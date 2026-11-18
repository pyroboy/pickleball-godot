"""Smooth, world-space focus post effects on top of the pixel viewport.

Pipeline it models (what the Godot shader would do):
  1. pixel viewport (240x427) upscaled with nearest filtering -> sharp pixel art
  2. focus mask from WORLD position: distance on the court from the focus point (ball/player),
     smoothstep falloff -> smooth ellipse in perspective, not a screen-space circle
  3. dim + cool tint + desaturate, weighted by the mask (float, no quantisation)
  4. blur: dual-filter (Kawase) blur on a 1/2-res copy, mixed in by the mask
  5. focus player, ball, trajectories and UI composited on top, never blurred
"""
import numpy as np
from math import tan, radians
from PIL import Image, ImageFilter
from scene import CAM, W, H

def world_ground(ox, oy, w, h, z):
    X, Y = np.meshgrid(np.arange(w), np.arange(h))
    u = ox + (X + 0.5) / z; v = oy + (Y + 0.5) / z
    xn = u / W * 2 - 1; yn = 1 - v / H * 2
    d = CAM.fwd[None, None] + xn[..., None] * CAM.th * CAM.right + yn[..., None] * CAM.tv * CAM.up
    t = np.where(d[..., 1] < -1e-6, -CAM.eye[1] / np.minimum(d[..., 1], -1e-6), 1e9)
    P = CAM.eye + d * t[..., None]
    return P[..., 0], P[..., 2], t

def smoothstep(a, b, x):
    k = np.clip((x - a) / (b - a), 0, 1); return k * k * (3 - 2 * k)

def kawase(img, z, passes=(1, 2, 3)):
    """Dual-filter style blur approximation: downsample 2x, a few widening taps, upsample."""
    im = Image.fromarray(img.astype(np.uint8))
    small = im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.BILINEAR)
    for p in passes:
        small = small.filter(ImageFilter.GaussianBlur(p * z * 0.5))
    return np.asarray(small.resize(im.size, Image.BILINEAR)).astype(float)

def focus_post(native, keep_native, focus_xz, ox=0, oy=0, w=None, h=None, z=3,
               r0=1.4, r1=4.5, dim=0.55, desat=0.45, blur=1.0, tint=(0.78, 0.82, 1.0)):
    """native: HxWx3 pixel image (crop region); keep_native: bool mask of pixels kept sharp."""
    nh, nw = native.shape[:2]
    w = w or nw * z; h = h or nh * z
    up = np.asarray(Image.fromarray(native).resize((w, h), Image.NEAREST)).astype(float)
    keep = np.asarray(Image.fromarray(keep_native.astype(np.uint8) * 255).resize((w, h), Image.NEAREST)) > 0
    x, zz, t = world_ground(ox, oy, w, h, z)
    dist = np.where(t < 1e8, np.hypot(x - focus_xz[0], (zz - focus_xz[1]) * 0.8), 30.0)
    m = smoothstep(r0, r1, dist)[..., None]
    out = up
    if blur > 0:
        b = kawase(up, z * blur)
        out = out * (1 - m) + b * m
    g = out.mean(2, keepdims=True)
    out = out * (1 - m * desat) + g * (m * desat)
    out = out * (1 - m * dim * (1 - np.array(tint)) - m * dim * 0.35 * np.array(tint))
    out = np.where(keep[..., None], up, out)
    return out.clip(0, 255).astype(np.uint8), keep


def dof_post(native, depth, keep, focus_d, z=3, ox=0, oy=0, in_focus=1.2, max_r=9.0, strength=1.0,
             dim=0.28, desat=0.3, tint=(0.86, 0.9, 1.0), soft_focus=None, soft_cap=1.6, feather=6):
    """Lens depth of field. Circle of confusion ~ |d - focus| / d (thin lens), with an in-focus range.
    Blur is a per-pixel mix of a small stack of Gaussian levels, so it grows smoothly with depth."""
    nh, nw = native.shape[:2]
    w, h = nw * z, nh * z
    up = np.asarray(Image.fromarray(native).resize((w, h), Image.NEAREST)).astype(float)
    D = np.asarray(Image.fromarray(depth.astype(np.float32), 'F').resize((w, h), Image.BILINEAR))
    kp = np.asarray(Image.fromarray(keep.astype(np.uint8) * 255).resize((w, h), Image.NEAREST)) > 0
    coc = np.clip(np.abs(D - focus_d) - in_focus, 0, None) / np.maximum(D, 0.1)
    r = np.clip(coc / 0.5, 0, 1) * max_r * strength
    s = np.zeros((h, w))
    if soft_focus is not None and soft_focus.any():
        sm = Image.fromarray(soft_focus.astype(np.uint8) * 255).resize((w, h), Image.NEAREST)
        sm = sm.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(feather))
        s = np.clip(np.asarray(sm).astype(float) / 255 * 1.6, 0, 1)
        r = r * (1 - s) + np.minimum(r, soft_cap) * s
    radii = [0.0, 1.0, 2.2, 3.8, 6.0, 9.0]
    stack = [up] + [np.asarray(Image.fromarray(up.astype(np.uint8)).filter(ImageFilter.GaussianBlur(rr))).astype(float) for rr in radii[1:]]
    out = np.zeros_like(up)
    for i in range(len(radii) - 1):
        a, b = radii[i], radii[i + 1]
        wgt = np.clip((r - a) / (b - a), 0, 1)
        sel = (r >= a) & ((r < b) | (i == len(radii) - 2))
        mix = stack[i] * (1 - wgt[..., None]) + stack[i + 1] * wgt[..., None]
        out[sel] = mix[sel]
    m = (np.clip(coc / 0.5, 0, 1) * (1 - s * 0.8))[..., None]
    g = out.mean(2, keepdims=True)
    out = out * (1 - m * desat) + g * (m * desat)
    out = out * (1 - m * dim * (1.15 - np.array(tint)))
    out = np.where(kp[..., None], up, out)
    return out.clip(0, 255).astype(np.uint8), r

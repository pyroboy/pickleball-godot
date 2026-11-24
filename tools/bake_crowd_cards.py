#!/usr/bin/env python3
"""Bake pixel cards for the barangay crowd and passers-by (visual only).

Same pipeline as the players (tools/bake_pixel_cards.py): every body part is built from
3D solids, rendered from a fixed set of views, quantised to three tones with a selective
outline and pre-compensated for the Filmic tonemap. Differences for background people:

  * 8 views (every 45 degrees) instead of 16; the rig snaps facing to the nearest one.
  * A coarser texel (CROWD_TEXEL m) to match how big they are on screen at the far end,
    so the art does not shimmer when it is minified.
  * Casual outfits generated from a seed: tees, polos, tanks and sandos, shorts and
    skirts, tsinelas, caps and bucket hats, all with explicit colours (no team tint).

Output:
  assets/crowd_cards/crowd_atlas.png   profiles in a grid of blocks (8 cols x 9 rows each)
  assets/crowd_cards/crowd_meta.json   grid, part anchors, per-profile block and the
                                       head / torso / shorts extents the rig stacks by

Usage: python3 tools/bake_crowd_cards.py [--sheet]
Run Godot with --import afterwards so the new PNG loads.
"""
import json, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_pixel_cards as B  # noqa: E402

ROOT = B.ROOT
OUT = os.path.join(ROOT, "assets/crowd_cards")
CROWD_TEXEL = 0.05       # m per texel (players: 0.028); ~ the screen grid at the far end
CROWD_CELL = 24          # px per cell
VIEWS = list(range(0, 16, 2))   # baked view indices in 22.5 degree units: 8 directions
PROFILES = 16
BLOCKS_PER_ROW = 4

SKINS = ["#f1cba6", "#e0ad85", "#c98f63", "#a87149", "#86563a"]
HAIR = ["#1d1613", "#2c1f18", "#3b2a1e", "#5a3a24", "#8f8a84"]
TOPS = ["#e0473b", "#3e7fd0", "#f2c84b", "#7cc490", "#f29ac0", "#ff9a4a", "#a98ae6", "#43c2b5",
        "#f2f0ea", "#2f4f86", "#d8d0b0", "#e86fa0", "#5a6b7a", "#c0392b"]
BOTTOMS = ["#2f4f86", "#3a3a48", "#c9a46a", "#5a5a66", "#7a4f3a", "#2e5e4e", "#8f7d58", "#1f2a44"]
SLIPPERS = ["#3e7fd0", "#e0473b", "#2a2a2a", "#f2f0ea", "#f2c84b", "#7cc490"]


def profile(i):
    r = np.random.default_rng(4100 + i)
    female = i % 2 == 1
    top_type = ["tee", "polo", "tank", "tee", "muscle_tank", "tee"][int(r.integers(6))]
    if female and top_type == "muscle_tank": top_type = "tee"
    # colours cycle with co-prime steps so every profile looks different (no repeats in 14)
    top = TOPS[(i * 5) % len(TOPS)]
    bottom = BOTTOMS[(i * 3) % len(BOTTOMS)]
    skin = SKINS[(i * 2 + i // 5) % len(SKINS)]
    hair_styles = ["bob", "ponytail", "bun", "curly"] if female else ["crew", "buzz", "curly", "crew"]
    head = {"hair": hair_styles[int(r.integers(len(hair_styles)))], "hair_color": HAIR[int(r.integers(len(HAIR)))]}
    roll = r.random()
    if roll < 0.18: head.update({"headwear": "bucket_hat", "headwear_color": ["#6f7550", "#d8d0b0", "#2f4f86"][int(r.integers(3))]})
    elif roll < 0.36: head.update({"headwear": "visor", "headwear_color": TOPS[int(r.integers(len(TOPS)))]})
    if r.random() < 0.15: head["sunglasses"] = True
    big = r.random()
    torso = {"shoulders": 0.88 if female else 1.0, "waist": 0.86 + (0.25 if big < 0.2 else 0.0),
             "chest": 0.35 if female else 0.15, "belly": 0.7 if big < 0.2 else 0.0,
             "hips": 0.98 if female else 1.0}
    bottom_type = "skirt_aline" if female and r.random() < 0.35 else "shorts"
    return {
        "name": "crowd_%02d" % i, "sex": "female" if female else "male", "skin": skin, "head": head,
        "torso": torso,
        "top": {"type": top_type, "color": top, "sleeve": top, "collar": top, "logo": top, "sleeve_length": 0.35},
        "bottom": {"type": bottom_type, "color": bottom, "tier": bottom, "length": 0.2, "flare": 0.05,
                   "thigh_cover": float(r.uniform(0.55, 0.95))},
        "arms": {"upper": 0.95, "fore": 0.95, "hand": 1.0},
        "legs": {"thigh": 1.0, "shin": 1.0},
        "shoes": {"color": SLIPPERS[int(r.integers(len(SLIPPERS)))], "sole": "#3a3a3a", "accent": "#3a3a3a", "width": 1.0},
    }


def extents(out, anchor):
    """(top, bottom, half_width) in texels from the anchor for a rendered cell."""
    ys, xs = np.nonzero(out >= 0)
    if not len(ys): return 0.0, 0.0, 0.0
    return float(anchor[1] - ys.min()), float(anchor[1] - ys.max() - 1), float(max(anchor[0] - xs.min(), xs.max() + 1 - anchor[0]))


def main():
    np.seterr(all="ignore")
    with open(B.META) as f: card_meta = json.load(f)
    B.CELL, B.TEXEL = CROWD_CELL, CROWD_TEXEL
    comp = B.make_compensator(float(card_meta.get("gain", 1.0)))
    grid = B.grid_for(card_meta)
    rows = int(card_meta["rows"])
    cols = len(VIEWS)
    bw, bh = cols * CROWD_CELL, rows * CROWD_CELL
    brows = (PROFILES + BLOCKS_PER_ROW - 1) // BLOCKS_PER_ROW
    atlas = np.zeros((brows * bh, BLOCKS_PER_ROW * bw, 4), np.uint8)
    profiles = []
    for i in range(PROFILES):
        pr = profile(i)
        parts = B.build_parts(pr, grid)
        bx, by = (i % BLOCKS_PER_ROW) * bw, (i // BLOCKS_PER_ROW) * bh
        ext = {}
        for name, (solids, decals) in parts.items():
            info = grid["parts"][name]
            mpt = CROWD_TEXEL / B.PART_SCALE.get(name, 1.0)
            for c, view in enumerate(VIEWS):
                out, keys, edge = B.render(solids, decals, view, info["anchor"], B.PART_ELEV.get(name, 0.0), mpt)
                y0, x0 = by + info["row"] * CROWD_CELL, bx + c * CROWD_CELL
                atlas[y0:y0 + CROWD_CELL, x0:x0 + CROWD_CELL] = B.colourise(out, keys, edge, "blue", comp)
                if view == 0 and name in ("head", "torso", "shorts"):
                    t, b, hw = extents(out, info["anchor"])
                    ext[name] = [round(t * CROWD_TEXEL, 4), round(b * CROWD_TEXEL, 4), round(hw * CROWD_TEXEL, 4)]
        profiles.append({"id": pr["name"], "sex": pr["sex"], "block": [bx // CROWD_CELL, by // CROWD_CELL], "extents": ext})
        print("baked", pr["name"])
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(atlas).save(os.path.join(OUT, "crowd_atlas.png"))
    meta = {"cell": [CROWD_CELL, CROWD_CELL], "cols": cols, "rows": rows, "view_deg": 45.0,
            "meters_per_texel": CROWD_TEXEL, "gain": card_meta.get("gain", 1.0),
            "atlas_px": [int(atlas.shape[1]), int(atlas.shape[0])], "parts": grid["parts"], "profiles": profiles}
    with open(os.path.join(OUT, "crowd_meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
        f.write("\n")
    if "--sheet" in sys.argv:
        a = atlas.astype(float)
        a[..., :3] = B.display_of(a[..., :3])
        os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
        Image.fromarray(a.round().astype(np.uint8), "RGBA").resize((atlas.shape[1] * 2, atlas.shape[0] * 2), Image.NEAREST).save(os.path.join(ROOT, "logs/crowd_cards_sheet.png"))
    print("crowd atlas %dx%d, %d profiles x %d views" % (atlas.shape[1], atlas.shape[0], PROFILES, cols))


if __name__ == "__main__":
    main()

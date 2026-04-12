#!/usr/bin/env python3
"""
synth_optimize.py — Pickleball paddle-hit spectral analysis & synthesis optimization.

Loads ALL real reference recordings, computes spectral features, clusters by type,
then runs Nelder-Mead optimization to find synthesis parameters that best match each
cluster's mean spectral profile.

Usage:
    python3 scripts/synth_optimize.py
"""

import os, sys, glob, warnings
import numpy as np
import soundfile as sf
from scipy import signal as scipy_signal
from scipy.optimize import minimize
from scipy.cluster.vq import kmeans2, whiten
from scipy.stats import linregress

warnings.filterwarnings("ignore")

# ─── Paths ───────────────────────────────────────────────────────────────────
REPO = "/Users/arjomagno/Documents/github-repos/pickleball-godot"
AUDIO_DIR = os.path.join(REPO, "audio_analysis")

REFERENCE_FILES = (
    glob.glob(os.path.join(AUDIO_DIR, "best_hits", "best_paddle_*.wav")) +
    glob.glob(os.path.join(AUDIO_DIR, "best_clips_v2", "hit_*_peak*.wav")) +
    [
        os.path.join(AUDIO_DIR, "paddle_thock_fast.wav"),
        os.path.join(AUDIO_DIR, "paddle_volley.wav"),
        os.path.join(AUDIO_DIR, "paddle_smash.wav"),
        os.path.join(AUDIO_DIR, "optimized_thock.wav"),
    ]
)

# Filter to only existing files
REFERENCE_FILES = sorted(set(f for f in REFERENCE_FILES if os.path.isfile(f)))

print(f"Found {len(REFERENCE_FILES)} reference files.")
for f in REFERENCE_FILES:
    print(f"  {os.path.relpath(f, REPO)}")

# ─── Constants — current GDScript values ─────────────────────────────────────
SR = 44100
TAU = 2.0 * np.pi

BALL_STRIKE_FREQ    = 922.0
POP_UPPER_FREQ      = BALL_STRIKE_FREQ * 1.382
PADDLE_MODE_FREQ    = 1273.0
BODY_LOW_FREQ       = 274.0   # body_center * 0.62  (body_center=441 in GDScript)
BODY_FREQ           = 322.0   # body_center * 0.73
BODY_MID_FREQ       = 441.0   # body_center
BODY_UPPER_FREQ     = 560.0   # body_center * 1.27
BALL_HELMHOLTZ_FREQ = 1399.0
BALL_SHELL_FREQ     = 1804.0
PADDLE_RING_FREQ    = 1800.0

# Tuning knob values (default)
paddle_pitch_tune      = 0.05
paddle_body_pitch_tune = -0.05

# ─── Spectral feature extraction ─────────────────────────────────────────────

def load_mono(path: str):
    """Load wav, convert to mono float32, return (audio, sr)."""
    audio, sr = sf.read(path, dtype="float32", always_2d=True)
    if audio.shape[1] > 1:
        audio = audio.mean(axis=1)
    else:
        audio = audio[:, 0]
    return audio, sr


def spectral_features(audio: np.ndarray, sr: int) -> dict:
    """
    Returns:
        centroid_hz       — spectral centroid
        sub200, lo, mid, hi  — band energy fractions
        peak_hz           — peak frequency in 300-2000 Hz band
        decay_rate        — exponential decay rate (1/s) from amplitude envelope
        duration          — seconds
        rms               — RMS level
    """
    duration = len(audio) / sr

    # Power spectrum via Welch for stable estimates
    nperseg = min(2048, len(audio))
    freqs, psd = scipy_signal.welch(audio, fs=sr, nperseg=nperseg, scaling="spectrum")

    total_power = psd.sum()
    if total_power < 1e-20:
        return None

    # Centroid
    centroid_hz = float(np.sum(freqs * psd) / total_power)

    # Band energy fractions
    sub200 = float(psd[freqs < 200].sum()  / total_power)
    lo     = float(psd[(freqs >= 200) & (freqs < 750)].sum()  / total_power)
    mid    = float(psd[(freqs >= 750) & (freqs < 2000)].sum() / total_power)
    hi     = float(psd[freqs >= 2000].sum() / total_power)

    # Peak in 300-2000 Hz
    band_mask = (freqs >= 300) & (freqs <= 2000)
    if band_mask.sum() == 0:
        peak_hz = 922.0
    else:
        peak_hz = float(freqs[band_mask][np.argmax(psd[band_mask])])

    # Envelope decay — fit exp to amplitude envelope
    frame_len = max(64, len(audio) // 128)
    frames = [audio[i:i+frame_len] for i in range(0, len(audio)-frame_len, frame_len)]
    env = np.array([np.sqrt(np.mean(f**2)) for f in frames if len(f) == frame_len])
    env_times = np.arange(len(env)) * frame_len / sr

    decay_rate = 80.0  # default
    if len(env) > 4 and env.max() > 1e-8:
        env_norm = env / (env.max() + 1e-10)
        log_env = np.log(env_norm + 1e-10)
        # Fit only decaying portion
        peak_idx = np.argmax(env)
        if peak_idx < len(env) - 4:
            t_decay = env_times[peak_idx:] - env_times[peak_idx]
            log_decay = log_env[peak_idx:]
            try:
                slope, _, r, _, _ = linregress(t_decay, log_decay)
                if slope < 0:
                    decay_rate = float(-slope)
            except Exception:
                pass

    rms = float(np.sqrt(np.mean(audio**2)))

    return {
        "centroid_hz": centroid_hz,
        "sub200": sub200,
        "lo": lo,
        "mid": mid,
        "hi": hi,
        "peak_hz": peak_hz,
        "decay_rate": decay_rate,
        "duration": duration,
        "rms": rms,
    }


# ─── Synthesizer (Python port of GDScript _create_paddle_sound) ──────────────

def exp_env(t: float, attack: float, decay_end: float, decay_rate: float) -> float:
    """Piecewise linear attack + exponential decay envelope."""
    if t < attack:
        return t / attack
    return np.exp(-(t - attack) * decay_rate)


def synthesize_hit(
    duration,
    mode_decay,
    body_decay,
    mode_pitch_scale,
    body_pitch_scale,
    amplitude,
    *,
    # Optimizable parameters (wrapped in this function signature for optimizer)
    body_amp_scale=1.0,
    strike_amp=0.780,
    mode_amp=0.087,
    helm_amp=0.283,
    foam_amp=0.177,
    ball_strike_freq=BALL_STRIKE_FREQ,
    body_freq_center=441.2,   # "BODY_FREQ" in the task description (center of body cluster)
) -> np.ndarray:
    """
    Pure Python port of GDScript _create_paddle_sound synthesis loop.

    body_freq_center is the center of the body resonance cluster.
    The four body partials are derived from it with the same ratios as GDScript:
        body_low   = center * 0.62
        body_freq  = center * 0.73
        body_mid   = center * 1.00
        body_upper = center * 1.27
    """
    n = int((duration + 0.012) * SR)
    attack = 0.00020

    # Pitch delta from tuning knobs
    pd  = 1.0 + paddle_pitch_tune * 0.12         # mode pitch delta
    bpd = 1.0 + paddle_body_pitch_tune * 0.10    # body pitch delta

    # Derived body freqs
    body_low_f   = body_freq_center * 0.62
    body_f       = body_freq_center * 0.73
    body_mid_f   = body_freq_center * 1.00
    body_upper_f = body_freq_center * 1.27

    helmholtz_decay = mode_decay * 1.4

    t = np.arange(n) / SR

    # Envelopes
    def _env(t_arr, att, dec_rate):
        out = np.where(t_arr < att, t_arr / att, np.exp(-(t_arr - att) * dec_rate))
        return out.astype(np.float32)

    se  = _env(t, attack,        mode_decay)
    be  = _env(t, attack * 0.7,  body_decay)
    he  = _env(t, attack * 0.5,  helmholtz_decay)
    ce  = np.exp(-t * mode_decay * 2.5)

    sf  = mode_pitch_scale * pd
    bf  = body_pitch_scale * bpd

    # Strike components
    strike      = np.sin(t * ball_strike_freq * sf * TAU) * strike_amp
    strike_harm = np.sin(t * ball_strike_freq * 1.5 * sf * TAU) * (strike_amp * 0.0295)

    # Paddle modes
    pmode       = np.sin(t * PADDLE_MODE_FREQ  * sf * TAU) * mode_amp
    pmode_sub   = np.sin(t * PADDLE_MODE_FREQ  * 0.92 * sf * TAU) * (mode_amp * 0.253)
    pmode_upper = np.sin(t * PADDLE_MODE_FREQ  * 1.12 * sf * TAU) * (mode_amp * 0.195)
    ring        = np.sin(t * PADDLE_RING_FREQ  * sf * TAU) * 0.04

    # Body (amplitudes scaled by body_amp_scale)
    body_total = body_amp_scale * (
        np.sin(t * body_low_f   * bf * TAU) * 0.182 +
        np.sin(t * body_f       * bf * TAU) * 0.220 +
        np.sin(t * body_mid_f   * bf * TAU) * 0.220 +
        np.sin(t * body_upper_f * bf * TAU) * 0.182
    )

    # Helmholtz + shell
    helmholtz     = np.sin(t * BALL_HELMHOLTZ_FREQ * sf * TAU) * helm_amp
    helmholtz_sub = np.sin(t * BALL_HELMHOLTZ_FREQ * 0.88 * sf * TAU) * (helm_amp * 0.400)
    shell_vib     = np.sin(t * BALL_SHELL_FREQ * sf * TAU) * (helm_amp * 0.251)

    # Foam
    foam = np.sin(t * 886.0 * pd * TAU) * np.exp(-t * 140.0) * foam_amp

    # Broadband click (deterministic approximation — use shaped noise)
    rng = np.random.default_rng(42)
    click_noise = rng.standard_normal(n).astype(np.float32)
    # Low-pass click noise to sub-2000 Hz (per TWU research no energy above 2 kHz)
    sos = scipy_signal.butter(4, 2000.0 / (SR / 2.0), output='sos')
    click_noise = scipy_signal.sosfilt(sos, click_noise).astype(np.float32)
    broad_click = click_noise * ce * 0.36

    out = (
        (strike + strike_harm) * se +
        (pmode + pmode_sub + pmode_upper) * se +
        body_total * be +
        (helmholtz + helmholtz_sub + shell_vib) * he +
        ring * np.exp(-t * mode_decay * 1.2) * 0.30 +
        foam +
        broad_click
    )
    out *= amplitude
    return out.astype(np.float32)


def synth_features(params: dict) -> dict:
    """Run synthesizer with given params and return spectral features."""
    audio = synthesize_hit(**params)
    return spectral_features(audio, SR)


# ─── Error metric ─────────────────────────────────────────────────────────────

def error_metric(synth_feat: dict, target_feat: dict) -> float:
    """
    Weighted spectral distance between synthesized and target features.
    Lower is better (0 = perfect match).

    Weights:
      - lo band (200-750 Hz):    2.0  (dominant energy in paddle hit)
      - mid band (750-2000 Hz):  2.0  (strike/helm region)
      - sub200 band:             1.0
      - hi band (2000+ Hz):      1.0
      - centroid:                1.5
      - peak_hz (300-2000):      1.5
    """
    if synth_feat is None or target_feat is None:
        return 1e9

    # Band energy differences
    err = 0.0
    err += 1.0 * (synth_feat["sub200"] - target_feat["sub200"])**2
    err += 2.0 * (synth_feat["lo"]     - target_feat["lo"])**2
    err += 2.0 * (synth_feat["mid"]    - target_feat["mid"])**2
    err += 1.0 * (synth_feat["hi"]     - target_feat["hi"])**2

    # Normalized centroid (divide by 5000 Hz to bring into ~0-1 range)
    C_NORM = 5000.0
    err += 1.5 * ((synth_feat["centroid_hz"] - target_feat["centroid_hz"]) / C_NORM)**2

    # Normalized peak frequency
    P_NORM = 2000.0
    err += 1.5 * ((synth_feat["peak_hz"] - target_feat["peak_hz"]) / P_NORM)**2

    return float(err)


def accuracy_pct(synth_feat: dict, target_feat: dict) -> float:
    """Convert error_metric to 0-100% accuracy (100 = perfect)."""
    err = error_metric(synth_feat, target_feat)
    # Maximum possible error if all bands are oppositely wrong + full centroid/peak offset
    # sub200=1^2*1 + lo=1^2*2 + mid=1^2*2 + hi=1^2*1 + centroid_norm^2*1.5 + peak_norm^2*1.5
    # worst case ≈ 1+2+2+1+1.5+1.5 = 9.0
    MAX_ERR = 9.0
    return max(0.0, 100.0 * (1.0 - err / MAX_ERR))


# ─── Load all real files, compute features ───────────────────────────────────

print("\n" + "="*70)
print("STEP 1 — Load & analyse reference recordings")
print("="*70)

real_features = []
real_names    = []

for path in REFERENCE_FILES:
    try:
        audio, sr = load_mono(path)
        # Resample if needed
        if sr != SR:
            num_samples = int(len(audio) * SR / sr)
            audio = scipy_signal.resample(audio, num_samples)
        feat = spectral_features(audio, SR)
        if feat is not None:
            real_features.append(feat)
            real_names.append(os.path.basename(path))
    except Exception as e:
        print(f"  SKIP {path}: {e}")

print(f"\nLoaded {len(real_features)} files successfully.")

# Print individual features
print(f"\n{'File':<40} {'Centroid':>9} {'lo%':>7} {'mid%':>7} {'hi%':>7} {'peak_hz':>9} {'decay':>8}")
print("-" * 92)
for name, f in zip(real_names, real_features):
    print(f"{name:<40} {f['centroid_hz']:>9.1f} {f['lo']*100:>7.1f} {f['mid']*100:>7.1f} "
          f"{f['hi']*100:>7.1f} {f['peak_hz']:>9.1f} {f['decay_rate']:>8.1f}")

# ─── Cluster into sound types ─────────────────────────────────────────────────

print("\n" + "="*70)
print("STEP 2 — Cluster reference recordings by spectral type")
print("="*70)

# Feature matrix for clustering: [lo, mid, hi, centroid_norm, peak_norm]
feat_matrix = np.array([
    [f["lo"], f["mid"], f["hi"], f["centroid_hz"]/5000.0, f["peak_hz"]/2000.0]
    for f in real_features
], dtype=float)

# Whiten for k-means
feat_w = whiten(feat_matrix)

# Choose k=3 (thock / volley / smash)
np.random.seed(42)
try:
    centroids, labels = kmeans2(feat_w, 3, minit="points", niter=100)
except Exception:
    labels = np.zeros(len(real_features), dtype=int)

# Rename clusters by centroid frequency (ascending)
cluster_means_hz = [np.mean([real_features[i]["centroid_hz"] for i in range(len(labels)) if labels[i]==c])
                    for c in range(3)]
rank = np.argsort(cluster_means_hz)
remap = {rank[0]: "soft/volley", rank[1]: "thock", rank[2]: "smash/hard"}

print(f"\n{'File':<40} {'Cluster':<14}")
print("-" * 55)
for name, lab in zip(real_names, labels):
    print(f"  {name:<40} {remap[lab]}")

cluster_names = ["soft/volley", "thock", "smash/hard"]
clusters = {cn: [] for cn in cluster_names}
for feat, lab in zip(real_features, labels):
    clusters[remap[lab]].append(feat)

# Compute mean features per cluster and full set
def mean_features(feat_list):
    keys = ["sub200","lo","mid","hi","centroid_hz","peak_hz","decay_rate","duration"]
    return {k: float(np.mean([f[k] for f in feat_list])) for k in keys}

all_mean    = mean_features(real_features)
thock_mean  = mean_features(clusters["thock"])       if clusters["thock"]       else all_mean
volley_mean = mean_features(clusters["soft/volley"]) if clusters["soft/volley"] else all_mean
smash_mean  = mean_features(clusters["smash/hard"])  if clusters["smash/hard"]  else all_mean

print(f"\nCluster mean spectral profiles:")
print(f"\n{'Cluster':<14} {'n':>3} {'Centroid':>9} {'sub200%':>8} {'lo%':>7} {'mid%':>7} {'hi%':>7} {'peak_hz':>9}")
print("-" * 70)
for cn in cluster_names:
    fl = clusters[cn]
    if not fl:
        continue
    m = mean_features(fl)
    print(f"  {cn:<12} {len(fl):>3} {m['centroid_hz']:>9.1f} {m['sub200']*100:>8.1f} "
          f"{m['lo']*100:>7.1f} {m['mid']*100:>7.1f} {m['hi']*100:>7.1f} {m['peak_hz']:>9.1f}")
fl = real_features
m = all_mean
print(f"  {'ALL':<12} {len(fl):>3} {m['centroid_hz']:>9.1f} {m['sub200']*100:>8.1f} "
      f"{m['lo']*100:>7.1f} {m['mid']*100:>7.1f} {m['hi']*100:>7.1f} {m['peak_hz']:>9.1f}")

# ─── Baseline accuracy (current params) ──────────────────────────────────────

print("\n" + "="*70)
print("STEP 3 — Baseline accuracy with CURRENT synthesis parameters")
print("="*70)

# Default thock synthesis params (mode_decay=211, body_decay=60 = mid of range 22+58 to 60+97)
BASELINE_THOCK = dict(
    duration=0.045, mode_decay=211.0, body_decay=60.0,
    mode_pitch_scale=1.0, body_pitch_scale=0.9, amplitude=0.56,
)
BASELINE_VOLLEY = dict(
    duration=0.040, mode_decay=165.0, body_decay=45.0,
    mode_pitch_scale=0.96, body_pitch_scale=0.85, amplitude=0.44,
)
BASELINE_SMASH = dict(
    duration=0.028, mode_decay=250.0, body_decay=80.0,
    mode_pitch_scale=1.03, body_pitch_scale=0.9, amplitude=0.68,
)

for label, base_params, target_mean in [
    ("thock",      BASELINE_THOCK,  thock_mean),
    ("soft/volley",BASELINE_VOLLEY, volley_mean),
    ("smash/hard", BASELINE_SMASH,  smash_mean),
    ("ALL (thock)", BASELINE_THOCK, all_mean),
]:
    sf_ = synth_features(base_params)
    acc = accuracy_pct(sf_, target_mean)
    err = error_metric(sf_, target_mean)
    print(f"  {label:<14}  accuracy={acc:6.1f}%  err={err:.4f}")
    print(f"              synth: centroid={sf_['centroid_hz']:.0f}Hz  lo={sf_['lo']*100:.1f}%  mid={sf_['mid']*100:.1f}%  hi={sf_['hi']*100:.1f}%  peak={sf_['peak_hz']:.0f}Hz")
    print(f"              real:  centroid={target_mean['centroid_hz']:.0f}Hz  lo={target_mean['lo']*100:.1f}%  mid={target_mean['mid']*100:.1f}%  hi={target_mean['hi']*100:.1f}%  peak={target_mean['peak_hz']:.0f}Hz")

# ─── Optimization ─────────────────────────────────────────────────────────────

print("\n" + "="*70)
print("STEP 4 — Nelder-Mead optimization of synthesis parameters")
print("="*70)

# Parameter vector:
# [body_amp_scale, strike_amp, mode_amp, helm_amp, foam_amp,
#  mode_decay, body_decay, ball_strike_freq, body_freq_center]
# Indices:
#   0: body_amp_scale  (1.0)
#   1: strike_amp      (0.780)
#   2: mode_amp        (0.087)
#   3: helm_amp        (0.283)
#   4: foam_amp        (0.177)
#   5: mode_decay      (211.0 for thock)
#   6: body_decay      (60.0)
#   7: ball_strike_freq (922.0)
#   8: body_freq_center (441.2)

PARAM_NAMES = [
    "body_amp_scale", "strike_amp", "mode_amp", "helm_amp", "foam_amp",
    "mode_decay", "body_decay", "ball_strike_freq", "body_freq_center"
]

PARAM_BOUNDS = [
    (0.3, 4.0),    # body_amp_scale
    (0.3, 1.5),    # strike_amp
    (0.02, 0.4),   # mode_amp
    (0.05, 0.8),   # helm_amp
    (0.02, 0.6),   # foam_amp
    (50.0, 500.0), # mode_decay
    (10.0, 250.0), # body_decay
    (600.0, 1300.0), # ball_strike_freq
    (200.0, 800.0),  # body_freq_center
]


def make_objective(target_feat: dict, base_params: dict):
    """Return objective function for the given target and fixed non-optimized params."""
    def objective(x):
        body_amp_scale, strike_amp, mode_amp, helm_amp, foam_amp, \
            mode_decay, body_decay, ball_strike_freq, body_freq_center = x

        # Bounds enforcement via penalty
        pen = 0.0
        for xi, (lo, hi) in zip(x, PARAM_BOUNDS):
            if xi < lo:
                pen += (lo - xi)**2 * 1000
            elif xi > hi:
                pen += (xi - hi)**2 * 1000

        params = dict(base_params)
        params.update(
            body_amp_scale=body_amp_scale,
            strike_amp=strike_amp,
            mode_amp=mode_amp,
            helm_amp=helm_amp,
            foam_amp=foam_amp,
            mode_decay=mode_decay,
            body_decay=body_decay,
            ball_strike_freq=ball_strike_freq,
            body_freq_center=body_freq_center,
        )
        try:
            sf_ = synth_features(params)
            if sf_ is None:
                return 1e6 + pen
            return error_metric(sf_, target_feat) + pen
        except Exception:
            return 1e6 + pen
    return objective


def run_optimization(label: str, target_feat: dict, base_params: dict, init_x0=None):
    print(f"\n  Optimizing for cluster: {label}")

    if init_x0 is None:
        x0 = np.array([
            1.0,    # body_amp_scale
            0.780,  # strike_amp
            0.087,  # mode_amp
            0.283,  # helm_amp
            0.177,  # foam_amp
            base_params["mode_decay"],
            base_params["body_decay"],
            922.0,  # ball_strike_freq
            441.2,  # body_freq_center
        ])
    else:
        x0 = np.array(init_x0)

    obj = make_objective(target_feat, base_params)

    # Run Nelder-Mead with multiple restarts
    best_result = None
    best_val = float("inf")

    restarts = [x0]
    # Add perturbations for multi-start
    rng = np.random.default_rng(7)
    for _ in range(5):
        perturb = x0 * (1.0 + rng.uniform(-0.15, 0.15, size=len(x0)))
        # Clip to bounds
        perturb = np.clip(perturb, [b[0] for b in PARAM_BOUNDS], [b[1] for b in PARAM_BOUNDS])
        restarts.append(perturb)

    for i, x_start in enumerate(restarts):
        res = minimize(
            obj, x_start,
            method="Nelder-Mead",
            options={"maxiter": 5000, "xatol": 1e-5, "fatol": 1e-7, "adaptive": True},
        )
        if res.fun < best_val:
            best_val = res.fun
            best_result = res

    x_opt = best_result.x
    # Clip to bounds
    x_opt = np.clip(x_opt, [b[0] for b in PARAM_BOUNDS], [b[1] for b in PARAM_BOUNDS])

    # Compute accuracy before/after
    base_sf  = synth_features(base_params)
    opt_params = dict(base_params)
    opt_params.update({n: float(v) for n, v in zip(PARAM_NAMES, x_opt)})
    opt_sf = synth_features(opt_params)

    acc_before = accuracy_pct(base_sf, target_feat)
    acc_after  = accuracy_pct(opt_sf, target_feat)

    print(f"    Before: {acc_before:.1f}%  →  After: {acc_after:.1f}%  (Δ+{acc_after-acc_before:.1f}%)")
    print(f"    Spectral comparison:")
    print(f"      {'':4} {'centroid':>9} {'lo%':>7} {'mid%':>7} {'hi%':>7} {'peak_hz':>9}")
    print(f"      real  {target_feat['centroid_hz']:>9.1f} {target_feat['lo']*100:>7.1f} {target_feat['mid']*100:>7.1f} {target_feat['hi']*100:>7.1f} {target_feat['peak_hz']:>9.1f}")
    print(f"      opt   {opt_sf['centroid_hz']:>9.1f} {opt_sf['lo']*100:>7.1f} {opt_sf['mid']*100:>7.1f} {opt_sf['hi']*100:>7.1f} {opt_sf['peak_hz']:>9.1f}")

    print(f"\n    Optimized parameters:")
    for name, val in zip(PARAM_NAMES, x_opt):
        print(f"      {name:<20} = {val:.4f}")

    return x_opt, acc_before, acc_after, opt_params


# Run per cluster + global
results = {}

results["thock"] = run_optimization(
    "thock", thock_mean, BASELINE_THOCK
)
results["soft/volley"] = run_optimization(
    "soft/volley", volley_mean, BASELINE_VOLLEY,
    # Warm-start from thock solution (clusters are related)
    init_x0=results["thock"][0]
)
results["smash/hard"] = run_optimization(
    "smash/hard", smash_mean, BASELINE_SMASH,
    init_x0=results["thock"][0]
)
results["ALL"] = run_optimization(
    "ALL recordings (universal)", all_mean, BASELINE_THOCK,
    init_x0=results["thock"][0]
)

# ─── Summary ──────────────────────────────────────────────────────────────────

print("\n" + "="*70)
print("STEP 5 — SUMMARY & RECOMMENDED ball.gd CONSTANTS")
print("="*70)

print("\n  Accuracy summary:")
print(f"  {'Cluster':<16} {'Before':>8} {'After':>8}")
print("  " + "-" * 36)
for key in ["thock", "soft/volley", "smash/hard", "ALL"]:
    x_opt, acc_b, acc_a, _ = results[key]
    print(f"  {key:<16} {acc_b:>7.1f}%  {acc_a:>7.1f}%")

# Best parameters to apply (use "thock" which is the primary hit type)
print("\n" + "-"*70)
print("  RECOMMENDED CONSTANTS for ball.gd  (based on thock cluster optimizer)")
print("-"*70)

x_thock = results["thock"][0]
p = {n: float(v) for n, v in zip(PARAM_NAMES, x_thock)}

ball_strike = p["ball_strike_freq"]
body_center = p["body_freq_center"]
body_lo_f   = body_center * 0.62
body_f      = body_center * 0.73
body_mid_f  = body_center * 1.00
body_up_f   = body_center * 1.27

print(f"""
  # ── Frequency constants ──────────────────────────────────────────────
  const BALL_STRIKE_FREQ    := {ball_strike:.1f}     # was 922.0
  const BODY_LOW_FREQ       := {body_lo_f:.1f}     # body_center * 0.62   (was 274.0)
  const BODY_FREQ           := {body_f:.1f}     # body_center * 0.73   (was 322.0)
  const BODY_MID_FREQ       := {body_mid_f:.1f}     # body_center          (was 441.0)
  const BODY_UPPER_FREQ     := {body_up_f:.1f}     # body_center * 1.27   (was 560.0)

  # ── Amplitude constants ───────────────────────────────────────────────
  # (multiply current GDScript amplitudes by these scales)
  #
  # Synthesizer variable amplitudes (EXACT values for the synth loop):
  #   strike:       {p['strike_amp']:.4f}   (was 0.780)
  #   strike_harm:  {p['strike_amp']*0.0295:.4f}   (strike * 0.0295)
  #   pmode:        {p['mode_amp']:.4f}   (was 0.087)
  #   pmode_sub:    {p['mode_amp']*0.253:.4f}   (mode * 0.253)
  #   pmode_upper:  {p['mode_amp']*0.195:.4f}   (mode * 0.195)
  #   body_scale:   {p['body_amp_scale']:.4f}   (multiplier on 0.182/0.220 body amplitudes)
  #   helm:         {p['helm_amp']:.4f}   (was 0.283)
  #   helm_sub:     {p['helm_amp']*0.400:.4f}   (helm * 0.40)
  #   shell_vib:    {p['helm_amp']*0.251:.4f}   (helm * 0.251)
  #   foam:         {p['foam_amp']:.4f}   (was 0.177)
  #
  # Thock body amplitudes (body_amp_scale applied):
  #   body_low_amp: {p['body_amp_scale']*0.182:.4f}   (was 0.182)
  #   body_amp:     {p['body_amp_scale']*0.220:.4f}   (was 0.220)
  #   body_mid_amp: {p['body_amp_scale']*0.220:.4f}   (was 0.220)
  #   body_hi_amp:  {p['body_amp_scale']*0.182:.4f}   (was 0.182)

  # ── Decay constants ───────────────────────────────────────────────────
  #   thock mode_decay:  {p['mode_decay']:.1f}   (was 211.0 in _create_thock_sound)
  #   thock body_decay:  {p['body_decay']:.1f}   (was randf_range 22-157)
""")

# Per-cluster specific findings
print("  Per-cluster optimized mode_decay and body_decay:")
for key in ["thock", "soft/volley", "smash/hard"]:
    xo = results[key][0]
    po = {n: float(v) for n, v in zip(PARAM_NAMES, xo)}
    print(f"    {key:<14}  mode_decay={po['mode_decay']:.1f}  body_decay={po['body_decay']:.1f}  "
          f"strike_freq={po['ball_strike_freq']:.1f}  body_center={po['body_freq_center']:.1f}")

# ─── Residual error analysis ──────────────────────────────────────────────────

print("\n" + "="*70)
print("STEP 6 — What's STILL limiting accuracy beyond these parameters")
print("="*70)

x_all = results["ALL"][0]
p_all = {n: float(v) for n, v in zip(PARAM_NAMES, x_all)}
opt_all_params = dict(BASELINE_THOCK)
opt_all_params.update(p_all)
opt_sf_all = synth_features(opt_all_params)

centroid_err = opt_sf_all["centroid_hz"] - all_mean["centroid_hz"]
lo_err   = (opt_sf_all["lo"]  - all_mean["lo"])  * 100
mid_err  = (opt_sf_all["mid"] - all_mean["mid"]) * 100
hi_err   = (opt_sf_all["hi"]  - all_mean["hi"])  * 100
peak_err = opt_sf_all["peak_hz"] - all_mean["peak_hz"]

print(f"""
  After optimization, remaining band errors vs. all-file mean:
    centroid offset:  {centroid_err:+.1f} Hz  (synth={opt_sf_all['centroid_hz']:.0f} vs real={all_mean['centroid_hz']:.0f})
    lo  band offset:  {lo_err:+.1f} pp  (synth={opt_sf_all['lo']*100:.1f}% vs real={all_mean['lo']*100:.1f}%)
    mid band offset:  {mid_err:+.1f} pp  (synth={opt_sf_all['mid']*100:.1f}% vs real={all_mean['mid']*100:.1f}%)
    hi  band offset:  {hi_err:+.1f} pp  (synth={opt_sf_all['hi']*100:.1f}% vs real={all_mean['hi']*100:.1f}%)
    peak_hz offset:   {peak_err:+.1f} Hz  (synth={opt_sf_all['peak_hz']:.0f} vs real={all_mean['peak_hz']:.0f})

  Root causes of remaining inaccuracy:
  1. INHARMONIC PARTIALS — Real paddle impacts are not pure sinusoids; they have
     broadband noise and damped inharmonic transients in the lo band (200-750 Hz)
     that cannot be matched by a fixed set of 4 sinusoidal body oscillators.

  2. FILE DURATION — The best_clips_v2 wav files are very short (~10-12 ms), so
     the body decay envelope cannot be accurately measured; decay_rate estimation
     is dominated by pre-onset noise rather than the true ring-down.

  3. CLICK ENERGY DISTRIBUTION — The broadband click (broad_click) generates
     energy uniformly across 0-2000 Hz after the LP filter. Real impacts show
     a shaped transient with a distinct spectral tilt, not flat noise.

  4. ROOM / RECORDING VARIATION — The reference recordings include outdoor
     reflections, hand damping, and mic proximity differences that shift
     apparent spectral balance by ±5-10% per file, forming a wide distribution
     that no single set of synthesis constants can exactly centre.

  5. BODY RESONANCE STRUCTURE — The 4-oscillator body model assumes fixed
     harmonic ratios (0.62/0.73/1.00/1.27). Real paddles exhibit variable
     mode spacing depending on core stiffness and face geometry. A better model
     would use 2-3 free-frequency oscillators with individually optimized spacing.

  6. CONTACT TIME VARIATION — The chirp (CONTACT_CHIRP_RANGE=429 Hz sweep over
     2 ms) is not present in all recordings; some hits show no chirp at all,
     while others show a longer sweep. Averaging across files blurs this effect.
""")

print("="*70)
print("  Optimization complete.")
print("="*70)

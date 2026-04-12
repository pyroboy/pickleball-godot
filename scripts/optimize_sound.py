#!/usr/bin/env python3
"""
Pickleball Sound Spectral Optimizer
====================================
Uses scipy.optimize.differential_evolution to find optimal synthesis
parameters that minimize spectral distance from the real reference recording.

This is the "ultrathink" approach: systematic numerical optimization
instead of manual parameter guessing.
"""

import numpy as np
import wave
import json
from pathlib import Path
from scipy.optimize import differential_evolution
from scipy.fft import fft, fftfreq
from scipy.ndimage import uniform_filter1d
from scipy import signal as sp_signal

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

SAMPLE_RATE = 44100
OUTPUT_DIR = Path("/Users/arjomagno/Documents/github-repos/pickleball-godot/audio_analysis")


def load_wav(filepath):
    with wave.open(str(filepath), 'r') as wf:
        channels = wf.getnchannels()
        nframes = wf.getnframes()
        raw = wf.readframes(nframes)
    data = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return data


def save_wav(filename, samples, sr=44100):
    samples = np.clip(samples, -1.0, 1.0)
    int_samples = (samples * 32767).astype(np.int16)
    with wave.open(str(filename), 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(int(sr))
        wf.writeframes(int_samples.tobytes())


def highpass(data, cutoff=80, sr=44100, order=4):
    sos = sp_signal.butter(order, cutoff, btype='high', fs=sr, output='sos')
    return sp_signal.sosfiltfilt(sos, data)


def extract_reference_hits(ref_path, n_hits=5):
    """Extract and return the cleanest reference hits."""
    data = load_wav(str(ref_path))
    data = highpass(data, cutoff=80, sr=SAMPLE_RATE)

    # Detect hits
    window = max(int(SAMPLE_RATE * 0.001), 1)
    envelope = np.sqrt(np.convolve(data**2, np.ones(window)/window, mode='same'))
    peak_env = envelope.max()
    threshold = peak_env * 10**(-15 / 20)
    min_gap = int(SAMPLE_RATE * 0.250)
    clip_samples = int(SAMPLE_RATE * 0.040)

    hits = []
    i = 0
    while i < len(data) - clip_samples:
        if envelope[i] > threshold:
            region_end = min(i + clip_samples * 2, len(data))
            region = envelope[i:region_end]
            peak_idx = i + np.argmax(region)
            start = max(0, peak_idx - int(SAMPLE_RATE * 0.005))
            end = min(len(data), start + clip_samples * 2)
            raw_clip = data[start:end]

            # Find onset
            env = np.abs(raw_clip)
            env_smooth = uniform_filter1d(env, size=int(SAMPLE_RATE * 0.0003))
            peak = env_smooth.max()
            onset_candidates = np.where(env_smooth > peak * 0.15)[0]
            onset = max(0, onset_candidates[0] - int(SAMPLE_RATE * 0.001)) if len(onset_candidates) > 0 else 0
            clean_clip = raw_clip[onset:onset + clip_samples]

            if len(clean_clip) < clip_samples:
                padded = np.zeros(clip_samples)
                padded[:len(clean_clip)] = clean_clip
                clean_clip = padded

            peak_amp = np.max(np.abs(clean_clip))
            if 0.08 < peak_amp < 0.95:
                hits.append(clean_clip)
            i = peak_idx + min_gap
        else:
            i += 1

    # Sort by peak amplitude, return top n
    hits.sort(key=lambda h: np.max(np.abs(h)), reverse=True)
    return hits[:n_hits]


def compute_power_spectrum(samples, sr=44100, max_freq=5000):
    """Compute normalized power spectrum up to max_freq."""
    N = max(len(samples), sr // 10)
    padded = np.zeros(N)
    padded[:len(samples)] = samples
    yf = np.abs(fft(padded))[:N // 2]
    xf = fftfreq(N, 1.0 / sr)[:N // 2]
    mask = xf <= max_freq
    power = yf[mask] ** 2
    total = power.sum()
    if total < 1e-10:
        return np.zeros_like(power), xf[mask]
    return power / total, xf[mask]


def cosine_similarity(a, b):
    """Cosine similarity between two vectors."""
    dot = np.dot(a, b)
    na = np.sqrt(np.dot(a, a))
    nb = np.sqrt(np.dot(b, b))
    if na < 1e-10 or nb < 1e-10:
        return 0.0
    return dot / (na * nb)


# ─────────────────────────────────────────────────────────────────
# Parameterized Synthesis
# ─────────────────────────────────────────────────────────────────

def synthesize(params, duration=0.028, amplitude=0.84):
    """
    Parameterized pickleball paddle hit synthesis.

    params = [
        strike_freq,        # 0: primary strike frequency (Hz)
        strike_amp,         # 1: strike amplitude
        strike_harm_amp,    # 2: strike 1.5x harmonic amplitude
        mode_freq,          # 3: paddle mode frequency (Hz)
        mode_amp,           # 4: mode amplitude
        body_freq_center,   # 5: body center frequency (Hz)
        body_amp,           # 6: body amplitude
        body_spread,        # 7: body bandwidth spread factor
        helmholtz_freq,     # 8: Helmholtz frequency
        helmholtz_amp,      # 9: Helmholtz amplitude
        brightness_amp,     # 10: 2k+ brightness amplitude
        brightness_freq,    # 11: brightness center freq
        attack_time,        # 12: attack time (seconds)
        strike_decay,       # 13: strike decay rate
        mode_decay,         # 14: mode decay rate
        body_decay,         # 15: body decay rate
        foam_freq,          # 16: foam bloom frequency
        foam_amp,           # 17: foam bloom amplitude
        chirp_range,        # 18: contact chirp range (Hz)
    ]
    """
    num_samples = int(duration * SAMPLE_RATE)
    t = np.arange(num_samples) / SAMPLE_RATE
    TAU = 2.0 * np.pi

    (strike_freq, strike_amp, strike_harm_amp, mode_freq, mode_amp,
     body_freq_center, body_amp, body_spread, helmholtz_freq, helmholtz_amp,
     brightness_amp, brightness_freq, attack_time, strike_decay,
     mode_decay, body_decay, foam_freq, foam_amp, chirp_range) = params

    # Contact chirp
    contact_duration = 0.002
    chirp_factor = np.ones_like(t)
    mask = t < contact_duration
    phase = t[mask] / contact_duration
    chirp_factor[mask] = 1.0 + (1.0 - phase) * (chirp_range / max(strike_freq, 1)) * 0.3

    # Envelopes
    def env(t, atk, decay):
        e = np.zeros_like(t)
        rising = t < atk
        e[rising] = t[rising] / max(atk, 0.0001)
        falling = t >= atk
        e[falling] = np.exp(-(t[falling] - atk) * decay)
        return e

    strike_env = env(t, attack_time, strike_decay)
    mode_env = env(t, attack_time, mode_decay)
    body_env = env(t, attack_time * 0.7, body_decay)
    click_env = np.exp(-t * (strike_decay * 2.5))
    helmholtz_env = env(t, attack_time * 0.5, mode_decay * 1.4)

    # ─── Oscillators ───

    # PRIMARY: Strike tone (~920 Hz)
    strike = np.sin(t * strike_freq * chirp_factor * TAU) * strike_amp
    strike_harm = np.sin(t * strike_freq * 1.5 * chirp_factor * TAU) * strike_harm_amp

    # Mode (~1185 Hz)
    mode = np.sin(t * mode_freq * chirp_factor * TAU) * mode_amp
    mode_sub = np.sin(t * mode_freq * 0.92 * TAU) * mode_amp * 0.25
    mode_upper = np.sin(t * (mode_freq * 1.12) * TAU) * mode_amp * 0.2

    # Body (200-500 Hz band) — spread across multiple frequencies
    body_freqs = [
        body_freq_center * 0.85,   # ~187 Hz
        body_freq_center,           # ~300 Hz
        body_freq_center * 1.27,   # ~380 Hz
        body_freq_center * 1.53,   # ~460 Hz
    ]
    body_total = np.zeros_like(t)
    for i, bf in enumerate(body_freqs):
        amp_scale = 1.0 - abs(i - 1.5) * 0.15  # peak in middle
        body_total += np.sin(t * bf * TAU) * body_amp * amp_scale * body_spread

    # Helmholtz (~1280 Hz)
    helmholtz = np.sin(t * helmholtz_freq * chirp_factor * TAU) * helmholtz_amp
    helmholtz_sub = np.sin(t * helmholtz_freq * 0.88 * TAU) * helmholtz_amp * 0.4
    shell = np.sin(t * helmholtz_freq * 1.29 * TAU) * helmholtz_amp * 0.25

    # Foam bloom
    foam = np.sin(t * foam_freq * TAU) * np.exp(-t * 140.0) * foam_amp

    # Brightness (2k+) — noise-modulated tones
    noise = np.random.RandomState(42).randn(num_samples) * 0.3
    bright1 = noise * np.sin(t * brightness_freq * TAU) * click_env * brightness_amp
    bright2 = noise * np.sin(t * brightness_freq * 1.33 * TAU) * click_env * brightness_amp * 0.6
    bright3 = noise * np.sin(t * brightness_freq * 1.75 * TAU) * click_env * brightness_amp * 0.3
    # Broadband click
    click = noise * click_env * brightness_amp * 0.5

    # Mix
    combined = (
        (strike + strike_harm) * strike_env +
        (mode + mode_sub + mode_upper) * mode_env +
        body_total * body_env +
        (helmholtz + helmholtz_sub + shell) * helmholtz_env +
        foam +
        bright1 + bright2 + bright3 + click
    )

    return combined * amplitude


def spectral_distance(params, ref_spectrum, ref_freqs):
    """
    Compute negative cosine similarity (to minimize).
    Also includes band-level MSE for better convergence.
    """
    try:
        synth = synthesize(params)
        synth_spec, synth_freqs = compute_power_spectrum(synth, SAMPLE_RATE)

        min_len = min(len(ref_spectrum), len(synth_spec))
        r = ref_spectrum[:min_len]
        s = synth_spec[:min_len]
        f = ref_freqs[:min_len]

        # Cosine similarity (primary metric)
        cos_sim = cosine_similarity(r, s)

        # Band-level MSE (secondary metric for convergence)
        bands = [(0, 200), (200, 500), (500, 750), (750, 1000),
                 (1000, 1500), (1500, 2000), (2000, 5000)]
        band_mse = 0
        for f_lo, f_hi in bands:
            mask = (f >= f_lo) & (f < f_hi)
            r_band = r[mask].sum()
            s_band = s[mask].sum()
            band_mse += (r_band - s_band) ** 2

        # Combined loss: negative cosine + band MSE
        # Weight cosine more heavily since it's our target metric
        loss = -cos_sim + band_mse * 5.0
        return loss

    except Exception:
        return 1.0  # Worst case


def main():
    print("=" * 65)
    print("PICKLEBALL SPECTRAL OPTIMIZER")
    print("Using scipy.optimize.differential_evolution")
    print("=" * 65)

    # Load reference
    ref_path = OUTPUT_DIR / "reference.wav"
    print(f"\nLoading reference from: {ref_path}")
    ref_hits = extract_reference_hits(ref_path, n_hits=5)
    print(f"Extracted {len(ref_hits)} clean reference hits")

    # Average reference spectrum
    profiles = []
    for h in ref_hits:
        p, f = compute_power_spectrum(h, SAMPLE_RATE)
        profiles.append(p)
    ref_spectrum = np.mean(profiles, axis=0)
    ref_spectrum /= max(ref_spectrum.sum(), 1e-10)
    ref_freqs = f

    # Baseline similarity
    from sound_analysis import create_paddle_sound
    np.random.seed(42)
    baseline = create_paddle_sound(0.028, 0.84, 0.64, 0.42, 0.05, 0.025, 185.0, 42.0, 0.00075, 0.95, 0.86)
    baseline_spec, _ = compute_power_spectrum(baseline, SAMPLE_RATE)
    baseline_sim = cosine_similarity(ref_spectrum[:len(baseline_spec)], baseline_spec[:len(ref_spectrum)])
    print(f"\nBaseline similarity (current synthesis): {baseline_sim*100:.1f}%")

    # ─── Parameter bounds for optimization ───
    # [param_name, lower, upper, initial_guess]
    param_defs = [
        ("strike_freq",      850,  980,   920),    # 0
        ("strike_amp",       0.2,  0.9,   0.52),   # 1
        ("strike_harm_amp",  0.01, 0.2,   0.10),   # 2
        ("mode_freq",        1050, 1300,  1185),    # 3
        ("mode_amp",         0.05, 0.5,   0.34),    # 4
        ("body_freq_center", 250,  450,   300),     # 5
        ("body_amp",         0.05, 0.5,   0.18),    # 6
        ("body_spread",      0.3,  2.0,   1.0),     # 7
        ("helmholtz_freq",   1100, 1400,  1280),    # 8
        ("helmholtz_amp",    0.01, 0.3,   0.12),    # 9
        ("brightness_amp",   0.05, 0.8,   0.14),    # 10
        ("brightness_freq",  2000, 3500,  2400),    # 11
        ("attack_time",      0.0002, 0.003, 0.00075), # 12
        ("strike_decay",     80,   300,   185),     # 13
        ("mode_decay",       100,  350,   200),     # 14
        ("body_decay",       20,   100,   42),      # 15
        ("foam_freq",        750,  1000,  880),     # 16
        ("foam_amp",         0.01, 0.4,   0.15),    # 17
        ("chirp_range",      100,  500,   280),     # 18
    ]

    names = [p[0] for p in param_defs]
    bounds = [(p[1], p[2]) for p in param_defs]
    x0 = [p[3] for p in param_defs]

    print(f"\nOptimizing {len(bounds)} parameters...")
    print("This may take 1-3 minutes...\n")

    # Track progress
    best_so_far = [1.0]
    eval_count = [0]

    def callback(xk, convergence):
        eval_count[0] += 1
        loss = spectral_distance(xk, ref_spectrum, ref_freqs)
        sim = -loss + (loss + cosine_similarity(
            ref_spectrum[:len(compute_power_spectrum(synthesize(xk), SAMPLE_RATE)[0])],
            compute_power_spectrum(synthesize(xk), SAMPLE_RATE)[0][:len(ref_spectrum)]
        ))
        if eval_count[0] % 10 == 0:
            synth = synthesize(xk)
            s_spec, _ = compute_power_spectrum(synth, SAMPLE_RATE)
            min_l = min(len(ref_spectrum), len(s_spec))
            actual_sim = cosine_similarity(ref_spectrum[:min_l], s_spec[:min_l]) * 100
            print(f"  Generation {eval_count[0]:4d}: similarity = {actual_sim:.1f}%")

    result = differential_evolution(
        spectral_distance,
        bounds=bounds,
        args=(ref_spectrum, ref_freqs),
        x0=x0,
        maxiter=200,
        popsize=25,
        tol=1e-8,
        mutation=(0.5, 1.5),
        recombination=0.9,
        seed=42,
        callback=callback,
        workers=1,
        polish=True,
    )

    optimal = result.x
    print(f"\nOptimization complete!")
    print(f"  Iterations: {result.nit}")
    print(f"  Function evaluations: {result.nfev}")

    # Final similarity
    np.random.seed(42)
    synth_optimal = synthesize(optimal)
    opt_spec, _ = compute_power_spectrum(synth_optimal, SAMPLE_RATE)
    min_l = min(len(ref_spectrum), len(opt_spec))
    final_sim = cosine_similarity(ref_spectrum[:min_l], opt_spec[:min_l]) * 100

    print(f"\n  Baseline similarity: {baseline_sim*100:.1f}%")
    print(f"  Optimized similarity: {final_sim:.1f}%")
    print(f"  Improvement: +{final_sim - baseline_sim*100:.1f}%")

    # ─── Print optimal parameters ───
    print("\n" + "=" * 65)
    print("OPTIMAL PARAMETERS")
    print("=" * 65)
    param_dict = {}
    for i, name in enumerate(names):
        print(f"  {name:20s} = {optimal[i]:.6f}")
        param_dict[name] = float(optimal[i])

    # Save to JSON
    json_path = OUTPUT_DIR / "optimal_params.json"
    with open(json_path, 'w') as f:
        json.dump(param_dict, f, indent=2)
    print(f"\nSaved to: {json_path}")

    # ─── Power distribution comparison ───
    print("\n" + "=" * 65)
    print("POWER DISTRIBUTION COMPARISON")
    print("=" * 65)
    bands = [
        ("0-200", 0, 200), ("200-500", 200, 500), ("500-750", 500, 750),
        ("750-1k", 750, 1000), ("1k-1.5k", 1000, 1500), ("1.5k-2k", 1500, 2000), ("2k+", 2000, 5000),
    ]
    freqs_spec = ref_freqs[:min_l]
    for label, f_lo, f_hi in bands:
        mask_r = (freqs_spec >= f_lo) & (freqs_spec < f_hi)
        mask_s = mask_r  # Same freq axis
        r_pct = ref_spectrum[:min_l][mask_r].sum() * 100
        s_pct = opt_spec[:min_l][mask_s].sum() * 100
        delta = r_pct - s_pct
        ok = "OK" if abs(delta) < 3 else ("+" if delta > 0 else "-")
        print(f"  {label:8s}: ref={r_pct:5.1f}%  synth={s_pct:5.1f}%  delta={delta:+5.1f}%  {ok}")

    # ─── Export optimized WAV ───
    np.random.seed(42)
    save_wav(OUTPUT_DIR / "optimized_thock.wav", synth_optimal, SAMPLE_RATE)
    print(f"\nExported: {OUTPUT_DIR}/optimized_thock.wav")

    # ─── Generate comparison plot ───
    fig = plt.figure(figsize=(16, 10))
    gs = matplotlib.gridspec.GridSpec(2, 2, figure=fig, hspace=0.35, wspace=0.3)

    # Waveforms
    ax1 = fig.add_subplot(gs[0, 0])
    ref_clip = ref_hits[0]
    t_ref = np.arange(len(ref_clip)) / SAMPLE_RATE * 1000
    ax1.plot(t_ref, ref_clip, color='blue', linewidth=0.5)
    ax1.set_title('Reference (Real)', fontsize=11)
    ax1.set_xlabel('Time (ms)')
    ax1.set_xlim(0, 40)
    ax1.grid(True, alpha=0.3)

    ax2 = fig.add_subplot(gs[0, 1])
    t_synth = np.arange(len(synth_optimal)) / SAMPLE_RATE * 1000
    ref_peak = np.max(np.abs(ref_clip))
    synth_peak = np.max(np.abs(synth_optimal))
    synth_scaled = synth_optimal * (ref_peak / max(synth_peak, 1e-10))
    ax2.plot(t_synth, synth_scaled, color='red', linewidth=0.5)
    ax2.set_title(f'Optimized Synthesis ({final_sim:.1f}%)', fontsize=11)
    ax2.set_xlabel('Time (ms)')
    ax2.set_xlim(0, 40)
    ax2.grid(True, alpha=0.3)

    # Spectral overlay
    ax3 = fig.add_subplot(gs[1, 0])
    ref_db = 10 * np.log10(ref_spectrum[:min_l] / max(ref_spectrum[:min_l].max(), 1e-10))
    opt_db = 10 * np.log10(opt_spec[:min_l] / max(opt_spec[:min_l].max(), 1e-10))
    ref_smooth = uniform_filter1d(ref_db, size=8)
    opt_smooth = uniform_filter1d(opt_db, size=8)
    ax3.plot(freqs_spec, ref_smooth, color='blue', linewidth=1.5, label='Reference')
    ax3.plot(freqs_spec, opt_smooth, color='red', linewidth=1.5, label='Optimized')
    ax3.set_xlim(0, 4000)
    ax3.set_ylim(-40, 2)
    ax3.set_xlabel('Frequency (Hz)')
    ax3.set_ylabel('Power (dB)')
    ax3.set_title('Spectral Comparison')
    ax3.legend()
    ax3.grid(True, alpha=0.3)

    # Power bars
    ax4 = fig.add_subplot(gs[1, 1])
    ref_bands = []
    opt_bands = []
    band_labels = []
    for label, f_lo, f_hi in bands:
        mask = (freqs_spec >= f_lo) & (freqs_spec < f_hi)
        ref_bands.append(ref_spectrum[:min_l][mask].sum() * 100)
        opt_bands.append(opt_spec[:min_l][mask].sum() * 100)
        band_labels.append(label)
    x = np.arange(len(band_labels))
    ax4.bar(x - 0.2, ref_bands, 0.35, color='blue', alpha=0.7, label='Reference')
    ax4.bar(x + 0.2, opt_bands, 0.35, color='red', alpha=0.7, label='Optimized')
    ax4.set_xticks(x)
    ax4.set_xticklabels(band_labels, rotation=45, fontsize=8)
    ax4.set_ylabel('Power (%)')
    ax4.set_title('Power Distribution Match')
    ax4.legend(fontsize=8)
    ax4.grid(True, alpha=0.3, axis='y')

    fig.suptitle(f'Optimized Pickleball Synthesis — {final_sim:.1f}% Spectral Match', fontsize=14, fontweight='bold')
    plt.savefig(str(OUTPUT_DIR / "optimized_comparison.png"), dpi=150, bbox_inches='tight')
    plt.close()
    print(f"Saved: {OUTPUT_DIR}/optimized_comparison.png")

    # ─── Generate GDScript constants ───
    print("\n" + "=" * 65)
    print("GDSCRIPT CONSTANTS (copy to ball.gd)")
    print("=" * 65)
    print(f"""
const BALL_STRIKE_FREQ := {optimal[0]:.1f}
const PADDLE_MODE_FREQ := {optimal[3]:.1f}
const BODY_FREQ := {optimal[5] * 0.73:.1f}  # body_freq_center * 0.73 ≈ original 220 Hz mapping
const BODY_LOW_FREQ := {optimal[5] * 0.62:.1f}
const BODY_HIGH_FREQ := {optimal[5] * 0.83:.1f}
const BALL_HELMHOLTZ_FREQ := {optimal[8]:.1f}
const CONTACT_CHIRP_RANGE := {optimal[18]:.1f}

# Oscillator amplitudes (in synthesis loop):
# strike = sin(...) * {optimal[1]:.3f}
# strike_harmonic = sin(...) * {optimal[2]:.3f}
# mode = sin(...) * {optimal[4]:.3f}
# body components: base amp = {optimal[6]:.3f}, spread = {optimal[7]:.3f}
# helmholtz = sin(...) * {optimal[9]:.3f}
# brightness: amp = {optimal[10]:.3f}, center_freq = {optimal[11]:.0f} Hz
# foam_bloom: freq = {optimal[16]:.0f} Hz, amp = {optimal[17]:.3f}

# Envelope parameters:
# attack_time = {optimal[12]:.6f}s ({optimal[12]*1000:.3f}ms)
# strike_decay = {optimal[13]:.1f}
# mode_decay = {optimal[14]:.1f}
# body_decay = {optimal[15]:.1f}
""")


if __name__ == "__main__":
    main()

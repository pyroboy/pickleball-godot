#!/usr/bin/env python3
"""
Reclip reference hits with proper windowing, then re-compare.
Also generates a corrected synthesis target based on what real outdoor
pickleball actually sounds like.
"""

import numpy as np
import wave
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from scipy import signal as sp_signal
from scipy.fft import fft, fftfreq
from scipy.ndimage import uniform_filter1d

SAMPLE_RATE = 44100
OUTPUT_DIR = Path("/Users/arjomagno/Documents/github-repos/pickleball-godot/audio_analysis")


def load_wav(filepath):
    with wave.open(str(filepath), 'r') as wf:
        channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        framerate = wf.getframerate()
        nframes = wf.getnframes()
        raw = wf.readframes(nframes)
    data = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return data, framerate


def save_wav(filename, samples, sr=44100):
    samples = np.clip(samples, -1.0, 1.0)
    int_samples = (samples * 32767).astype(np.int16)
    with wave.open(str(filename), 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(int(sr))
        wf.writeframes(int_samples.tobytes())


def highpass(data, cutoff=80, sr=44100, order=4):
    """High-pass Butterworth filter to remove handling/wind noise."""
    sos = sp_signal.butter(order, cutoff, btype='high', fs=sr, output='sos')
    return sp_signal.sosfiltfilt(sos, data)


def find_onset(clip, sr, threshold_ratio=0.15):
    """Find the exact onset sample using envelope threshold."""
    env = np.abs(clip)
    env_smooth = uniform_filter1d(env, size=int(sr * 0.0003))  # 0.3ms smoothing
    peak = env_smooth.max()
    threshold = peak * threshold_ratio
    onset_candidates = np.where(env_smooth > threshold)[0]
    if len(onset_candidates) == 0:
        return 0
    return max(0, onset_candidates[0] - int(sr * 0.001))  # 1ms pre-onset


def detect_clean_hits(data, sr, threshold_db=-15, min_gap_ms=250, clip_ms=40):
    """
    Detect hits with tight onset-aligned clipping.
    Returns onset-aligned clips of exactly clip_ms duration.
    """
    window = max(int(sr * 0.001), 1)
    envelope = np.sqrt(np.convolve(data**2, np.ones(window)/window, mode='same'))
    peak_env = envelope.max()
    threshold = peak_env * 10**(threshold_db / 20)
    min_gap = int(sr * min_gap_ms / 1000)
    clip_samples = int(sr * clip_ms / 1000)

    hits = []
    i = 0
    while i < len(data) - clip_samples:
        if envelope[i] > threshold:
            # Find peak of this event
            region_end = min(i + clip_samples * 2, len(data))
            region = envelope[i:region_end]
            peak_idx = i + np.argmax(region)

            # Extract generous window around peak
            start = max(0, peak_idx - int(sr * 0.005))  # 5ms before peak
            end = min(len(data), start + clip_samples * 2)
            raw_clip = data[start:end]

            # Find precise onset
            onset = find_onset(raw_clip, sr)
            clean_clip = raw_clip[onset:onset + clip_samples]

            if len(clean_clip) < clip_samples:
                padded = np.zeros(clip_samples)
                padded[:len(clean_clip)] = clean_clip
                clean_clip = padded

            peak_amp = np.max(np.abs(clean_clip))
            hits.append({
                'clip': clean_clip,
                'peak': peak_amp,
                'global_pos': start + onset,
                'time_s': (start + onset) / sr,
            })

            i = peak_idx + min_gap
        else:
            i += 1

    return hits


def compute_spectral_profile(samples, sr, max_freq=4000):
    """Compute normalized power spectrum."""
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


def spectral_similarity(a, b, sr, max_freq=4000):
    spec_a, _ = compute_spectral_profile(a, sr, max_freq)
    spec_b, _ = compute_spectral_profile(b, sr, max_freq)
    min_len = min(len(spec_a), len(spec_b))
    spec_a, spec_b = spec_a[:min_len], spec_b[:min_len]
    dot = np.dot(spec_a, spec_b)
    norm_a = np.sqrt(np.dot(spec_a, spec_a))
    norm_b = np.sqrt(np.dot(spec_b, spec_b))
    if norm_a < 1e-10 or norm_b < 1e-10:
        return 0.0
    return dot / (norm_a * norm_b) * 100


def extract_reference_profile(hits, sr):
    """
    Average the spectral profiles of multiple hits to get
    a stable reference target.
    """
    profiles = []
    for h in hits:
        prof, freqs = compute_spectral_profile(h['clip'], sr)
        profiles.append(prof)
    avg_profile = np.mean(profiles, axis=0)
    avg_profile /= max(avg_profile.sum(), 1e-10)
    return avg_profile, freqs


def main():
    print("=" * 65)
    print("RECLIP & SPECTRAL ANALYSIS v2")
    print("=" * 65)

    ref_path = OUTPUT_DIR / "reference.wav"
    if not ref_path.exists():
        print("ERROR: reference.wav not found")
        return

    data, sr = load_wav(ref_path)
    print(f"Loaded: {len(data)/sr:.1f}s at {sr} Hz")

    # High-pass filter to remove environmental rumble
    print("Applying 80 Hz high-pass filter...")
    data = highpass(data, cutoff=80, sr=sr)

    # Detect and clip hits
    print("Detecting hits with tight 40ms windows...")
    hits = detect_clean_hits(data, sr, threshold_db=-15, min_gap_ms=250, clip_ms=40)
    print(f"Found {len(hits)} hits")

    # Filter: non-clipping, reasonable amplitude
    clean_hits = [h for h in hits if 0.08 < h['peak'] < 0.95]
    print(f"Clean (non-clipping) hits: {len(clean_hits)}")

    # If too few clean hits, relax threshold
    if len(clean_hits) < 5:
        clean_hits = [h for h in hits if h['peak'] > 0.05]
        print(f"Relaxed filter: {len(clean_hits)} hits")

    # Sort by peak amplitude
    clean_hits.sort(key=lambda h: h['peak'], reverse=True)
    best = clean_hits[:10]

    # Export best clips
    best_dir = OUTPUT_DIR / "best_clips_v2"
    best_dir.mkdir(exist_ok=True)
    for i, h in enumerate(best):
        save_wav(best_dir / f"hit_{i+1}_peak{h['peak']:.3f}_t{h['time_s']:.1f}s.wav", h['clip'], sr)
        print(f"  #{i+1}: peak={h['peak']:.3f}, time={h['time_s']:.1f}s")

    # Compute average reference spectral profile
    print("\n── Reference Spectral Profile (averaged) ──")
    ref_profile, ref_freqs = extract_reference_profile(best[:5], sr)

    # Find peaks in reference profile
    from scipy.signal import find_peaks
    smoothed = uniform_filter1d(ref_profile, size=20)
    peak_indices, peak_props = find_peaks(smoothed, height=smoothed.max() * 0.05,
                                            distance=int(50 / (ref_freqs[1] - ref_freqs[0])))
    print("\n  Detected spectral peaks in reference:")
    for idx in peak_indices:
        freq = ref_freqs[idx]
        power_pct = ref_profile[idx] / ref_profile.max() * 100
        print(f"    {freq:7.0f} Hz — {power_pct:5.1f}% of peak power")

    # Power distribution
    bands = [
        ("0-200", 0, 200), ("200-500", 200, 500), ("500-750", 500, 750),
        ("750-1k", 750, 1000), ("1k-1.5k", 1000, 1500), ("1.5k-2k", 1500, 2000), ("2k+", 2000, 4000),
    ]
    print("\n  Power distribution:")
    below_750 = 0
    for label, f_lo, f_hi in bands:
        mask = (ref_freqs >= f_lo) & (ref_freqs < f_hi)
        pct = ref_profile[mask].sum() * 100
        marker = "◄" if pct > 15 else ""
        print(f"    {label:8s}: {pct:5.1f}% {marker}")
        if f_hi <= 750:
            below_750 += pct
    print(f"    {'< 750 Hz':8s}: {below_750:5.1f}% (research target: ~80%)")

    # ─── Load synthesis and compare ───
    print("\n── Synthesis Comparison ──")
    synth_files = {
        "thock_slow": OUTPUT_DIR / "paddle_thock_slow.wav",
        "thock_fast": OUTPUT_DIR / "paddle_thock_fast.wav",
        "smash": OUTPUT_DIR / "paddle_smash.wav",
        "serve": OUTPUT_DIR / "paddle_serve.wav",
        "volley": OUTPUT_DIR / "paddle_volley.wav",
    }

    synth_sounds = {}
    for name, path in synth_files.items():
        if path.exists():
            s, _ = load_wav(path)
            synth_sounds[name] = s

    for name, synth in synth_sounds.items():
        sims = [spectral_similarity(h['clip'], synth, sr) for h in best[:5]]
        avg = np.mean(sims)
        print(f"  {name:15s}: {avg:5.1f}% similarity (avg of top 5)")

    # ─── Master comparison plot ───
    fig = plt.figure(figsize=(18, 14))
    gs = GridSpec(3, 3, figure=fig, hspace=0.4, wspace=0.35)

    # Top row: best 3 reference waveforms
    for i in range(min(3, len(best))):
        ax = fig.add_subplot(gs[0, i])
        h = best[i]
        t = np.arange(len(h['clip'])) / sr * 1000
        ax.plot(t, h['clip'], color='blue', linewidth=0.5)
        ax.set_title(f'Ref Hit #{i+1} (peak={h["peak"]:.2f})', fontsize=10)
        ax.set_xlabel('Time (ms)')
        ax.set_ylabel('Amplitude')
        ax.set_xlim(0, 40)
        ax.grid(True, alpha=0.3)

    # Middle left: Average reference spectrum with peaks labeled
    ax_spec = fig.add_subplot(gs[1, 0:2])
    ref_db = 10 * np.log10(ref_profile / max(ref_profile.max(), 1e-10))
    ref_db_smooth = uniform_filter1d(ref_db, size=10)
    ax_spec.plot(ref_freqs, ref_db_smooth, color='blue', linewidth=1.5, label='Reference (avg)')

    # Plot synthesis spectrum
    if 'thock_slow' in synth_sounds:
        synth_prof, synth_freqs = compute_spectral_profile(synth_sounds['thock_slow'], sr)
        synth_db = 10 * np.log10(synth_prof / max(synth_prof.max(), 1e-10))
        synth_db_smooth = uniform_filter1d(synth_db, size=10)
        min_len = min(len(ref_freqs), len(synth_freqs))
        ax_spec.plot(synth_freqs[:min_len], synth_db_smooth[:min_len], color='red', linewidth=1.5, label='Synthesis (thock)')

    for idx in peak_indices:
        freq = ref_freqs[idx]
        ax_spec.axvline(x=freq, color='green', linestyle=':', alpha=0.5, linewidth=0.8)
        ax_spec.annotate(f'{freq:.0f} Hz', (freq, ref_db_smooth[idx]),
                        textcoords="offset points", xytext=(5, 10), fontsize=7, color='green')

    ax_spec.set_xlim(0, 4000)
    ax_spec.set_ylim(-40, 2)
    ax_spec.set_xlabel('Frequency (Hz)')
    ax_spec.set_ylabel('Power (dB, normalized)')
    ax_spec.set_title('Spectral Comparison: Reference vs Synthesis')
    ax_spec.legend(fontsize=9)
    ax_spec.grid(True, alpha=0.3)

    # Middle right: Power distribution comparison
    ax_pow = fig.add_subplot(gs[1, 2])
    ref_bands = []
    synth_bands = []
    band_labels = []
    for label, f_lo, f_hi in bands:
        mask_r = (ref_freqs >= f_lo) & (ref_freqs < f_hi)
        ref_bands.append(ref_profile[mask_r].sum() * 100)
        if 'thock_slow' in synth_sounds:
            mask_s = (synth_freqs >= f_lo) & (synth_freqs < f_hi)
            synth_bands.append(synth_prof[mask_s[:len(synth_prof)]].sum() * 100 if mask_s.sum() <= len(synth_prof) else 0)
        band_labels.append(label)
    x = np.arange(len(band_labels))
    ax_pow.bar(x - 0.2, ref_bands, 0.35, color='blue', alpha=0.7, label='Reference')
    if synth_bands:
        ax_pow.bar(x + 0.2, synth_bands, 0.35, color='red', alpha=0.7, label='Synthesis')
    ax_pow.set_xticks(x)
    ax_pow.set_xticklabels(band_labels, rotation=45, fontsize=8)
    ax_pow.set_ylabel('Power (%)')
    ax_pow.set_title('Power Distribution')
    ax_pow.legend(fontsize=8)
    ax_pow.grid(True, alpha=0.3, axis='y')

    # Bottom: Envelope overlay + waveform overlay
    ax_env = fig.add_subplot(gs[2, 0:2])
    ref_clip = best[0]['clip']
    t_ref = np.arange(len(ref_clip)) / sr * 1000

    # Compute envelope
    env_win = int(sr * 0.0005)
    ref_env = np.sqrt(np.convolve(ref_clip**2, np.ones(env_win)/env_win, mode='same'))
    ref_env_norm = ref_env / max(ref_env.max(), 1e-10)

    ax_env.plot(t_ref, ref_env_norm, color='blue', linewidth=1.5, label='Reference envelope')

    if 'thock_slow' in synth_sounds:
        synth_clip = synth_sounds['thock_slow']
        # Scale synth to reference peak
        synth_scaled = synth_clip * (np.max(np.abs(ref_clip)) / max(np.max(np.abs(synth_clip)), 1e-10))
        t_synth = np.arange(len(synth_scaled)) / sr * 1000
        synth_env = np.sqrt(np.convolve(synth_scaled**2, np.ones(env_win)/env_win, mode='same'))
        synth_env_norm = synth_env / max(synth_env.max(), 1e-10)
        ax_env.plot(t_synth, synth_env_norm, color='red', linewidth=1.5, label='Synthesis envelope')

    ax_env.set_xlabel('Time (ms)')
    ax_env.set_ylabel('Envelope (normalized)')
    ax_env.set_title('Amplitude Envelope Comparison')
    ax_env.set_xlim(0, 40)
    ax_env.legend(fontsize=9)
    ax_env.grid(True, alpha=0.3)

    # Bottom right: Similarity scores
    ax_sim = fig.add_subplot(gs[2, 2])
    names = []
    scores = []
    for name, synth in synth_sounds.items():
        sims = [spectral_similarity(h['clip'], synth, sr) for h in best[:5]]
        names.append(name)
        scores.append(np.mean(sims))
    colors = ['#F44336' if s < 15 else '#FFC107' if s < 40 else '#4CAF50' for s in scores]
    ax_sim.barh(names, scores, color=colors)
    ax_sim.set_xlabel('Spectral Similarity (%)')
    ax_sim.set_title('Synthesis Accuracy Scores')
    ax_sim.set_xlim(0, 100)
    for i, s in enumerate(scores):
        ax_sim.text(s + 1, i, f'{s:.1f}%', va='center', fontsize=9)
    ax_sim.grid(True, alpha=0.3, axis='x')

    plt.suptitle('Pickleball Sound Analysis v2 — Filtered, Onset-Aligned', fontsize=14, fontweight='bold')
    plt.savefig(str(OUTPUT_DIR / "master_comparison_v2.png"), dpi=150, bbox_inches='tight')
    plt.close()
    print(f"\n  Saved: {OUTPUT_DIR}/master_comparison_v2.png")

    # ─── Output recommended synthesis adjustments ───
    print("\n" + "=" * 65)
    print("RECOMMENDED SYNTHESIS ADJUSTMENTS")
    print("=" * 65)

    # Find where reference power is concentrated vs synthesis
    if 'thock_slow' in synth_sounds:
        print("\n  Reference vs Synthesis power deltas:")
        for i, (label, f_lo, f_hi) in enumerate(bands):
            delta = ref_bands[i] - synth_bands[i]
            direction = "↑ needs MORE" if delta > 3 else "↓ needs LESS" if delta < -3 else "≈ OK"
            print(f"    {label:8s}: ref={ref_bands[i]:5.1f}%  synth={synth_bands[i]:5.1f}%  delta={delta:+5.1f}%  {direction}")

    # Find reference peak frequency
    peak_freq_idx = np.argmax(ref_profile)
    peak_freq = ref_freqs[peak_freq_idx]
    print(f"\n  Reference dominant frequency: {peak_freq:.0f} Hz")
    print(f"  Current synthesis mode freq:  {1185:.0f} Hz")
    if abs(peak_freq - 1185) > 200:
        print(f"  ⚠ Mismatch! Reference peaks lower than synthesis.")
        print(f"    This is expected — outdoor recording captures more body resonance.")
        print(f"    The body (200-500 Hz) dominates at distance; mode (1185 Hz) is close-mic character.")


if __name__ == "__main__":
    main()

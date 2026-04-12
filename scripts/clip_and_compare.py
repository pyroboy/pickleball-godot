#!/usr/bin/env python3
"""
Pickleball Hit Clipper & Spectral Comparator
=============================================
1. Loads the reference recording (freesound ibisradio 696743)
2. Auto-detects individual paddle hits via transient detection
3. Clips each hit into a ~50ms window
4. Exports the cleanest hits as individual WAV files
5. Compares spectral profiles against our synthesis
"""

import numpy as np
import wave
import struct
import os
from pathlib import Path

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.gridspec import GridSpec
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False

try:
    from scipy import signal as scipy_signal
    from scipy.fft import fft, fftfreq
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False

SAMPLE_RATE = 44100
OUTPUT_DIR = Path("/Users/arjomagno/Documents/github-repos/pickleball-godot/audio_analysis")
REF_PATH = OUTPUT_DIR / "reference.wav"


def load_wav(filepath):
    """Load WAV file, return mono float samples and sample rate."""
    with wave.open(str(filepath), 'r') as wf:
        channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        framerate = wf.getframerate()
        nframes = wf.getnframes()
        raw = wf.readframes(nframes)

    if sampwidth == 2:
        data = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    elif sampwidth == 3:
        # 24-bit
        data = np.zeros(nframes * channels, dtype=np.float64)
        for i in range(nframes * channels):
            b = raw[i*3:(i+1)*3]
            val = int.from_bytes(b, byteorder='little', signed=True)
            data[i] = val / 8388608.0
    else:
        data = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0

    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)  # Mix to mono

    return data, framerate


def detect_hits(samples, sr, threshold_db=-20, min_gap_ms=200, pre_ms=2, post_ms=50):
    """
    Detect transient hits in audio using envelope following.
    Returns list of (start_sample, end_sample) for each hit.
    """
    # Compute signal envelope
    window_ms = 1.0  # 1ms RMS window
    window_samples = max(int(sr * window_ms / 1000), 1)
    envelope = np.sqrt(np.convolve(samples**2, np.ones(window_samples)/window_samples, mode='same'))

    # Threshold
    peak_env = np.max(envelope)
    threshold = peak_env * 10**(threshold_db / 20)

    # Find regions above threshold
    above = envelope > threshold
    min_gap_samples = int(sr * min_gap_ms / 1000)
    pre_samples = int(sr * pre_ms / 1000)
    post_samples = int(sr * post_ms / 1000)

    hits = []
    i = 0
    while i < len(above):
        if above[i]:
            # Found start of hit region
            start = max(0, i - pre_samples)
            # Find end (where it drops below threshold + min gap)
            j = i
            last_above = i
            while j < len(above):
                if above[j]:
                    last_above = j
                elif j - last_above > min_gap_samples // 4:
                    break
                j += 1
            end = min(len(samples), last_above + post_samples)
            hits.append((start, end))
            i = end + min_gap_samples  # Skip minimum gap
        else:
            i += 1

    return hits


def classify_hit(samples, sr):
    """
    Classify a hit as 'paddle' or 'bounce' based on spectral characteristics.
    Paddle hits have more energy in 1000-1500 Hz range.
    Bounces have more energy below 500 Hz relative to 1000+ Hz.
    """
    N = len(samples)
    yf = np.abs(fft(samples))[:N // 2]
    xf = fftfreq(N, 1.0 / sr)[:N // 2]

    power = yf ** 2
    total = power.sum()
    if total < 1e-10:
        return "silence", 0

    low_power = power[(xf >= 100) & (xf < 500)].sum()
    mid_power = power[(xf >= 800) & (xf < 1500)].sum()
    high_power = power[(xf >= 1500) & (xf < 3000)].sum()

    # Paddle hits have strong mid peak (1000-1500 Hz)
    mid_ratio = mid_power / max(total, 1e-10)
    low_ratio = low_power / max(total, 1e-10)

    peak_amp = np.max(np.abs(samples))

    if mid_ratio > 0.15 and peak_amp > 0.05:
        return "paddle", peak_amp
    elif peak_amp > 0.03:
        return "bounce", peak_amp
    else:
        return "ambient", peak_amp


def spectral_similarity(samples_a, samples_b, sr, max_freq=3000):
    """
    Compute spectral similarity between two sounds using cosine similarity
    of their normalized power spectra.
    Returns similarity score 0-100%.
    """
    def norm_spectrum(s):
        N = len(s)
        yf = np.abs(fft(s))[:N // 2]
        xf = fftfreq(N, 1.0 / sr)[:N // 2]
        # Limit to max_freq
        mask = xf <= max_freq
        power = yf[mask] ** 2
        # Normalize
        total = power.sum()
        if total < 1e-10:
            return np.zeros_like(power), xf[mask]
        return power / total, xf[mask]

    # Resample shorter to match longer for comparison
    min_len = min(len(samples_a), len(samples_b))
    # Pad shorter signal to match length for FFT resolution
    target_len = max(len(samples_a), len(samples_b), sr // 10)  # At least 100ms for resolution
    a_padded = np.zeros(target_len)
    b_padded = np.zeros(target_len)
    a_padded[:len(samples_a)] = samples_a
    b_padded[:len(samples_b)] = samples_b

    spec_a, freq_a = norm_spectrum(a_padded)
    spec_b, freq_b = norm_spectrum(b_padded)

    # Ensure same length
    min_bins = min(len(spec_a), len(spec_b))
    spec_a = spec_a[:min_bins]
    spec_b = spec_b[:min_bins]

    # Cosine similarity
    dot = np.dot(spec_a, spec_b)
    norm_a = np.sqrt(np.dot(spec_a, spec_a))
    norm_b = np.sqrt(np.dot(spec_b, spec_b))

    if norm_a < 1e-10 or norm_b < 1e-10:
        return 0.0

    similarity = dot / (norm_a * norm_b) * 100
    return similarity


def plot_comparison(ref_samples, synth_samples, sr, title, filename):
    """Plot side-by-side waveform + overlaid spectrum comparison."""
    if not HAS_MATPLOTLIB or not HAS_SCIPY:
        return

    fig = plt.figure(figsize=(16, 12))
    gs = GridSpec(3, 2, figure=fig, hspace=0.4, wspace=0.3)

    TAU = 2.0 * np.pi

    # ─── Reference Waveform ───
    ax1 = fig.add_subplot(gs[0, 0])
    t_ref = np.arange(len(ref_samples)) / sr * 1000
    ax1.plot(t_ref, ref_samples, color='blue', linewidth=0.5)
    ax1.set_xlabel('Time (ms)')
    ax1.set_ylabel('Amplitude')
    ax1.set_title('Reference (Real Recording)')
    ax1.grid(True, alpha=0.3)

    # ─── Synthesis Waveform ───
    ax2 = fig.add_subplot(gs[0, 1])
    t_synth = np.arange(len(synth_samples)) / sr * 1000
    # Normalize synth to match reference peak
    ref_peak = np.max(np.abs(ref_samples))
    synth_peak = np.max(np.abs(synth_samples))
    if synth_peak > 0:
        synth_scaled = synth_samples * (ref_peak / synth_peak)
    else:
        synth_scaled = synth_samples
    ax2.plot(t_synth, synth_scaled, color='red', linewidth=0.5)
    ax2.set_xlabel('Time (ms)')
    ax2.set_ylabel('Amplitude')
    ax2.set_title('Synthesis (Our Engine)')
    ax2.grid(True, alpha=0.3)

    # ─── Overlaid Spectra ───
    ax3 = fig.add_subplot(gs[1, :])
    # Pad both to same length
    target_len = max(len(ref_samples), len(synth_samples), sr // 10)
    ref_padded = np.zeros(target_len)
    synth_padded = np.zeros(target_len)
    ref_padded[:len(ref_samples)] = ref_samples
    synth_padded[:len(synth_samples)] = synth_scaled

    N = target_len
    ref_fft = np.abs(fft(ref_padded))[:N // 2]
    synth_fft = np.abs(fft(synth_padded))[:N // 2]
    freqs = fftfreq(N, 1.0 / sr)[:N // 2]

    # Smooth for readability
    if HAS_SCIPY:
        from scipy.ndimage import uniform_filter1d
        ref_smooth = uniform_filter1d(ref_fft, size=5)
        synth_smooth = uniform_filter1d(synth_fft, size=5)
    else:
        ref_smooth = ref_fft
        synth_smooth = synth_fft

    ref_db = 20 * np.log10(ref_smooth / max(ref_smooth.max(), 1e-10))
    synth_db = 20 * np.log10(synth_smooth / max(synth_smooth.max(), 1e-10))

    ax3.plot(freqs, ref_db, color='blue', linewidth=1.0, alpha=0.8, label='Reference (Real)')
    ax3.plot(freqs, synth_db, color='red', linewidth=1.0, alpha=0.8, label='Synthesis (Ours)')
    ax3.set_xlabel('Frequency (Hz)')
    ax3.set_ylabel('Magnitude (dB, normalized)')
    ax3.set_title('Spectral Comparison — Reference vs Synthesis')
    ax3.set_xlim(0, 4000)
    ax3.set_ylim(-50, 5)
    ax3.axvline(x=1185, color='orange', linestyle='--', alpha=0.4, label='1185 Hz (Mode)')
    ax3.axvline(x=220, color='green', linestyle='--', alpha=0.4, label='220 Hz (Body)')
    ax3.axvline(x=2000, color='gray', linestyle=':', alpha=0.4, label='2 kHz ceiling')
    ax3.legend(fontsize=8)
    ax3.grid(True, alpha=0.3)

    # ─── Power Distribution Comparison ───
    ax4 = fig.add_subplot(gs[2, 0])
    bands = [
        ("0-200", 0, 200), ("200-500", 200, 500), ("500-750", 500, 750),
        ("750-1k", 750, 1000), ("1k-1.5k", 1000, 1500), ("1.5k-2k", 1500, 2000), ("2k+", 2000, 5000),
    ]

    ref_power = ref_fft ** 2
    synth_power = synth_fft ** 2
    ref_total = max(ref_power.sum(), 1e-10)
    synth_total = max(synth_power.sum(), 1e-10)

    ref_bands = []
    synth_bands = []
    labels = []
    for label, f_lo, f_hi in bands:
        mask = (freqs >= f_lo) & (freqs < f_hi)
        ref_bands.append(ref_power[mask].sum() / ref_total * 100)
        synth_bands.append(synth_power[mask].sum() / synth_total * 100)
        labels.append(label)

    x = np.arange(len(labels))
    width = 0.35
    ax4.bar(x - width/2, ref_bands, width, color='blue', alpha=0.7, label='Reference')
    ax4.bar(x + width/2, synth_bands, width, color='red', alpha=0.7, label='Synthesis')
    ax4.set_xticks(x)
    ax4.set_xticklabels(labels, rotation=45)
    ax4.set_ylabel('Power (%)')
    ax4.set_title('Power Distribution by Band')
    ax4.legend(fontsize=8)
    ax4.grid(True, alpha=0.3, axis='y')

    # ─── Envelope Comparison ───
    ax5 = fig.add_subplot(gs[2, 1])
    # Compute envelopes
    env_window = max(int(sr * 0.5 / 1000), 1)  # 0.5ms window
    ref_env = np.sqrt(np.convolve(ref_samples**2, np.ones(env_window)/env_window, mode='same'))
    synth_env = np.sqrt(np.convolve(synth_scaled**2, np.ones(env_window)/env_window, mode='same'))
    t_env_ref = np.arange(len(ref_env)) / sr * 1000
    t_env_synth = np.arange(len(synth_env)) / sr * 1000

    ax5.plot(t_env_ref, ref_env / max(ref_env.max(), 1e-10), color='blue', linewidth=1.5, label='Reference')
    ax5.plot(t_env_synth, synth_env / max(synth_env.max(), 1e-10), color='red', linewidth=1.5, label='Synthesis')
    ax5.set_xlabel('Time (ms)')
    ax5.set_ylabel('Envelope (normalized)')
    ax5.set_title('Amplitude Envelope Comparison')
    ax5.legend(fontsize=8)
    ax5.grid(True, alpha=0.3)

    # Compute similarity
    sim = spectral_similarity(ref_samples, synth_samples, sr)
    fig.suptitle(f'{title}\nSpectral Similarity: {sim:.1f}%', fontsize=14, fontweight='bold')

    plt.savefig(filename, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Saved comparison: {filename}")
    return sim


def save_wav(filename, samples, sample_rate=44100):
    """Save float samples to 16-bit WAV"""
    samples = np.clip(samples, -1.0, 1.0)
    int_samples = (samples * 32767).astype(np.int16)
    with wave.open(str(filename), 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(int(sample_rate))
        wf.writeframes(int_samples.tobytes())


def main():
    print("=" * 65)
    print("PICKLEBALL HIT CLIPPER & SPECTRAL COMPARATOR")
    print("=" * 65)

    if not REF_PATH.exists():
        print(f"ERROR: Reference file not found at {REF_PATH}")
        return

    # ─── Load Reference ───
    print(f"\nLoading reference: {REF_PATH}")
    ref_data, ref_sr = load_wav(REF_PATH)
    print(f"  Duration: {len(ref_data)/ref_sr:.2f}s, Sample rate: {ref_sr} Hz, Samples: {len(ref_data)}")

    # Resample to 44100 if needed
    if ref_sr != SAMPLE_RATE:
        print(f"  Resampling from {ref_sr} to {SAMPLE_RATE}...")
        ratio = SAMPLE_RATE / ref_sr
        new_len = int(len(ref_data) * ratio)
        ref_data = np.interp(np.linspace(0, len(ref_data)-1, new_len),
                              np.arange(len(ref_data)), ref_data)
        ref_sr = SAMPLE_RATE

    # ─── Detect Hits ───
    print("\nDetecting hits...")
    hits = detect_hits(ref_data, ref_sr, threshold_db=-18, min_gap_ms=150, pre_ms=2, post_ms=50)
    print(f"  Found {len(hits)} transient events")

    # ─── Classify and Export Hits ───
    print("\nClassifying and exporting hits...")
    paddle_hits = []
    bounce_hits = []
    clip_dir = OUTPUT_DIR / "reference_clips"
    clip_dir.mkdir(exist_ok=True)

    for i, (start, end) in enumerate(hits):
        clip = ref_data[start:end]
        if len(clip) < 100:
            continue

        hit_type, peak_amp = classify_hit(clip, ref_sr)

        if hit_type == "paddle":
            paddle_hits.append((i, clip, peak_amp))
        elif hit_type == "bounce":
            bounce_hits.append((i, clip, peak_amp))

        # Save all classified clips
        clip_path = clip_dir / f"hit_{i:03d}_{hit_type}_{peak_amp:.3f}.wav"
        save_wav(clip_path, clip, ref_sr)

    print(f"\n  Paddle hits: {len(paddle_hits)}")
    print(f"  Bounce hits: {len(bounce_hits)}")
    print(f"  Clips saved to: {clip_dir}/")

    if not paddle_hits:
        print("\nWARNING: No paddle hits detected. Try adjusting threshold.")
        # Still continue with whatever we have
        all_hits = bounce_hits if bounce_hits else [(0, ref_data[:int(ref_sr*0.05)], 0.1)]
    else:
        all_hits = paddle_hits

    # ─── Select Best Hits ───
    # Sort by peak amplitude (loudest = cleanest paddle contact)
    all_hits.sort(key=lambda x: x[2], reverse=True)
    best_hits = all_hits[:5]  # Top 5 loudest

    print(f"\n── Top {len(best_hits)} cleanest hits for comparison ──")
    for rank, (idx, clip, amp) in enumerate(best_hits):
        clip_ms = len(clip) / ref_sr * 1000
        print(f"  #{rank+1}: Hit {idx}, peak={amp:.3f}, duration={clip_ms:.1f}ms")

    # ─── Export Best Hits ───
    best_dir = OUTPUT_DIR / "best_hits"
    best_dir.mkdir(exist_ok=True)
    for rank, (idx, clip, amp) in enumerate(best_hits):
        save_wav(best_dir / f"best_paddle_{rank+1}.wav", clip, ref_sr)

    # ─── Load Synthesis Sounds ───
    print("\n── Loading synthesis sounds for comparison ──")
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
            data, sr = load_wav(path)
            synth_sounds[name] = data
            print(f"  Loaded: {name} ({len(data)} samples)")

    if not synth_sounds:
        print("  ERROR: No synthesis WAVs found. Run sound_analysis.py first.")
        return

    # ─── Spectral Comparison ───
    print("\n" + "=" * 65)
    print("SPECTRAL COMPARISON: REAL vs SYNTHESIS")
    print("=" * 65)

    # Use the best (loudest) hit as primary reference
    ref_clip = best_hits[0][1]
    print(f"\nUsing best hit #{best_hits[0][0]} as primary reference")

    # Compare each synthesis type against the reference
    similarities = {}
    for name, synth_data in synth_sounds.items():
        sim = spectral_similarity(ref_clip, synth_data, SAMPLE_RATE)
        similarities[name] = sim
        print(f"  {name:15s}: {sim:5.1f}% spectral similarity")

        # Generate comparison plot
        plot_comparison(
            ref_clip, synth_data, SAMPLE_RATE,
            f"Real Paddle Hit vs Synthesis: {name}",
            str(OUTPUT_DIR / f"comparison_{name}.png")
        )

    # ─── Average across top hits ───
    print("\n── Cross-validation (average across top 3 hits) ──")
    for name, synth_data in synth_sounds.items():
        sims = []
        for rank, (idx, clip, amp) in enumerate(best_hits[:3]):
            s = spectral_similarity(clip, synth_data, SAMPLE_RATE)
            sims.append(s)
        avg_sim = np.mean(sims)
        std_sim = np.std(sims)
        print(f"  {name:15s}: {avg_sim:5.1f}% ± {std_sim:4.1f}%")

    # ─── Generate master comparison plot ───
    if HAS_MATPLOTLIB and HAS_SCIPY and len(best_hits) >= 1:
        print("\n── Generating master comparison plot ──")
        fig, axes = plt.subplots(2, 3, figsize=(18, 10))
        fig.suptitle('Reference Pickleball Hits — Top 5 Cleanest', fontsize=14, fontweight='bold')

        for i in range(min(5, len(best_hits))):
            row, col = divmod(i, 3)
            if row >= 2:
                break
            ax = axes[row][col]
            idx, clip, amp = best_hits[i]
            t = np.arange(len(clip)) / ref_sr * 1000
            ax.plot(t, clip, color='blue', linewidth=0.5)
            ax.set_title(f'Hit #{idx} (peak={amp:.3f})')
            ax.set_xlabel('Time (ms)')
            ax.set_ylabel('Amplitude')
            ax.grid(True, alpha=0.3)

        # Use remaining subplot for spectrum overlay
        ax_spec = axes[1][2] if len(best_hits) < 6 else axes[1][2]
        for i in range(min(3, len(best_hits))):
            idx, clip, amp = best_hits[i]
            N_pad = max(len(clip), SAMPLE_RATE // 10)
            padded = np.zeros(N_pad)
            padded[:len(clip)] = clip
            yf = np.abs(fft(padded))[:N_pad//2]
            xf = fftfreq(N_pad, 1.0/SAMPLE_RATE)[:N_pad//2]
            yf_db = 20 * np.log10(yf / max(yf.max(), 1e-10))
            ax_spec.plot(xf, yf_db, linewidth=0.8, alpha=0.7, label=f'Hit #{idx}')
        ax_spec.set_xlim(0, 4000)
        ax_spec.set_ylim(-50, 5)
        ax_spec.set_title('Spectral Overlay (Top 3 Hits)')
        ax_spec.set_xlabel('Frequency (Hz)')
        ax_spec.legend(fontsize=7)
        ax_spec.grid(True, alpha=0.3)

        plt.tight_layout()
        plt.savefig(str(OUTPUT_DIR / "reference_best_hits.png"), dpi=150, bbox_inches='tight')
        plt.close()
        print(f"  Saved: {OUTPUT_DIR}/reference_best_hits.png")

    # ─── Final Report ───
    print("\n" + "=" * 65)
    print("FINAL REPORT")
    print("=" * 65)
    best_match = max(similarities.items(), key=lambda x: x[1])
    print(f"\n  Best matching synthesis type: {best_match[0]} ({best_match[1]:.1f}%)")
    print(f"  Reference hits exported: {len(best_hits)} clips")
    print(f"\n  All outputs in: {OUTPUT_DIR}/")
    print("  - comparison_*.png  — Side-by-side spectrum analysis")
    print("  - reference_best_hits.png — Top real hits overview")
    print("  - best_hits/  — Clean individual hit WAVs")
    print("  - reference_clips/  — All detected hits")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Pickleball Sound Analysis & Export Tool
========================================
Replicates the GDScript synthesis in Python, exports WAV files,
generates waveform + spectrum plots for comparison with real recordings
(e.g., the VARIN oscilloscope trace from Tennis Warehouse study).

Reference: https://twu.tennis-warehouse.com/learning_center/pickleball/pickleballnoise.php
"""

import numpy as np
import wave
import struct
import os
import json
from pathlib import Path

try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
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

# ──────────────────────────────────────────────────────────────────────
# Constants (must match ball.gd exactly)
# ──────────────────────────────────────────────────────────────────────
SAMPLE_RATE = 44100.0

# Paddle constants
# Optimized via scipy.optimize (98.6% spectral match to real recording)
PADDLE_MODE_FREQ = 1273.0
PADDLE_MODE_UPPER_FREQ = 1425.0
PADDLE_RING_FREQ = 1800.0
BALL_STRIKE_FREQ = 922.0
BALL_HELMHOLTZ_FREQ = 1399.0
BALL_SHELL_FREQ = 1804.0
CONTACT_CHIRP_RANGE = 429.0
BRIGHTNESS_FREQ = 2870.0

# Body constants (centered at 441 Hz)
BODY_FREQ = 322.0
BODY_LOW_FREQ = 274.0
BODY_HIGH_FREQ = 366.0
BODY_MID_FREQ = 441.0
BODY_UPPER_FREQ = 560.0

# Court constants
COURT_BOUNCE_FREQ = 620.0
COURT_BOUNCE_UPPER_FREQ = 780.0
COURT_BOUNCE_BODY_FREQ = 150.0

# ──────────────────────────────────────────────────────────────────────
# Default tuning values (must match ball.gd)
# ──────────────────────────────────────────────────────────────────────
TUNING_DEFAULTS = {
    "paddle_attack_tune": -0.30,
    "paddle_metallic_tune": -0.55,
    "paddle_pitch_tune": 0.0,
    "paddle_sub_pitch_tune": -0.55,
    "paddle_pitch_blend_tune": 0.0,
    "paddle_upper_pitch_tune": 0.25,
    "paddle_body_pitch_tune": 0.0,
    "paddle_hollow_pitch_tune": -0.45,
    "paddle_ring_tune": 0.0,
    "paddle_body_tune": -0.20,
    "paddle_tail_tune": -0.35,
    "paddle_wood_tune": -0.25,
    "paddle_echo_tune": -0.60,
    "paddle_damp_tune": 0.55,
    "paddle_noise_tune": -0.70,
    "paddle_hollow_tune": -0.55,
    "paddle_clack_tune": -0.35,
    "paddle_compress_tune": 0.45,
    "paddle_dead_tune": 0.55,
    "paddle_presence_tune": -0.30,
    "paddle_rumble_tune": -0.55,
    "paddle_crackle_tune": -0.90,
    "paddle_reflection_tune": -0.20,
    "paddle_sweet_spot_tune": 0.20,
    "paddle_core_softness_tune": 0.70,
    "paddle_variation_tune": -0.35,
    "paddle_chirp_tune": 0.15,
    "paddle_helmholtz_tune": 0.0,
    "court_weight_tune": 0.0,
    "court_snap_tune": 0.0,
    "court_decay_tune": 0.0,
    "court_hardness_tune": 0.0,
    "court_surface_tune": 0.0,
}

T = TUNING_DEFAULTS  # shorthand


def exp_env(t, attack, decay_start, decay_rate):
    """Exponential attack-decay envelope matching ball.gd _exp_env"""
    if t < attack:
        return t / max(attack, 0.0001)
    if t < decay_start:
        return 1.0
    return np.exp(-(t - decay_start) * decay_rate)

exp_env_vec = np.vectorize(exp_env)


def create_paddle_sound(duration, amplitude, mode_gain, body_gain, click_gain,
                        ring_gain, mode_decay, body_decay, attack,
                        mode_pitch_scale, body_pitch_scale):
    """
    Replicate _create_paddle_sound from ball.gd in Python.
    Returns float64 numpy array of samples.
    """
    num_samples = int(duration * SAMPLE_RATE)
    t = np.arange(num_samples) / SAMPLE_RATE

    # Tuning-derived scales (matching ball.gd pre-loop calculations)
    pitch_scale = 1.0 + T["paddle_pitch_tune"] * 0.24
    attack_scale = 1.0 + T["paddle_attack_tune"] * 0.7
    metallic_scale = max(T["paddle_metallic_tune"], 0.0) * 0.6
    damp_scale = 1.0 + T["paddle_damp_tune"] * 0.65
    tail_scale = 1.0 - T["paddle_tail_tune"] * 0.55
    noise_scale = max(T["paddle_noise_tune"], 0.0) * 0.85
    wood_scale = 1.0 + T["paddle_wood_tune"] * 0.12
    ring_scale = 1.0 + T["paddle_ring_tune"] * 0.45
    body_scale = 1.0 + T["paddle_body_tune"] * 0.65
    hollow_scale = max(T["paddle_hollow_tune"], 0.0) * 0.7
    clack_scale = max(T["paddle_clack_tune"], 0.0) * 0.5
    off_center_scale = 1.0 + T["paddle_metallic_tune"] * 0.35
    sub_pitch_scale = 1.0 + T["paddle_sub_pitch_tune"] * 0.18
    low_pitch_blend = max(T["paddle_pitch_blend_tune"], 0.0) * 0.6
    pitch_blend = max(T["paddle_pitch_blend_tune"], 0.0) * 0.5
    upper_pitch_scale = 1.0 + T["paddle_upper_pitch_tune"] * 0.15
    body_pitch_scale_tune = 1.0 + T["paddle_body_pitch_tune"] * 0.12
    hollow_pitch_scale = 1.0 + T["paddle_hollow_pitch_tune"] * 0.2
    core_softness_scale = 1.0 + T["paddle_core_softness_tune"] * 0.55
    sweet_spot_scale = 1.0 + T["paddle_sweet_spot_tune"] * 0.15
    rumble_scale = max(T["paddle_rumble_tune"], 0.0) * 0.5
    crackle_scale = max(T["paddle_crackle_tune"], 0.0) * 0.4
    presence_scale = 1.0 + T["paddle_presence_tune"] * 0.25

    peak_window = duration * 0.45
    hit_variation = (np.random.random() * 2.0 - 1.0) * max(T["paddle_variation_tune"], 0.0) * 0.04

    chirp_scale_val = max(T["paddle_chirp_tune"], 0.0) * 0.8 + 0.15
    contact_duration = 0.002
    strike_decay = mode_decay
    helmholtz_decay = mode_decay * 1.4

    # Envelopes — simplified to match optimizer exactly
    strike_env = exp_env_vec(t, attack, attack, strike_decay)
    mode_env = exp_env_vec(t, attack, attack, mode_decay)
    body_env = exp_env_vec(t, attack * 0.7, attack * 0.7, body_decay)
    helmholtz_env = exp_env_vec(t, attack * 0.5, attack * 0.5, helmholtz_decay)
    ring_env = np.exp(-t * mode_decay * 1.2)
    click_env = np.exp(-t * strike_decay * 2.5)

    # Contact chirp
    chirp_factor = np.ones_like(t)
    contact_mask = t < contact_duration
    contact_phase = t[contact_mask] / contact_duration
    chirp_factor[contact_mask] = 1.0 + (1.0 - contact_phase) * (CONTACT_CHIRP_RANGE / BALL_STRIKE_FREQ) * chirp_scale_val

    # Simple pitch deltas (no multiplicative tuning)
    pitch_delta = 1.0 + T["paddle_pitch_tune"] * 0.12
    body_pitch_delta = 1.0 + T["paddle_body_pitch_tune"] * 0.10

    TAU = 2.0 * np.pi

    # ── Exact optimizer model (98.6% match) — NO tuning multipliers on amplitudes ──

    sf = mode_pitch_scale * pitch_delta * chirp_factor
    mf = mode_pitch_scale * pitch_delta * chirp_factor
    bf = body_pitch_scale * body_pitch_delta

    # PRIMARY: strike at 922 Hz (67% of power)
    strike = np.sin(t * BALL_STRIKE_FREQ * sf * TAU) * 0.780
    strike_harm = np.sin(t * BALL_STRIKE_FREQ * 1.5 * sf * TAU) * 0.023

    # SECONDARY: paddle mode at 1273 Hz (10% of power)
    pmode = np.sin(t * PADDLE_MODE_FREQ * mf * TAU) * 0.087
    pmode_sub = np.sin(t * PADDLE_MODE_FREQ * 0.92 * mf * TAU) * 0.022
    pmode_upper = np.sin(t * PADDLE_MODE_FREQ * 1.12 * mf * TAU) * 0.017
    ring = np.sin(t * PADDLE_RING_FREQ * mf * TAU) * 0.04

    # BODY: 200-500 Hz (9% of power)
    body_total = (
        np.sin(t * BODY_LOW_FREQ * bf * TAU) * 0.091 +
        np.sin(t * BODY_FREQ * bf * TAU) * 0.110 +
        np.sin(t * BODY_MID_FREQ * bf * TAU) * 0.110 +
        np.sin(t * BODY_UPPER_FREQ * bf * TAU) * 0.091
    )

    # HELMHOLTZ: 1399 Hz
    helmholtz = np.sin(t * BALL_HELMHOLTZ_FREQ * mf * TAU) * 0.283
    helmholtz_sub = np.sin(t * (BALL_HELMHOLTZ_FREQ * 0.88) * mf * TAU) * 0.113
    shell_vib = np.sin(t * BALL_SHELL_FREQ * mf * TAU) * 0.071

    # Foam bloom at 886 Hz
    foam = np.sin(t * 886.0 * pitch_delta * TAU) * np.exp(-t * 140.0) * 0.177

    # Noise + brightness
    click_noise = np.random.randn(num_samples) * 0.3
    bright1 = click_noise * np.sin(t * BRIGHTNESS_FREQ * TAU) * click_env * 0.72
    bright2 = click_noise * np.sin(t * BRIGHTNESS_FREQ * 1.33 * TAU) * click_env * 0.43
    bright3 = click_noise * np.sin(t * BRIGHTNESS_FREQ * 1.75 * TAU) * click_env * 0.22
    broad_click = click_noise * click_env * 0.36

    # Mix — exact optimizer gains, no tuning multipliers
    combined = (
        (strike + strike_harm) * strike_env +
        (pmode + pmode_sub + pmode_upper) * mode_env +
        body_total * body_env +
        (helmholtz + helmholtz_sub + shell_vib) * helmholtz_env +
        ring * ring_env * 0.30 +
        foam +
        bright1 +
        bright2 +
        bright3 +
        broad_click
    )

    # No amplitude modification — optimizer amplitudes are exact

    # Echo/reflection (simplified — full version uses a delay buffer)
    echo_gain = max(T["paddle_echo_tune"], 0.0) * 0.25
    reflection_gain = max(T["paddle_reflection_tune"], 0.0) * 0.18
    echo_delay_samples = int(0.0042 * SAMPLE_RATE)
    reflection_delay_samples = int(0.0078 * SAMPLE_RATE)

    if echo_gain > 0.001 and echo_delay_samples < num_samples:
        combined[echo_delay_samples:] += combined[:-echo_delay_samples] * echo_gain * 0.35
    if reflection_gain > 0.001 and reflection_delay_samples < num_samples:
        combined[reflection_delay_samples:] += combined[:-reflection_delay_samples] * reflection_gain * 0.25

    return combined * amplitude


def create_court_bounce_sound(speed):
    """Replicate _create_court_bounce_sound from ball.gd"""
    speed_ratio = np.clip(speed / 10.0, 0.0, 1.0)
    court_tone_scale = 1.0 + T["court_snap_tune"] * 0.12
    court_weight_scale = 1.0 + T["court_weight_tune"] * 0.55
    court_amp_scale = 1.0 + T["court_weight_tune"] * 0.12
    court_decay_scale = 1.0 + T["court_decay_tune"] * 0.8
    court_hardness_scale = 1.0 + T["court_hardness_tune"] * 0.65
    court_surface_scale = 1.0 + T["court_surface_tune"] * 0.35
    duration = 0.020 + speed_ratio * 0.008 + max(T["court_decay_tune"], 0.0) * 0.006

    num_samples = int(duration * SAMPLE_RATE)
    t = np.arange(num_samples) / SAMPLE_RATE
    TAU = 2.0 * np.pi

    thwack_env = exp_env_vec(t, max(0.0006 - T["court_snap_tune"] * 0.0002, 0.0002),
                              0.0006, (125.0 + T["court_snap_tune"] * 18.0) / court_decay_scale)
    weight_env = exp_env_vec(t, 0.0004, 0.0016 * court_decay_scale, 48.0 / court_decay_scale)
    click_env = np.exp(-t * (180.0 + T["court_snap_tune"] * 35.0 + T["court_hardness_tune"] * 40.0))

    thwack = np.sin(t * COURT_BOUNCE_FREQ * court_tone_scale * court_hardness_scale * court_surface_scale * TAU) * 0.65
    thwack_upper = np.sin(t * COURT_BOUNCE_UPPER_FREQ * court_tone_scale * court_hardness_scale * court_surface_scale * TAU) * 0.22
    weight = np.sin(t * COURT_BOUNCE_BODY_FREQ * TAU) * 0.55
    weight_sub = np.sin(t * (COURT_BOUNCE_BODY_FREQ * 0.72) * TAU) * 0.18
    slap = np.sin(t * 920.0 * court_hardness_scale * court_surface_scale * TAU) * 0.10
    ball_ring = np.sin(t * BALL_HELMHOLTZ_FREQ * 0.85 * TAU) * 0.06
    click = np.random.randn(num_samples) * click_env

    combined = (
        (thwack + thwack_upper) * 0.52 * thwack_env +
        (weight + weight_sub) * 0.32 * court_weight_scale * weight_env +
        ball_ring * 0.15 * thwack_env +
        slap * max(T["court_hardness_tune"], 0.0) * 0.30 * thwack_env +
        click * (0.035 + T["court_snap_tune"] * 0.015 + T["court_hardness_tune"] * 0.008)
    )

    return combined * (0.45 + speed_ratio * 0.12) * court_amp_scale


def save_wav(filename, samples, sample_rate=44100):
    """Save float samples to 16-bit WAV"""
    samples = np.clip(samples, -1.0, 1.0)
    int_samples = (samples * 32767).astype(np.int16)
    with wave.open(filename, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(int(sample_rate))
        wf.writeframes(int_samples.tobytes())
    print(f"  Saved: {filename} ({len(int_samples)} samples, {len(int_samples)/sample_rate*1000:.1f}ms)")


def plot_waveform_and_spectrum(samples, title, filename, sample_rate=44100):
    """
    Plot waveform (matching oscilloscope format) and frequency spectrum.
    """
    if not HAS_MATPLOTLIB:
        print(f"  [matplotlib not available — skipping plot for {title}]")
        return

    t_ms = np.arange(len(samples)) / sample_rate * 1000  # time in ms

    fig = plt.figure(figsize=(14, 10))
    gs = GridSpec(2, 2, figure=fig, hspace=0.35, wspace=0.3)

    # ─── Waveform (oscilloscope style) ───
    ax1 = fig.add_subplot(gs[0, :])
    # Normalize to approximate Pa scale for comparison with oscilloscope
    peak_val = np.max(np.abs(samples))
    if peak_val > 0:
        pa_scale = samples / peak_val * 3.5  # Scale to match VARIN ~3.5 Pa peak
    else:
        pa_scale = samples
    ax1.plot(t_ms / 1000, pa_scale, color='red', linewidth=0.5)
    ax1.set_xlabel('Time (seconds)')
    ax1.set_ylabel('Air Pressure (Pa) [normalized]')
    ax1.set_title(f'Oscilloscope Tracing — {title}')
    ax1.set_xlim(-0.002, 0.04)
    ax1.set_ylim(-3.5, 4.5)
    ax1.grid(True, alpha=0.3)
    ax1.axhline(y=0, color='k', linewidth=0.5)

    # ─── Frequency Spectrum ───
    if HAS_SCIPY:
        ax2 = fig.add_subplot(gs[1, 0])
        # FFT
        N = len(samples)
        yf = np.abs(fft(samples))[:N // 2]
        xf = fftfreq(N, 1.0 / sample_rate)[:N // 2]

        # Normalize
        yf_db = 20 * np.log10(yf / max(yf.max(), 1e-10))

        ax2.plot(xf, yf_db, color='blue', linewidth=0.8)
        ax2.set_xlabel('Frequency (Hz)')
        ax2.set_ylabel('Magnitude (dB)')
        ax2.set_title(f'Frequency Spectrum — {title}')
        ax2.set_xlim(0, 5000)
        ax2.set_ylim(-60, 5)
        ax2.grid(True, alpha=0.3)
        ax2.axvline(x=1185, color='orange', linestyle='--', alpha=0.6, label='Mode (1185 Hz)')
        ax2.axvline(x=1280, color='green', linestyle='--', alpha=0.6, label='Helmholtz (1280 Hz)')
        ax2.axvline(x=220, color='red', linestyle='--', alpha=0.6, label='Body (220 Hz)')
        ax2.axvline(x=2000, color='gray', linestyle=':', alpha=0.6, label='2 kHz ceiling')
        ax2.legend(fontsize=7, loc='upper right')

        # ─── Power Distribution ───
        ax3 = fig.add_subplot(gs[1, 1])
        # Calculate power in frequency bands
        power = yf ** 2
        total_power = power.sum()

        bands = [
            ("0-200", 0, 200),
            ("200-500", 200, 500),
            ("500-750", 500, 750),
            ("750-1000", 750, 1000),
            ("1000-1500", 1000, 1500),
            ("1500-2000", 1500, 2000),
            ("2000+", 2000, 5000),
        ]

        band_powers = []
        band_labels = []
        for label, f_lo, f_hi in bands:
            mask = (xf >= f_lo) & (xf < f_hi)
            bp = power[mask].sum() / max(total_power, 1e-10) * 100
            band_powers.append(bp)
            band_labels.append(label)

        colors = ['#2196F3', '#4CAF50', '#8BC34A', '#CDDC39', '#FFC107', '#FF9800', '#F44336']
        ax3.bar(band_labels, band_powers, color=colors, edgecolor='white', linewidth=0.5)
        ax3.set_xlabel('Frequency Band (Hz)')
        ax3.set_ylabel('Power (%)')
        ax3.set_title(f'Power Distribution — {title}')
        ax3.axhline(y=80, color='red', linestyle='--', alpha=0.4, label='Research: 80% below 750 Hz')

        # Calculate cumulative power below 750 Hz
        below_750 = sum(bp for (label, f_lo, f_hi), bp in zip(bands, band_powers) if f_hi <= 750)
        ax3.text(0.02, 0.95, f'Power < 750 Hz: {below_750:.1f}%',
                 transform=ax3.transAxes, fontsize=9, verticalalignment='top',
                 bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
        ax3.legend(fontsize=7)
        ax3.tick_params(axis='x', rotation=45)

    plt.suptitle(f'Pickleball Sound Analysis: {title}', fontsize=14, fontweight='bold', y=0.98)
    plt.savefig(filename, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Saved plot: {filename}")


def main():
    output_dir = Path("/Users/arjomagno/Documents/github-repos/pickleball-godot/audio_analysis")
    output_dir.mkdir(exist_ok=True)

    print("=" * 60)
    print("PICKLEBALL SOUND SYNTHESIS ANALYSIS")
    print("=" * 60)

    # ─── Generate all paddle hit types ───
    hit_types = {
        "thock_slow":  {"speed": 6.0,  "fn": "thock"},
        "thock_fast":  {"speed": 11.0, "fn": "thock"},
        "volley":      {"speed": 3.0,  "fn": "volley"},
        "smash":       {"speed": 15.0, "fn": "smash"},
        "serve":       {"speed": 10.0, "fn": "serve"},
    }

    print("\n── Paddle Hit Sounds ──")
    for name, params in hit_types.items():
        np.random.seed(42)  # Reproducible noise
        if params["fn"] == "thock":
            speed = params["speed"]
            speed_ratio = np.clip(speed / 12.0, 0.0, 1.0)
            samples = create_paddle_sound(
                0.028 + speed_ratio * 0.004, 0.84, 1.0, 1.0, 0.12, 0.025,
                211.0, 95.0, 0.00020,
                1.0 + speed_ratio * 0.02, 1.0 + speed_ratio * 0.02
            )
        elif params["fn"] == "volley":
            samples = create_paddle_sound(0.032, 0.64, 0.85, 0.95, 0.06, 0.008, 165.0, 80.0, 0.00035, 0.96, 0.97)
        elif params["fn"] == "smash":
            samples = create_paddle_sound(0.025, 1.0, 1.1, 0.90, 0.18, 0.05, 250.0, 85.0, 0.00015, 1.03, 1.01)
        elif params["fn"] == "serve":
            samples = create_paddle_sound(0.028, 0.90, 1.0, 1.0, 0.10, 0.03, 205.0, 90.0, 0.00020, 1.0, 1.0)

        wav_path = str(output_dir / f"paddle_{name}.wav")
        png_path = str(output_dir / f"paddle_{name}.png")
        save_wav(wav_path, samples)
        plot_waveform_and_spectrum(samples, f"Paddle {name.replace('_', ' ').title()}", png_path)

    # ─── Court bounces ───
    print("\n── Court Bounce Sounds ──")
    for speed, label in [(3.0, "slow"), (6.0, "medium"), (9.0, "fast")]:
        np.random.seed(42)
        samples = create_court_bounce_sound(speed)
        wav_path = str(output_dir / f"court_bounce_{label}.wav")
        png_path = str(output_dir / f"court_bounce_{label}.png")
        save_wav(wav_path, samples)
        plot_waveform_and_spectrum(samples, f"Court Bounce ({label})", png_path)

    # ─── Summary Report ───
    print("\n" + "=" * 60)
    print("ANALYSIS SUMMARY")
    print("=" * 60)
    print(f"\nAll files exported to: {output_dir}/")
    print("\nWAV files can be played in any audio player.")
    print("PNG plots show waveform + spectrum + power distribution.")
    print("\nCompare the oscilloscope plots with the VARIN trace:")
    print("  - Waveform shape (attack sharpness, decay profile)")
    print("  - Frequency spectrum (peak location, bandwidth)")
    print("  - Power distribution (% below 750 Hz vs research 80%)")
    print()

    # List all generated files
    for f in sorted(output_dir.iterdir()):
        size_kb = f.stat().st_size / 1024
        print(f"  {f.name:40s} {size_kb:6.1f} KB")


if __name__ == "__main__":
    main()

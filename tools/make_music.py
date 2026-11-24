#!/usr/bin/env python3
"""Renders the game's music and point jingles (chip style, key of C).

  python3 tools/make_music.py            # writes assets/audio/music/*.wav and assets/audio/cues/*.wav
  python3 tools/make_music.py --stats    # also prints length, peak and loudness per file

Needs numpy and scipy. Everything is seeded, so a re-run gives the same files. Music is
32 kHz stereo and loops end to end; Godot compresses it on import (QOA, loop forward, set in
the .import files).
"""
import os, sys, wave
import numpy as np
from scipy.signal import butter, lfilter, resample_poly

SR = 44100
MUSIC_SR = 32000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOTES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    """'C4', 'F#5', 'Bb3' -> frequency."""
    semis = NOTES[name[0]] + name.count("#") - name.count("b")
    return 440.0 * 2 ** ((semis + (int(name[-1]) + 1) * 12 - 69) / 12)


def env(n, attack, decay, sustain, release):
    """Attack / decay / sustain / release envelope over n samples (times in seconds)."""
    a, d, r = int(attack * SR), int(decay * SR), int(release * SR)
    out = np.full(n, sustain)
    a = min(a, n)
    out[:a] = np.linspace(0, 1, a, endpoint=False)
    d = min(d, n - a)
    out[a:a + d] = np.linspace(1, sustain, d, endpoint=False)
    r = min(r, n)
    out[n - r:] *= np.linspace(1, 0, r)
    return out


def phase(freq, n, vibrato=0.0):
    t = np.arange(n) / SR
    return np.cumsum(freq * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t) * np.minimum(t / 0.25, 1)) / SR)


def pulse(freq, seconds, duty=0.5, vibrato=0.0):
    return np.where(phase(freq, int(seconds * SR), vibrato) % 1 < duty, 1.0, -1.0)


def triangle(freq, seconds):
    return 2 * np.abs(2 * (phase(freq, int(seconds * SR)) % 1) - 1) - 1


def sine(freq, seconds):
    return np.sin(2 * np.pi * phase(freq, int(seconds * SR)))


def lowpass(x, cutoff, order=2):
    b, a = butter(order, cutoff / (SR / 2))
    return lfilter(b, a, x, axis=0)


def highpass(x, cutoff, order=2):
    b, a = butter(order, cutoff / (SR / 2), btype="high")
    return lfilter(b, a, x, axis=0)


class Track:
    """A mono buffer that notes are added into; `mix` pans it into the stereo song."""

    def __init__(self, seconds):
        self.buf = np.zeros(int(seconds * SR))

    def add(self, at, sig, gain=1.0):
        start = int(at * SR)
        end = min(start + len(sig), len(self.buf))
        if end > start:
            self.buf[start:end] += sig[:end - start] * gain


def pan(mono, position):
    """position -1 (left) .. 1 (right), equal power."""
    angle = (position + 1) * np.pi / 4
    return np.stack([mono * np.cos(angle), mono * np.sin(angle)], axis=1)


def echo(stereo, delay, feedback, mix):
    """Cross-channel echo: each repeat lands on the other side."""
    d = int(delay * SR)
    out = stereo.copy()
    tap = stereo.copy()
    for _ in range(5):
        tap = np.roll(tap[:, ::-1], d, axis=0) * feedback
        tap[:d] = 0
        out += tap * mix
    return out


def kick(seconds=0.22):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(55 + 110 * np.exp(-t * 38)) / SR) * np.exp(-t * 16)
    knock = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 60) * 0.5   # audible on a phone speaker
    return body + knock


def snare(rng, seconds=0.16):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    noise = highpass(rng.uniform(-1, 1, n), 1800) * np.exp(-t * 30)
    return noise * 0.8 + np.sin(2 * np.pi * 210 * t) * np.exp(-t * 42) * 0.5


def hat(rng, seconds=0.05, decay=90.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    return highpass(rng.uniform(-1, 1, n), 7000) * np.exp(-t * decay)


def finish(stereo, loop_seconds, peak=0.7):
    """Fold the tail past the loop point back onto the start, so the loop joins cleanly."""
    n = int(round(loop_seconds * SR))
    out = stereo[:n].copy()
    tail = stereo[n:]
    out[:len(tail)] += tail
    out = np.tanh(out / np.max(np.abs(out)) * 1.15)
    return out / np.max(np.abs(out)) * peak


# ---------------------------------------------------------------- title theme

TITLE_CHORDS = ["C", "G", "Am", "F", "C", "G", "F", "G", "Am", "F", "C", "G", "F", "G", "C", "G"]
CHORD_TONES = {
    "C": ("C", "E", "G"), "G": ("G", "B", "D"), "Am": ("A", "C", "E"), "F": ("F", "A", "C"),
    "Dm": ("D", "F", "A"), "Em": ("E", "G", "B"),
    "Fmaj7": ("F", "A", "C", "E"), "G6": ("G", "B", "D", "E"), "Em7": ("E", "G", "B", "D"),
    "Am7": ("A", "C", "E", "G"), "Dm7": ("D", "F", "A", "C"), "Cmaj7": ("C", "E", "G", "B"),
}
# (beat, beats, note) per bar; every strong beat sits on a chord tone
TITLE_LEAD = [
    [(0, 1, "E5"), (1, .5, "G5"), (1.5, 1, "C6"), (2.5, .5, "G5"), (3, 1, "E5")],
    [(0, 1, "D5"), (1, .5, "G5"), (1.5, 1, "B5"), (2.5, .5, "G5"), (3, 1, "D5")],
    [(0, 1, "C5"), (1, .5, "E5"), (1.5, 1, "A5"), (2.5, .5, "G5"), (3, 1, "E5")],
    [(0, 1.5, "F5"), (1.5, .5, "A5"), (2, 1, "G5"), (3, .5, "E5"), (3.5, .5, "D5")],
    [(0, 1, "E5"), (1, .5, "G5"), (1.5, 1, "C6"), (2.5, .5, "D6"), (3, 1, "E6")],
    [(0, 1, "D6"), (1, .5, "B5"), (1.5, 1, "G5"), (2.5, .5, "A5"), (3, 1, "B5")],
    [(0, 1, "A5"), (1, .5, "F5"), (1.5, .5, "A5"), (2, 1.5, "C6"), (3.5, .5, "A5")],
    [(0, 2, "G5"), (2, .5, "B5"), (2.5, .5, "A5"), (3, .5, "G5"), (3.5, .5, "D5")],
    [(0, .5, "A5"), (.5, .5, "A5"), (1, 1, "C6"), (2, .5, "E5"), (2.5, .5, "A5"), (3, 1, "C6")],
    [(0, .5, "A5"), (.5, .5, "A5"), (1, 1, "C6"), (2, .5, "F5"), (2.5, .5, "A5"), (3, 1, "C6")],
    [(0, .5, "G5"), (.5, .5, "G5"), (1, 1, "C6"), (2, 1, "E6"), (3, .5, "D6"), (3.5, .5, "C6")],
    [(0, 1.5, "D6"), (1.5, .5, "B5"), (2, 2, "G5")],
    [(0, .5, "F5"), (.5, .5, "A5"), (1, 1, "C6"), (2, .5, "A5"), (2.5, .5, "C6"), (3, 1, "F6")],
    [(0, .5, "G5"), (.5, .5, "B5"), (1, 1, "D6"), (2, .5, "B5"), (2.5, .5, "D6"), (3, 1, "G6")],
    [(0, 1, "E6"), (1, .5, "C6"), (1.5, 1, "G5"), (2.5, .5, "E5"), (3, 1, "G5")],
    [(0, .5, "D5"), (.5, .5, "G5"), (1, .5, "B5"), (1.5, .5, "D6"), (2, 1, "G5"), (3, .5, "B5"), (3.5, .5, "D6")],
]


def chord_notes(chord, octave):
    """Chord tones climbing from the root in the given octave."""
    out, last = [], -1
    for name in CHORD_TONES[chord]:
        o = octave
        while NOTES[name[0]] + 12 * o <= last:
            o += 1
        last = NOTES[name[0]] + 12 * o
        out.append(hz(name + str(o)))
    return out


def title_theme():
    rng = np.random.default_rng(11)
    beat = 60 / 120
    bar = beat * 4
    loop = bar * len(TITLE_CHORDS)
    total = loop + 1.5
    lead, arp, bass, drums, hats = (Track(total) for _ in range(5))
    for index, chord in enumerate(TITLE_CHORDS):
        start = index * bar
        for at, beats, name in TITLE_LEAD[index]:
            seconds = beats * beat * 0.92
            note = pulse(hz(name), seconds, 0.5, 0.006) * env(int(seconds * SR), 0.006, 0.08, 0.6, 0.05)
            lead.add(start + at * beat, note, 0.55)
        tones = chord_notes(chord, 4)
        tones = tones + [tones[0] * 2]
        for step, tone in enumerate([0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 2, 1, 3]):
            seconds = beat / 4
            note = pulse(tones[tone], seconds, 0.125) * env(int(seconds * SR), 0.003, 0.07, 0.25, 0.02)
            arp.add(start + step * beat / 4, note, 0.3 if step % 4 else 0.42)
        root = chord_notes(chord, 3)[0]
        fifth = chord_notes(chord, 3)[2]
        if fifth < root: fifth *= 2
        for step, tone in enumerate([root, root, root * 2, root, fifth, root, root * 2, fifth]):
            seconds = beat / 2 * 0.85
            n = int(seconds * SR)
            note = (triangle(tone, seconds) + 0.25 * pulse(tone, seconds, 0.25)) * env(n, 0.004, 0.1, 0.7, 0.03)
            bass.add(start + step * beat / 2, note, 0.6)
        fill = index % 8 == 7
        for b in range(4):
            if b % 2 == 0: drums.add(start + b * beat, kick(), 0.9)
            else: drums.add(start + b * beat, snare(rng), 0.6)
            for half in range(2):
                hats.add(start + (b + half / 2) * beat, hat(rng), 0.32 if half else 0.2)
        drums.add(start + 2.5 * beat, kick(), 0.6)
        if fill:
            for sixteenth in range(4): drums.add(start + (3 + sixteenth / 4) * beat, snare(rng, 0.1), 0.35 + 0.08 * sixteenth)
    melodic = pan(lowpass(lead.buf, 5200), 0.0) + pan(lowpass(arp.buf, 4200), -0.45)
    song = echo(melodic, beat * 0.75, 0.38, 0.22)
    song += pan(lowpass(bass.buf, 1800), 0.0) + pan(drums.buf, 0.0) + pan(hats.buf, 0.4)
    return finish(song, loop), loop


# ---------------------------------------------------------------- match groove

MATCH_CHORDS = ["Fmaj7", "G6", "Em7", "Am7", "Dm7", "G6", "Cmaj7", "Cmaj7"] * 2
# which chord tone (0 = root .. 3 = top, 4 = root an octave up) each eighth note plays; None = rest
MATCH_PATTERNS = [
    [0, 2, 4, None, 3, 2, None, 1],
    [0, None, 2, 3, None, 4, 2, None],
    [4, 3, None, 2, 0, None, 2, 3],
    [0, 2, 3, None, 4, None, 3, 2],
]


def mallet(freq, seconds=0.5):
    """Soft marimba-like note: a sine with a quick wooden overtone."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * freq * t) * np.exp(-t * 7) + 0.3 * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-t * 30)) * np.minimum(t / 0.003, 1)


def match_groove():
    """Laid-back and quiet, so the paddle pops and bounces stay in front of it."""
    rng = np.random.default_rng(23)
    beat = 60 / 100
    bar = beat * 4
    loop = bar * len(MATCH_CHORDS)
    total = loop + 2.5
    pad, mallets, bass, drums, shaker = (Track(total) for _ in range(5))
    for index, chord in enumerate(MATCH_CHORDS):
        start = index * bar
        for tone in chord_notes(chord, 3):
            seconds = bar * 1.05
            n = int(seconds * SR)
            note = (sine(tone * 2, seconds) + 0.4 * triangle(tone * 2, seconds)) * env(n, 0.5, 0.4, 0.8, 0.7)
            pad.add(start, note, 0.16)
        tones = chord_notes(chord, 4)
        tones = tones + [tones[0] * 2]
        pattern = MATCH_PATTERNS[(index + index // 8) % len(MATCH_PATTERNS)]
        for step, tone in enumerate(pattern):
            if tone is None: continue
            swing = beat * 0.06 if step % 2 else 0.0
            mallets.add(start + step * beat / 2 + swing, mallet(tones[tone]), 0.5 if step % 2 == 0 else 0.36)
        root = chord_notes(chord, 2)[0] * 2
        for at, beats in [(0, 1.4), (1.5, 0.45), (2.5, 1.2)]:
            seconds = beats * beat
            n = int(seconds * SR)
            note = (sine(root, seconds) + 0.35 * sine(root * 2, seconds) + 0.15 * sine(root * 3, seconds)) * env(n, 0.008, 0.15, 0.7, 0.08)
            bass.add(start + at * beat, note, 0.5)
        for b in range(4):
            if b % 2 == 0: drums.add(start + b * beat, kick(0.2), 0.55)
            else: drums.add(start + b * beat, snare(rng, 0.07), 0.2)   # soft rim click
            for half in range(2):
                shaker.add(start + (b + half / 2) * beat + (beat * 0.06 if half else 0.0), hat(rng, 0.07, 55.0), 0.13 if half else 0.08)
    melodic = pan(mallets.buf, 0.25) + pan(lowpass(pad.buf, 2400), -0.2)
    song = echo(melodic, beat * 1.5, 0.35, 0.25)
    song += pan(lowpass(bass.buf, 1500), 0.0) + pan(drums.buf, 0.0) + pan(shaker.buf, -0.4)
    return finish(song, loop), loop


# ---------------------------------------------------------------- point jingles

def jingle(notes, seconds, duty=0.5, bright=5000.0):
    """notes: (start seconds, length seconds, name, gain). Mono, with a soft echo tail."""
    track = Track(seconds)
    for at, length, name, gain in notes:
        n = int(length * SR)
        tone = pulse(hz(name), length, duty, 0.005) + 0.5 * triangle(hz(name), length)
        track.add(at, tone * env(n, 0.004, 0.09, 0.45, min(0.12, length * 0.5)), gain)
    out = lowpass(track.buf, bright)
    d = int(0.11 * SR)
    out[d:] += out[:-d] * 0.22
    fade = int(0.03 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)
    return out / np.max(np.abs(out)) * 0.7


def jingles():
    return {
        "point_won": jingle([(0, .1, "C5", .8), (.08, .1, "E5", .8), (.16, .3, "G5", 1)], 0.6),
        "point_lost": jingle([(0, .16, "G4", .8), (.15, .34, "Eb4", .9)], 0.6, 0.5, 2600),
        "side_out": jingle([(0, .12, "D5", .8), (.12, .28, "A4", .9)], 0.5, 0.25, 3800),
        "match_won": jingle([(0, .11, "C5", .8), (.12, .11, "C5", .8), (.24, .11, "C5", .8), (.36, .2, "E5", .9),
                             (.56, .2, "G5", .9), (.78, .9, "C6", 1), (.78, .9, "E5", .5), (.78, .9, "G5", .5)], 1.9),
        "match_lost": jingle([(0, .3, "A4", .8), (.3, .3, "F4", .8), (.6, .3, "D4", .8), (.9, .8, "A3", .9), (.9, .8, "E4", .5)], 1.9, 0.5, 2400),
    }


# ---------------------------------------------------------------- output

def write_wav(path, data, rate=SR):
    data = np.asarray(data)
    with wave.open(path, "wb") as f:
        f.setnchannels(1 if data.ndim == 1 else 2)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes((np.clip(data, -1, 1) * 32767).astype("<i2").tobytes())


def stats(name, data, loop=None):
    rms = 20 * np.log10(np.sqrt(np.mean(data ** 2)))
    peak = 20 * np.log10(np.max(np.abs(data)))
    join = "" if loop is None else "  loop %.2fs  join step %.4f" % (loop, float(np.max(np.abs(data[0] - data[-1]))))
    print("%-12s %6.2fs  peak %5.1f dB  rms %5.1f dB%s" % (name, len(data) / SR, peak, rms, join))


def main():
    show = "--stats" in sys.argv
    music_dir = os.path.join(ROOT, "assets/audio/music")
    cue_dir = os.path.join(ROOT, "assets/audio/cues")
    os.makedirs(music_dir, exist_ok=True)
    os.makedirs(cue_dir, exist_ok=True)
    for name, maker in [("title_theme", title_theme), ("match_groove", match_groove)]:
        song, loop = maker()
        if show: stats(name, song, loop)
        # resample three loops and keep the middle one, so the loop point stays seamless
        frames = int(round(loop * MUSIC_SR))
        wide = resample_poly(np.concatenate([song, song, song]), MUSIC_SR // 100, SR // 100, axis=0)
        write_wav(os.path.join(music_dir, name + ".wav"), wide[frames:frames * 2], MUSIC_SR)
    for name, data in jingles().items():
        if show: stats(name, data)
        write_wav(os.path.join(cue_dir, name + ".wav"), data)


if __name__ == "__main__":
    main()

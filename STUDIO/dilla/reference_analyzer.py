#!/usr/bin/env python3
"""Spectral analyzer for the dilla reference pipeline.

Reads the reference mix (and, when demucs ran, the separated stems) and
measures what the next render needs to know: tempo and its confidence,
onset density per bar, offbeat share, micro-timing spread, swing ratio,
per-stem energy shares, spectral brightness, key and chord changes, a
melody summary, and 16-step drum grids for kick and snare.

numpy + scipy only. Deterministic: same audio in, same JSON out.

usage: reference_analyzer.py MIX.wav [--stems STEMS_DIR] --json FEATURES.json
               [--max-duration SECONDS]
"""

import argparse
import json
import os
import sys

import numpy as np
from scipy.signal import stft, resample_poly, find_peaks, medfilt

SR = 22050
HOP = 512
NFFT = 1024
FRAME_S = HOP / SR


def load_mono(path):
    import soundfile as sf
    data, sr = sf.read(path, dtype="float32", always_2d=True)
    mono = data.mean(axis=1)
    if sr != SR:
        g = np.gcd(sr, SR)
        mono = resample_poly(mono, SR // g, sr // g).astype(np.float32)
    return mono


def magnitude(mono):
    f, t, z = stft(mono, fs=SR, nperseg=NFFT, noverlap=NFFT - HOP, padded=False, boundary=None)
    return f, t, np.abs(z).astype(np.float32)


def spectral_flux(mag, floor_bin=1):
    diff = np.diff(mag, axis=1, prepend=mag[:, :1])
    flux = np.maximum(diff, 0.0).sum(axis=0)
    flux[floor_bin:] = flux[floor_bin:]
    return flux


def pick_onsets(flux):
    env = flux - medfilt(flux, 31)
    env[env < 0] = 0.0
    if env.max() <= 0:
        return np.array([]), env
    # Vinyl crackle and tape noise sprinkle tiny spikes; the onset gate must
    # sit above them or density measures the wear layer instead of the music.
    gate = max(env.max() * 0.14, float(np.percentile(env, 92)))
    peaks, _ = find_peaks(env, height=gate, distance=int(0.085 / FRAME_S))
    if len(peaks) == 0:
        return peaks, env
    # Quadratic interpolation on log-envelope: onset time to ~1/10 frame,
    # which is what 8-15 ms micro-timing measurement needs at a 23 ms hop.
    logenv = np.log(env + 1e-9)
    refined = []
    for p in peaks:
        if 0 < p < len(logenv) - 1:
            a, b, c = logenv[p - 1], logenv[p], logenv[p + 1]
            denom = a - 2.0 * b + c
            shift = 0.5 * (a - c) / denom if abs(denom) > 1e-9 else 0.0
            refined.append(p + np.clip(shift, -0.5, 0.5))
        else:
            refined.append(float(p))
    return np.array(refined), env


def estimate_tempo(env):
    n = len(env)
    if n < 64:
        return 90.0, 0.0
    x = env - env.mean()
    ac = np.correlate(x, x, mode="full")[n - 1:]
    ac /= ac[0] + 1e-12
    fps = 1.0 / FRAME_S
    lags = np.arange(0, int(fps * 1.6))  # down to ~37 bpm
    lo = int(fps * 60.0 / 200.0)
    hi = min(int(fps * 60.0 / 40.0), len(ac) - 1)
    if hi <= lo:
        return 90.0, 0.0
    seg = np.abs(ac[lo:hi])
    best = lo + int(np.argmax(seg))
    strength = float(seg.max())
    local = np.abs(ac[max(lo, best - 12):min(hi, best + 12)])
    conf = float(strength / (local.mean() + 1e-9) - 1.0)
    bpm = 60.0 * fps / best
    while bpm < 70:
        bpm *= 2
    while bpm > 180:
        bpm /= 2
    return float(bpm), float(np.clip(conf, 0.0, 1.0))


def beat_phase(env, bpm):
    fps = 1.0 / FRAME_S
    lag = 60.0 / bpm * fps
    n = len(env)
    best_phase, best_score = 0.0, -1.0
    for k in range(64):
        phase = k * lag / 64.0
        idx = np.arange(phase, n - 1, lag)
        idx = idx.astype(int)
        if len(idx) < 4:
            continue
        score = env[idx].mean()
        if score > best_score:
            best_score, best_phase = score, phase
    # Everything downstream (grid features, drum grids) works in seconds.
    return float(best_phase * FRAME_S)


def grid_features(onsets, env, bpm, phase):
    fps = 1.0 / FRAME_S
    beat_s = 60.0 / bpm
    six_s = beat_s / 4.0
    bar_s = beat_s * 4.0
    onset_t = onsets * FRAME_S
    if len(onset_t) == 0:
        return {"onset_density_per_bar": 0.0, "offbeat_onset_share": 0.5,
                "timing_spread_ms": 0.0, "swing_ratio": 0.5}
    rel = (onset_t - phase) % six_s
    nearest = np.round((onset_t - phase) / six_s).astype(int)
    dev_ms = (rel - (rel > six_s / 2) * six_s) * 1000.0
    dev_ms = ((onset_t - phase) / six_s - nearest) * six_s * 1000.0
    odd = (nearest % 2) == 1
    offbeat_share = float(np.clip(odd.mean(), 0.0, 1.0))
    spread = float(np.clip(np.std(dev_ms[onset_t > phase + beat_s]), 0.0, 120.0))
    swing = 0.5 + float(np.clip(np.median(dev_ms[odd]) / (six_s * 1000.0), 0.0, 0.2)) if odd.any() else 0.5
    n_bars = max((onset_t.max() - phase) / bar_s, 1.0)
    density = float(len(onset_t) / n_bars)
    return {"onset_density_per_bar": density,
            "offbeat_onset_share": offbeat_share,
            "timing_spread_ms": spread,
            "swing_ratio": float(np.clip(swing, 0.5, 0.7))}


KRUM_MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
KRUM_MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
PC_SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
PC_FLAT = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
FLAT_BIAS = {5, 7, 10, 8, 3, 1}  # prefer flat spellings for flats-friendly keys


def chroma_of(mag, freqs):
    chroma = np.zeros(12, dtype=np.float64)
    freq_res = freqs[1] - freqs[0]
    mag_sq = (mag ** 2).mean(axis=1)
    for pc in range(12):
        energy = 0.0
        for h in (1, 2, 3, 4):
            f = 65.406 * (2.0 ** (pc / 12.0)) * h
            if f * (2 ** (0.5 / 12.0)) >= freqs[-1]:
                continue
            lo = int(f / (2 ** (0.5 / 12.0)) / freq_res)
            hi = int(f * (2 ** (0.5 / 12.0)) / freq_res)
            if hi > lo and lo < len(mag_sq):
                energy += float(mag_sq[lo:min(hi, len(mag_sq))].sum())
        chroma[pc] = energy
    total = chroma.sum()
    return chroma / total if total > 0 else chroma


def estimate_key(chroma):
    cands = []
    for rot in range(12):
        c = np.roll(chroma, -rot)
        for name, profile in (("maj", KRUM_MAJOR), ("min", KRUM_MINOR)):
            r = np.corrcoef(c, profile)[0, 1]
            cands.append((r, rot, name))
    cands.sort(reverse=True)
    r, rot, name = cands[0]
    # Relative-major/minor pairs share a key signature; let the chroma third
    # decide which one the recording actually lives in.
    if len(cands) > 1:
        r2, rot2, name2 = cands[1]
        if rot2 == (rot + 9) % 12 and name != name2 and abs(r - r2) < 0.05:
            third_flat = chroma[(rot + 3) % 12]
            third_nat = chroma[(rot + 4) % 12]
            if name == "maj" and third_flat > third_nat * 1.02:
                name = "min"
            elif name == "min" and third_nat > third_flat * 1.02:
                name = "maj"
    label = f"{PC_FLAT[rot] if rot in FLAT_BIAS else PC_SHARP[rot]} {name}"
    return label, float(r)


CHORD_TEMPLATES = {}


def _build_templates():
    for root in range(12):
        for quality, ivs in (("maj", (0, 4, 7)), ("min", (0, 3, 7)), ("7", (0, 4, 7, 10)), ("m7", (0, 3, 7, 10))):
            t = np.zeros(12)
            for iv in ivs:
                t[(root + iv) % 12] = 1.0
            CHORD_TEMPLATES[f"{PC_FLAT[root] if root in FLAT_BIAS else PC_SHARP[root]}{quality}"] = t / np.linalg.norm(t)


def chord_changes(chroma_frames, fps):
    _build_templates()
    # median-smooth each pitch class over ~1s, then cosine-distance novelty
    k = max(int(fps * 2) | 1, 3)
    smooth = np.stack([medfilt(chroma_frames[i], k) for i in range(12)])
    norms = np.linalg.norm(smooth, axis=0) + 1e-9
    unit = smooth / norms
    cos = (unit[:, 1:] * unit[:, :-1]).sum(axis=0)
    novelty = 1.0 - cos
    if novelty.max() <= 0:
        return {"chord_changes": 0, "chords": []}
    thr = max(np.median(novelty) + 1.5 * novelty.std(), novelty.max() * 0.45)
    peaks, _ = find_peaks(novelty, height=thr, distance=int(fps * 1.5))
    changes = int(len(peaks))
    chords = []
    bounds = [0, *(peaks + 1).tolist(), chroma_frames.shape[1]]
    for a, b in zip(bounds[:-1], bounds[1:]):
        seg = chroma_frames[:, a:b].mean(axis=1)
        seg = seg / (np.linalg.norm(seg) + 1e-9)
        best_label, best_score = "", -1.0
        for label, t in CHORD_TEMPLATES.items():
            s = float(seg @ t)
            if s > best_score:
                best_score, best_label = s, label
        chords.append({"t": round(a * FRAME_S, 2), "label": best_label})
    return {"chord_changes": changes, "chords": chords}


def melody_summary(mag, freqs, bpm):
    band = (freqs >= 150) & (freqs <= 1400)
    seg = mag[band]
    f_band = freqs[band]
    frame_energy = seg.sum(axis=0)
    gate = np.percentile(frame_energy, 55)
    voiced = frame_energy > gate
    peak_bin = seg.argmax(axis=0)
    f0s = f_band[peak_bin][voiced]
    if len(f0s) < 8:
        return {"median_hz": None, "range_semitones": None, "note_density_per_bar": None}
    f0s = np.sort(f0s)
    median = float(np.median(f0s))
    lo, hi = np.percentile(f0s, 10), np.percentile(f0s, 90)
    range_st = float(12.0 * np.log2(max(hi, 1e-6) / max(lo, 1e-6)))
    runs = int(np.abs(np.diff(peak_bin[voiced]) > 2).sum() + 1)
    bar_s = 60.0 / bpm * 4
    density = float(runs / max(mag.shape[1] * FRAME_S / bar_s, 1.0))
    return {"median_hz": round(median, 1), "range_semitones": round(range_st, 1),
            "note_density_per_bar": round(density, 2)}


def band_flux(mag, freqs, lo, hi):
    band = (freqs >= lo) & (freqs <= hi)
    return spectral_flux(mag[band])


def drum_grids(mix_mag, freqs, mag_drums, freqs_d, bpm, phase):
    def grid16(mag_, freqs_, lo, hi):
        flux = band_flux(mag_, freqs_, lo, hi)
        onsets, _ = pick_onsets(flux)
        if len(onsets) == 0:
            return [0.0] * 16
        beat_s = 60.0 / bpm
        six_s = beat_s / 4.0
        steps = np.round(((onsets * FRAME_S - phase) % six_s * 0 + (onsets * FRAME_S - phase) / six_s)).astype(int) % 16
        hist = np.bincount(steps, minlength=16).astype(float)
        return [round(float(h) / hist.max(), 3) for h in hist] if hist.max() > 0 else [0.0] * 16

    kick = grid16(mag_drums, freqs_d, 30, 150) if mag_drums is not None else grid16(mix_mag, freqs, 30, 150)
    snare = grid16(mag_drums, freqs_d, 150, 700) if mag_drums is not None else grid16(mix_mag, freqs, 150, 700)
    hat = grid16(mag_drums, freqs_d, 5000, 12000) if mag_drums is not None else grid16(mix_mag, freqs, 5000, 12000)
    return {"kick": kick, "snare": snare, "hat": hat}


def energy_shares(stems_dir):
    names = {"drums": "drums_energy_share", "bass": "bass_energy_share",
             "other": "other_energy_share", "vocals": "vocal_energy_share"}
    powers = {}
    for stem, key in names.items():
        path = os.path.join(stems_dir, f"{stem}.wav")
        if os.path.isfile(path):
            mono = load_mono(path)
            powers[key] = float(np.mean(mono ** 2) + 1e-12)
    total = sum(powers.values())
    if total <= 0:
        return None
    shares = {k: round(v / total, 3) for k, v in powers.items()}
    shares["other_energy_share"] = round(shares.get("other_energy_share", 0.0) + shares.get("vocal_energy_share", 0.0) * 0.5, 3)
    return shares


def band_shares_from_mix(mag, freqs):
    mag_sq = (mag ** 2).mean(axis=1)
    def share(lo, hi):
        band = (freqs >= lo) & (freqs <= hi)
        return float(mag_sq[band].sum())
    drums = share(30, 160) + share(4500, 14000) * 0.6 + share(150, 700) * 0.25
    bass = share(30, 220) * 0.7
    other = mag_sq.sum() - drums - bass
    total = mag_sq.sum() + 1e-12
    return {"drums_energy_share": round(max(drums, 0.0) / total, 3),
            "bass_energy_share": round(max(bass, 0.0) / total, 3),
            "other_energy_share": round(max(other, 0.0) / total, 3),
            "vocal_energy_share": 0.0}


def sections_of(mono, bpm):
    win = int(SR * 1.0)
    n = len(mono) // win
    if n < 4:
        return []
    energy = np.array([float(np.mean(mono[i * win:(i + 1) * win] ** 2)) for i in range(n)])
    hi, lo = np.percentile(energy, 80), np.percentile(energy, 30)
    span = 60.0 / bpm * 8  # 8-bar sections
    out = []
    t = 0.0
    dur = len(mono) / SR
    while t < dur:
        e = energy[min(int(t), n - 1)]
        level = "high" if e > hi else ("low" if e < lo else "mid")
        out.append({"start": round(t, 1), "level": level})
        t += span
    return out


def analyze(path, stems_dir=None, max_duration=None):
    mono = load_mono(path)
    if max_duration and max_duration > 0:
        mono = mono[: int(SR * max_duration)]
    freqs, times, mag = magnitude(mono)
    flux = spectral_flux(mag)
    onsets, env = pick_onsets(flux)
    bpm, conf = estimate_tempo(env)
    phase = beat_phase(env, bpm)

    # The pocket is a drum measurement: read it from the demucs drums stem when
    # separation ran, else from a kick+snare+hat band flux of the mix. Tempo
    # stays on the full mix, which is the more stable periodicity.
    drums_mag, drums_freqs = None, None
    if stems_dir and os.path.isdir(stems_dir):
        dpath = os.path.join(stems_dir, "drums.wav")
        if os.path.isfile(dpath):
            dmono = load_mono(dpath)
            drums_freqs, _t, drums_mag = magnitude(dmono[: len(mono)])
    if drums_mag is not None:
        drum_flux = spectral_flux(drums_mag[(drums_freqs >= 30) & (drums_freqs <= 9000)])
        d_onsets, _denv = pick_onsets(drum_flux)
    else:
        band = ((freqs >= 30) & (freqs <= 160)) | ((freqs >= 150) & (freqs <= 700)) | ((freqs >= 4000) & (freqs <= 12000))
        drum_flux = spectral_flux(mag[band])
        d_onsets, _denv = pick_onsets(drum_flux)

    feats = {"duration_s": round(len(mono) / SR, 2)}
    feats.update(grid_features(d_onsets, env, bpm, phase))
    feats["bpm"] = round(bpm, 2)
    feats["bpm_confidence"] = round(conf, 3)

    shares = energy_shares(stems_dir) if stems_dir else None
    if shares is None:
        shares = band_shares_from_mix(mag, freqs)
    feats.update(shares)

    centroid = float((mag.mean(axis=1) * freqs).sum() / (mag.mean(axis=1).sum() + 1e-12))
    feats["brightness_hz"] = round(centroid, 1)

    chroma = chroma_of(mag, freqs)
    key, key_score = estimate_key(chroma)
    chroma_frames = np.stack([chroma_of(mag[:, i:i + 22], freqs) if mag.shape[1] > i + 4 else chroma
                              for i in range(0, mag.shape[1], 22)], axis=1)
    harmony = {"key": key, "key_confidence": round(key_score, 3)}
    frame_stride_s = 22 * FRAME_S
    harmony.update(chord_changes(chroma_frames, 1.0 / frame_stride_s))
    feats["harmony"] = harmony
    feats["melody"] = melody_summary(mag, freqs, bpm)
    feats["drum_grid"] = drum_grids(mag, freqs, drums_mag, drums_freqs, bpm, phase)
    feats["sections"] = sections_of(mono, bpm)
    return feats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mix")
    ap.add_argument("--stems", default=None)
    ap.add_argument("--json", required=True)
    ap.add_argument("--max-duration", type=float, default=None)
    args = ap.parse_args()
    feats = analyze(args.mix, args.stems, args.max_duration)
    def _plain(obj):
        if isinstance(obj, dict):
            return {k: _plain(v) for k, v in obj.items()}
        if isinstance(obj, (list, tuple)):
            return [_plain(v) for v in obj]
        if isinstance(obj, (np.floating, np.integer)):
            v = float(obj)
            return v if np.isfinite(v) else None
        if isinstance(obj, float) and not np.isfinite(obj):
            return None
        return obj

    with open(args.json, "w") as fh:
        json.dump(_plain(feats), fh, indent=1, sort_keys=True)
    print(f"analyzer: {args.mix} -> {args.json} ({feats['bpm']} BPM, {feats['harmony']['key']})")


if __name__ == "__main__":
    main()

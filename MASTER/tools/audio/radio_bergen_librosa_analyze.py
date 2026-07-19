#!/usr/bin/env python3
"""Librosa playlist analysis — invoked by: ruby dilla.rb radio-bergen-librosa"""

from __future__ import annotations

import json
import math
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import librosa
import numpy as np
import yaml

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "radio_bergen_tracks.yml"
OUT = ROOT.parent / "reports" / "radio_bergen_good_music_analysis.yml"
SCRATCH = ROOT / ".analysis_cache"

AUDIO_ROOTS = [
    Path("../../../../pub2").resolve(),
    Path("../../../../pub3/.index.html").resolve(),
]

LOCAL_ALIASES = {
    "/audio/akmd/akmd-stailings.mp3": ["akmd-stailings.mp3"],
    "/audio/akmd/akmd_mike_t-alt_kan_skje.mp3": ["akmd_mike_t-alt_kan_skje.mp3", "mike_t_and_johann-alt_kan_skje.mp3"],
    "/audio/akmd/akmd_mike_t_jan_hakim-diverse.mp3": ["akmd_mike_t_jan_hakim-diverse.mp3"],
    "/audio/akmd/angelo_reira_and_johann-sandviken_hotell_a.mp3": ["angelo_reira_and_johann-sandviken_hotell_a.mp3"],
    "/audio/akmd/angelo_reira_and_johann-sandviken_hotell_b.mp3": ["angelo_reira_and_johann-sandviken_hotell_b.mp3"],
    "/audio/akmd/chase_swayze-traffic.mp3": ["chase_swayze-traffic.mp3", "chase_swayze-underated.mp3"],
    "/audio/akmd/haisam_and_johann-pb1.mp3": ["haisam_and_johann-pb1.mp3"],
    "/audio/akmd/jan_hakim_and_johann-stailings_a.mp3": ["jan_hakim_and_johann-stailings_a.mp3"],
    "/audio/akmd/mike_t_jr-rauingar.mp3": ["mike_t_jr-rauingar.mp3", "johann-rauingar.mp3"],
}

PITCH_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def slug(artist: str, title: str) -> str:
    s = f"{artist}-{title}".lower()
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


def resolve_local(src: str | None) -> Path | None:
    if not src:
        return None
    names = LOCAL_ALIASES.get(src, [Path(src).name])
    for root in AUDIO_ROOTS:
        for name in names:
            p = root / name
            if p.is_file():
                return p
    return None


def yt_audio_path(video_id: str, start: int | None = None) -> Path | None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    out = SCRATCH / f"yt_{video_id}.m4a"
    if out.is_file() and out.stat().st_size > 10_000:
        return out
    url = f"https://www.youtube.com/watch?v={video_id}"
    cmd = ["yt-dlp", "-f", "bestaudio[abr<=128]/bestaudio", "-o", str(out), "--no-playlist", "--quiet", "--no-warnings"]
    if start:
        cmd += ["--download-sections", f"*{start}-{start + 90}"]
    else:
        cmd += ["--download-sections", "*0-90"]
    cmd.append(url)
    try:
        subprocess.run(cmd, check=True, timeout=120)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None
    return out if out.is_file() else None


def estimate_key(chroma: np.ndarray) -> dict:
    chroma_mean = np.mean(chroma, axis=1)
    major = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
    minor = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
    scores = []
    for i in range(12):
        rotated = np.roll(chroma_mean, -i)
        scores.append((PITCH_NAMES[i] + " major", float(np.dot(rotated, major))))
        scores.append((PITCH_NAMES[i] + " minor", float(np.dot(rotated, minor))))
    scores.sort(key=lambda x: -x[1])
    return {"top": scores[0][0], "runner_up": scores[1][0]}


def analyze_file(path: Path) -> dict:
    y, sr = librosa.load(path, sr=22050, mono=True, duration=90.0)
    tempo, _ = librosa.beat.beat_track(y=y, sr=sr, units="time")
    bpm = float(tempo) if np.isscalar(tempo) else float(tempo[0])
    while bpm < 70:
        bpm *= 2
    while bpm > 110:
        bpm /= 2
    onset_times = librosa.onset.onset_detect(y=y, sr=sr, units="time", backtrack=True)
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    cent = float(np.mean(librosa.feature.spectral_centroid(y=y, sr=sr)))
    rolloff = float(np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr, roll_percent=0.85)))
    return {
        "tool": "librosa",
        "duration_sec": round(len(y) / sr, 2),
        "tempo_bpm": round(bpm, 1),
        "key": estimate_key(chroma),
        "onset_count": int(len(onset_times)),
        "spectral": {"centroid_hz_mean": round(cent, 1), "rolloff_hz_mean": round(rolloff, 1)},
    }


def main() -> int:
    manifest = yaml.safe_load(MANIFEST.read_text())
    rows = []
    for row in manifest.get("local_mp3", []):
        rows.append({**row, "source": "local_mp3", "youtube_id": None, "start": None})
    for row in manifest.get("external_reference", {}).get("youtube", []):
        rows.append({**row, "source": "youtube_reference"})

    tracks_out = []
    measured = 0
    for i, row in enumerate(rows):
        print(f"[{i+1}/{len(rows)}] {row['artist']} — {row['title']}", flush=True)
        audio_path = resolve_local(row.get("src"))
        source_note = None
        if not audio_path and row.get("youtube_id"):
            audio_path = yt_audio_path(row["youtube_id"], row.get("start"))
            source_note = "youtube_90s_clip"
        elif audio_path:
            source_note = "local_archive"
        analysis = None
        if audio_path:
            try:
                analysis = analyze_file(audio_path)
                measured += 1
            except Exception as exc:
                analysis = {"error": str(exc)}
        tracks_out.append({
            "id": slug(row["artist"], row["title"]),
            "artist": row["artist"],
            "title": row["title"],
            "source": row["source"],
            "audio_path": str(audio_path) if audio_path else None,
            "audio_source": source_note,
            "librosa_analysis": analysis,
        })

    report = {
        "meta": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "tools": ["librosa", "yt-dlp"],
            "tracks_total": len(rows),
            "tracks_measured": measured,
        },
        "tracks": tracks_out,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(yaml.dump(report, default_flow_style=False, sort_keys=False))
    print(f"\nwrote {OUT}")
    print(json.dumps(report["meta"], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
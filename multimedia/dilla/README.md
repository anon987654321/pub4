# Dilla - Neo-Soul Beat Generator

J Dilla / Flying Lotus / Madlib style beat generation with authentic microtiming.

## Quick Start

```bash
ruby dilla.rb
```

Press Ctrl+C to stop after generating tracks.

## Features

3 drum styles with authentic microtiming:
- Dilla (64% swing, ±40ms kick drift, -35ms snare drag)
- FlyLo (58% swing, glitchy, random beat skips)
- Techno (52% swing, 4-on-floor precision)

6 jazz progressions from Slum Village tracks
SP-404/MPC mastering chain with tape saturation
Professor Crane TTS narration (educational commentary)
SoX-based synthesis (no external samples)
Auto-cleanup of temp files

## Dependencies

SoX (detected at: `sox.exe`)

## Output

WAV files, 44.1kHz stereo, ~8-10 MB per track, ~90 seconds duration
Saved to current directory with format: `progression_TIMESTAMP.wav`

## Architecture

Main: `dilla.rb` (249 lines)
Modules in `__shared/`:
- `@constants.rb` - Configuration and constants
- `@generators.rb` - Drum, pad, and bass generators
- `@mastering.rb` - Mixing and mastering chain
- `@tts.rb` - Professor Crane TTS system
- `progressions.json` - 6 jazz progressions (externalized data)

## Cache

Runtime files stored in `../.cache/`:
- `checkpoints/` - Temporary audio files
- `tts_cache/` - Cached TTS MP3s
- `output/` - Generated tracks

All temp files auto-cleaned after generation.

## Technical Details

Drums: SoX synthesis with microtiming offsets
Pads: Warm analog-style detuning, multi-layer synthesis
Bass: Walking basslines following chord roots
Mastering: Crane Song HEDD-style EQ + compression + stereo width

All processing via SoX command-line synthesis.
No external samples required.

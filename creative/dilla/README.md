# Dilla v74.0.0

J Dilla Beat Generator - Produces complete tracks using J Dilla's chord progressions and microtiming techniques.

## Features

- **J Dilla microtiming**: ±40ms kick drift, -35ms snare drag
- **Chord progressions**: 6 Slum Village progressions from JSON
- **SP-404/MPC3000 effects**: Tape saturation, reverb, chorus
- **Professor Crane TTS**: Educational narration explaining techniques
- **Pure SoX synthesis**: No samples required
- **3 drum styles**: Dilla (drunk timing), FlyLo (glitchy), Techno (industrial)

## Dependencies

OpenBSD:
```
pkg_add sox ruby
```

Linux:
```
apt install sox ruby
```

## Usage

Generate continuous beats:
```
ruby dilla.rb
```

Verbose debug mode:
```
DEBUG=1 ruby dilla.rb
```

## Output

- Generates complete tracks with drums, pads, and walking basslines
- Saves WAV files with timestamps
- Auto-cleanup of temporary files
- Professor Crane narration explains production techniques

## Architecture

Modular design with 5 components:
- `@constants.rb` - Configuration and helpers
- `@generators.rb` - Pad, drum, and bass synthesis (593 lines)
- `@mastering.rb` - Mixing and mastering chain
- `@tts.rb` - Text-to-speech narration
- `progressions.json` - Chord data

Total: ~1,349 lines across 5 modules

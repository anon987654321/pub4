# SOS Dilla v2.1.0
Cross-platform lo-fi music production system for generating J Dilla-style beats and dub techno.
## Features
- **Dub Techno Generation**: King Tubby, Basic Channel, Rhythm & Sound styles
- **J Dilla Hip-Hop**: MPC3000/SP-1200 sampler emulation with swing timing

- **Vintage Gear Emulation**: 12-bit/14-bit bitcrushing, tape saturation

- **Random Lo-Fi Chains**: Procedural effect chains (tape, vinyl, cosmic, industrial)

- **Cross-Platform**: Works on Termux (Android), Cygwin, OpenBSD, macOS, Linux

## Requirements
- **Ruby** 2.7+
- **FFmpeg** (universal audio backend)

### Installation
**OpenBSD:**
```bash

pkg_add ffmpeg ruby

```

**Linux (Debian/Ubuntu):**
```bash

sudo apt install ffmpeg ruby

```

**macOS:**
```bash

brew install ffmpeg ruby

```

**Cygwin (Windows):**
```bash

apt-cyg install ffmpeg ruby

```

**Termux (Android):**
```bash

pkg install ffmpeg ruby

```

## Usage
### Generate Dub Techno
```bash

./dilla.rb dub [pattern] [progression] [key] [bpm]

# Examples:
./dilla.rb dub one_drop dub_meditative E 120

./dilla.rb dub steppers rhythm_and_sound Gm 126

./dilla.rb dub atmospheric basic_channel Am 128

```

**Patterns:**
- `one_drop` - Strong hit on beat 3, reggae foundation

- `steppers` - Four-on-the-floor mechanized groove

- `rockers` - Syncopated driving rhythm

- `atmospheric` - Berlin minimal, mechanized precision

**Progressions:**
- `dub_meditative` - i-iv (tension release)

- `dub_tension` - i-v (builds tension)

- `rhythm_and_sound` - min7 chords, warm depth

- `basic_channel` - single chord drone

### Generate J Dilla Beats
```bash

./dilla.rb dilla [style] [key] [bpm]

# Examples:
./dilla.rb dilla donuts C 95

./dilla.rb dilla fantastic Am 88

./dilla.rb dilla shining D 92

```

### Apply Vintage Gear Character
```bash

./dilla.rb gear <type> <input.wav>

# Examples:
./dilla.rb gear sp1200 sample.wav    # E-mu SP-1200 (12-bit grit)

./dilla.rb gear mpc3000 loop.wav     # Akai MPC3000 (14-bit warm)

./dilla.rb gear sp303 drums.wav      # Roland SP-303 (lo-fi charm)

./dilla.rb gear s950 bass.wav        # Akai S950 (vintage sampler)

```

**Available Gear:**
- `sp1200` - E-mu SP-1200 (12-bit, Dilla's secret weapon)

- `mpc3000` - Akai MPC3000 (14-bit, warm character)

- `sp303` - Roland SP-303 (lo-fi, tape simulation)

- `s950` - Akai S950 (12-bit, vintage sampler)

- `mpc60` - Akai MPC60 (12-bit, classic hip-hop)

- `tx16w` - Yamaha TX16W (12-bit, gritty)

### Generate Random Lo-Fi Chain
```bash

./dilla.rb random [aesthetic] [seed]

# Examples:
./dilla.rb random authentic        # Classic tape/vinyl wear

./dilla.rb random tape             # Tape saturation focus

./dilla.rb random vinyl            # Vinyl crackle focus

./dilla.rb random cosmic 42        # Reproducible with seed

```

**Aesthetics:**
- `authentic` - Balanced tape + vinyl wear

- `dark` - Heavy low-end, crushed dynamics

- `deep` - Sub-bass emphasis, wide reverb

- `tape` - Tape saturation, wow/flutter

- `vinyl` - Surface noise, crackle

- `gritty` - Aggressive bitcrushing

- `cosmic` - Spacey delays, modulation

- `industrial` - Harsh distortion

### Master with Vintage Color
```bash

./dilla.rb master <file.wav> [era]

# Examples:
./dilla.rb master beat.wav king_tubby        # Jamaica 1970s dub

./dilla.rb master track.wav basic_channel    # Berlin minimal

./dilla.rb master mix.wav rhythm_and_sound   # Modern dub techno

```

**Eras:**
- `king_tubby` - Jamaica 1970s, spring reverb + tape echo

- `basic_channel` - Berlin minimal meets dub (deep reverb)

- `rhythm_and_sound` - Warmth with precision

- `wackie` - South Bronx grit, raw character

- `mpc3000` - MPC3000 14-bit warmth

- `sp1200` - SP-1200 12-bit grit

### Show Chord Progressions
```bash

./dilla.rb chords [artist] [album]

# Examples:
./dilla.rb chords dilla fantastic_vol2

./dilla.rb chords flying_lotus la

./dilla.rb chords madlib madvillainy

```

### List All Options
```bash

./dilla.rb list

```

### Export Config as JSON
```bash

./dilla.rb config > my_config.json

```

## Configuration
Place `dilla_config.json` in the same directory as `dilla.rb`:
```json
{

  "chords": {

    "dilla_fantastic_vol2": {

      "players": ["Dm7", "G7", "Cmaj7", "Fmaj7"],

      "fall_in_love": ["Fmaj7", "Em7", "Dm7", "Cmaj7"]

    }

  },

  "timing": {

    "dilla_swing": {

      "sweet_spot": [53, 56],

      "tempo_range": [82, 92],

      "nudge_ms": {

        "kick": -8,

        "snare": 12,

        "hihat": -3

      }

    }

  }

}

```

## Output
All generated files are saved to `~/dilla_output/` with timestamps:
- `dub_one_drop_E_120_20260101_201245.wav`

- `dilla_donuts_C_95_20260101_201345.wav`

- `sp1200_20260101_201445.wav`

## Technical Details
### Dilla Timing
- **Sweet Spot**: 53-56% swing (quantized but slightly behind the beat)

- **Micro-nudges**: Kick -8ms, Snare +12ms, Hihat -3ms

- **Tempo Range**: 82-92 BPM (classic Dilla zone)

### Dub Techno Principles
Based on Bahadırhan Koçer's "Understanding Dub Drums":

- **One-Drop**: Strong hit on beat 3 (reggae foundation)

- **Steppers**: Four-on-the-floor (mechanized precision)

- **Delays**: 16th note (125ms), dotted 8th (375ms)

- **Reverb**: Spring (King Tubby), Plate (Berlin minimal)

### Vintage Gear Specs
- **SP-1200**: 12-bit, 26.04 kHz sampling (Dilla's main tool)

- **MPC3000**: 14-bit, 44.1 kHz (warm, clean)

- **MPC60**: 12-bit, 40 kHz (classic hip-hop grit)

## Sources & Inspiration
- **J Dilla**: Fantastic Vol 1 & 2, Donuts, The Shining
- **Flying Lotus**: Los Angeles (2008)

- **Madlib**: Madvillainy, Beat Konducta series

- **Sonitex STX-1260**: Hardware reference

- **Bahadırhan Koçer**: "Understanding Dub Drums" (dub techno analysis)

- **arXiv papers**: Tape/vinyl emulation research

## License
MIT License - Free for personal and commercial use
## Author
Built with love for lo-fi production

# Dilla.rb - J Dilla Beat Generator

Algorithmically recreate J Dilla's revolutionary timing mathematics and vintage hardware processing.

## Overview

Hip-hop beat production with mathematical precision based on J Dilla's documented techniques.

**Core Technology:**
- Golden ratio swing timing (54.2%)
- Voice-specific microtiming
- Vintage hardware emulation (MPC3000, SP-1200)
- Analog console modeling

## Installation

```bash
# Install dependencies
brew install fluidsynth sox        # macOS
apt-get install fluidsynth sox     # Linux

# Install Ruby gem dependency
gem install midilib

# Make executable
chmod +x dilla.rb
```

## Features

**J Dilla Chord Progressions**
- `donuts_classic`: min7 → maj7 → min7 → dom7 (signature Donuts sound)
- `neo_soul`: min9 → maj9 → min7 → dom7 (extended jazz harmonies)
- `mpc_soul`: maj9 → min7 → dom13 → min7 (MPC3000 characteristic)
- `drunk`: min7♭5 → maj7 → min7 → dom7 (maximum timing deviation)

**Vintage Hardware Emulation**
- **SP-1200**: 26.04kHz sampling with 12-bit quantization and aliasing artifacts
- **MPC3000**: 96 PPQN resolution with disabled quantization for natural feel
- **Analog Console**: Channel crosstalk, transformer saturation, thermal noise

**Mathematical Timing Engine**
- Golden ratio swing (54.2%) based on Dilla's documented preferences
- Voice-specific microtiming: roots early (-12 ticks), sevenths late (+15 ticks)
- Humanization: ±15 velocity variance, ±65ms timing deviations
- MPC jitter simulation: ±4 samples random variance

## Usage

```bash
# Generate classic Donuts progression in Db at 94 BPM
ruby dilla.rb gen donuts_classic Db 94

# Create neo-soul progression in Ab major
ruby dilla.rb gen neo_soul Ab 86

# List all available progressions
ruby dilla.rb list

# Show technical information
ruby dilla.rb info
```

## Audio Processing Chain

1. **MIDI Generation**: 384 PPQN resolution with voice-specific microtiming
2. **FluidSynth Rendering**: Dry signal generation with neo-soul soundfonts
3. **Vintage Processing**: Sample rate conversion for aliasing artifacts
4. **Analog Modeling**: Tape wobble, compression, and harmonic saturation
5. **Console Summing**: Transformer modeling and crosstalk simulation

## Technical Specifications

**Timing Mathematics**
- Base swing: 54.2% (approximates golden ratio 1.618)
- Timing deviation: 10-30ms from strict quantization
- Voice offsets: kick (-8ms), snare (+12ms), hats (-3ms), bass (-5ms)
- Humanization variance: 18ms timing, 15 velocity units

**Vintage Emulation Parameters**
- SP-1200: 26040Hz, 12-bit, no anti-aliasing
- MPC3000: 44100Hz, 16-bit, swing disabled
- Analog saturation: 2nd harmonic (warmth), 3rd harmonic (edge)
- Console crosstalk: -70dB between adjacent channels

**Harmonic Language**
- Extended jazz voicings: min7, maj9, dom13, min7♭5
- Dorian mode emphasis for characteristic melancholy
- Quartal harmony structures (stacked 4ths)
- Modal interchange and chromatic mediants

## File Structure

```
dilla.rb                   # Main executable
dilla_output/              # Generated audio files
  dilla_donuts_classic_*.wav
  dilla_neo_soul_*.wav
  dilla_mpc_soul_*.wav
  dilla_drunk_*.wav
```

## Dependencies

- **FluidSynth**: MIDI synthesis engine
- **SoX**: Audio processing toolkit  
- **midilib**: Ruby MIDI file generation
- **Soundfont**: FluidR3_GM.sf2 or neo-soul equivalent

## Troubleshooting

**"No soundfont found"**
```bash
# macOS
brew install fluid-synth --with-libsndfile

# Linux  
apt-get install fluid-soundfont-gm
```

**"Missing midilib gem"**
```bash
gem install midilib
```

**"Command not found: fluidsynth"**
```bash
# macOS
brew install fluidsynth sox

# Linux
apt-get install fluidsynth sox
```

## Algorithm Details

**Timing Engine**
1. **Swing Calculation**: Uses 54.2% ratio derived from golden ratio approximation
2. **Microtiming Application**: Voice-specific offsets maintain harmonic coherence
3. **Humanization Layer**: Adds controlled randomness within measured parameters
4. **Hardware Jitter**: Simulates MPC3000's ±4 sample timing variance

**Vintage Processing**
1. **Sample Rate Artifacts**: Preserves aliasing from missing reconstruction filters
2. **Bit Depth Reduction**: Linear 12-bit quantization with characteristic distortion
3. **Analog Saturation**: Jiles-Atherton hysteresis model for tape behavior  
4. **Console Modeling**: Transformer saturation curves and channel crosstalk

# Strange Voice System - Maximum Weirdness TTS
# Free, Offline, Independent, VERY VERY Strange

## Overview

**100% free, offline, zero dependencies on cloud services or Copilot**

This system creates **intentionally imperfect, heavily corrupted, extremely lofi voices** using:
- **espeak** (free, offline formant synthesis)
- **Sox** (audio effect processor)
- **Ruby** (orchestration)

**No API keys. No internet. No Copilot. Just pure weirdness.**

## What Makes It Strange?

### 1. Text Corruption (40-50% intensity)
- **Stuttering**: "T-T-T-Testing the s-s-s-system"
- **Word repetition**: "the the voice voice system"
- **Glitch sounds**: "*bzzt*", "*crackle*", "*static*", "*pop*", "*glitch*"
- **Random pauses**: "Testing ... the ... voice"
- **Phonetic corruption**: s→zh, th→zz, r→w, l→w

### 2. Random Voice Selection
Each run picks a random espeak voice variant:
- **en+croak** (pitch 0, speed 60) - Extremely deep croaky demon
- **en+whisper** (pitch 99, speed 300) - High-pitched whisper chipmunk
- **en+m3** (pitch 10, speed 100) - Male deep slow monster
- **en+f4** (pitch 80, speed 220) - Female high fast alien
- **en+croak** (pitch 40, speed 150) - Mid-range croak creature

### 3. Extreme Lofi Effects (7 presets)

#### **maximum_weird** (Default)
```
Downsample to 5.5kHz → Upsample (aliasing) → 
Lowpass 2.8kHz → Overdrive 35 → Reverb 80 → 
Pitch +50 → Heavy tremolo → Echo → Gain -5
```
**Result**: Extreme bitcrushed, distorted, warbling alien voice

#### **telephone_hell**
```
Bandpass 400-2400Hz → Rate 8kHz → 
Overdrive 50 → Reverb 60 → Tremolo 40%
```
**Result**: Telephone quality but destroyed

#### **underwater**
```
Lowpass 800Hz → Reverb 90 → Echo → 
Pitch -200 → Tremolo 60%
```
**Result**: Deep muffled underwater transmission

#### **nightmare**
```
Pitch -300 → Reverb 95 → Echo → 
Tremolo 90% → Overdrive 20 → Phaser
```
**Result**: Horror movie demon voice

#### **robot_broken**
```
Rate 8kHz (bitcrush) → Overdrive 60 → 
Pitch +100 → Tremolo 10Hz → Flanger
```
**Result**: Malfunctioning cyborg/robot

#### **vinyl_destroyed**
```
Bandpass 150-4000Hz → Bitcrush 11kHz → 
Overdrive 25 → Reverb 50 → Tremolo 0.05Hz
```
**Result**: Worn-out vinyl record

#### **cassette_melted**
```
Lowpass 3500Hz → Pitch -50 → Bend (warping) → 
Overdrive 15 → Tremolo 40%
```
**Result**: Melted cassette tape warble

## Installation

### 1. espeak (Already installed via Cygwin)
```bash
# Test
espeak "Hello" --stdout | head -c 100
```

### 2. Sox (Already installed via Cygwin)
```bash
# Test
sox --version
```

### 3. Ruby script
```bash
# Already at G:\pub\strange_voice.rb
ruby strange_voice.rb say "Test"
```

## Usage

### Basic Strange Voice
```bash
ruby strange_voice.rb say "Your text here"
```

**Output example:**
```
[CORRUPTED] Y-Y-Y-Your *static* t-t-t-text ... t-t-t-text *bzzt* here *crackle*
[EFFECTS] Applying maximum_weird...
# Plays extremely weird corrupted voice
```

### Choose Preset
```bash
ruby strange_voice.rb preset nightmare "Spooky message"
ruby strange_voice.rb preset underwater "Deep transmission"
ruby strange_voice.rb preset robot_broken "System error"
```

### Demo All Presets
```bash
ruby strange_voice.rb demo
```

Plays all 7 presets in sequence with different corrupted text.

## How It Works

### Pipeline
```
Text Input
    ↓
Text Corruption (stutter, repeat, glitches)
    ↓
Random Voice Selection (en+croak, en+whisper, etc.)
    ↓
espeak Generation → temp.wav
    ↓
Sox Extreme Effects (bitcrush, distortion, reverb, etc.)
    ↓
Direct to Audio Device (streaming)
    ↓
Temp file deleted
```

### Effect Chain Example (maximum_weird)
```
1. Highpass 200Hz          - Remove bass rumble
2. Rate 5512Hz             - Extreme downsample (bitcrush)
3. Rate 22050Hz            - Upsample with aliasing artifacts
4. Lowpass 2800Hz          - Aggressive cut
5. Overdrive 35            - Heavy distortion
6. Reverb 80               - Massive reverb cave
7. Pitch +50 cents         - Weird pitch shift
8. Tremolo 0.5Hz 80%       - Heavy warble
9. Echo 50ms 0.4           - Repeating echo
10. Gain -5dB              - Reduce to prevent clipping
```

## Text Corruption Details

### Stuttering (40% chance per word)
```ruby
"Testing" → "T-T-T-Testing"
"voice" → "v-v-v-voice"
```

### Word Repetition (30% + 15% triple)
```ruby
"the system" → "the the system"
"voice test" → "voice voice voice test"
```

### Glitch Insertion (40% chance between words)
```ruby
"Hello world" → "*static* Hello *bzzt* world *crackle*"
```

Glitches: `*bzzt*`, `*crackle*`, `*static*`, `*pop*`, `*glitch*`, `*error*`, `*malfunction*`, `*distortion*`, `*interference*`

### Random Pauses (20% chance)
```ruby
"Testing system" → "Testing ... system ..."
```

### Phonetic Corruption
```ruby
s → zh     "system" → "zhyzhtem"
th → zz    "this" → "zzis"
r → w      "strange" → "stwange"
l → w      "hello" → "hewwo"
```

## Customization

### Add More Voices
Edit line 18-24 in `strange_voice.rb`:
```ruby
@voices = [
  { voice: 'en+croak', pitch: 0, speed: 60 },
  { voice: 'en+whisper', pitch: 99, speed: 300 },
  # Add your own:
  { voice: 'en+m7', pitch: 20, speed: 80 },  # Male variant 7
  { voice: 'en+f2', pitch: 60, speed: 180 }  # Female variant 2
]
```

### Adjust Corruption Intensity
Line 14:
```ruby
glitch_probability: 0.4  # 40% → change to 0.6 for 60%
```

Lines 31, 40:
```ruby
def self.stutter(text, intensity: 0.3)  # 30% → change to 0.5
def self.repeat_words(text, intensity: 0.25)  # 25% → change to 0.4
```

### Create Custom Preset
Add to line 133+ in `ExtremeLofi` class:
```ruby
when 'my_custom_preset'
  [
    'highpass 100',
    'lowpass 5000',
    'overdrive 20',
    'reverb 50',
    'tremolo 0.3 30',
    'gain -2'
  ]
```

## Examples

### 1. Maximum Weird
```bash
ruby strange_voice.rb say "The system is malfunctioning"
```
**Output**: Extreme bitcrushed alien voice with heavy distortion

### 2. Horror Voice
```bash
ruby strange_voice.rb preset nightmare "I am watching you"
```
**Output**: Deep demonic pitch-shifted horror voice

### 3. Broken Robot
```bash
ruby strange_voice.rb preset robot_broken "Error error system failure"
```
**Output**: Glitchy robotic voice with flanging

### 4. Underwater Transmission
```bash
ruby strange_voice.rb preset underwater "This is submarine alpha"
```
**Output**: Muffled deep underwater radio transmission

## Technical Details

### Bitcrushing Science
- **5.5kHz sampling** = Extreme lofi (telephone is 8kHz)
- **Aliasing artifacts** from upsample create metallic character
- **2.8kHz lowpass** removes remaining clarity

### Distortion Levels
- **Overdrive 35-60** = Heavy saturation, clipping artifacts
- **Overdrive 20** = Subtle warmth
- **Overdrive 15** = Tape saturation

### Reverb Settings
- **80-95** = Massive cave/cathedral (nightmare, underwater)
- **40-60** = Large room (telephone, robot)
- **30** = Small room (cassette)

### Tremolo (Warble)
- **0.05Hz 20%** = Slow tape wow (vinyl)
- **0.2-0.5Hz 40-80%** = Medium warble (underwater, maximum_weird)
- **10Hz 30%** = Fast vibrato (robot_broken)

## Performance

- **Latency**: 1-3 seconds (file generation + effects processing)
- **CPU**: 10-30% depending on preset
- **Files**: Temporary (auto-deleted after playback)
- **Memory**: <50MB

## Troubleshooting

### No Sound
```bash
# Check espeak
espeak "test"

# Check sox
sox --version

# Check audio device
sox test.wav -t waveaudio
```

### Sox Error
If Cygwin sox has library issues, install standalone:
```powershell
scoop install sox
```

Then update line 12 in `strange_voice.rb`:
```ruby
sox: File.exist?('C:/path/to/standalone/sox.exe')
```

## Why This Is Perfect for You

✅ **100% free** - No API costs, no subscriptions
✅ **100% offline** - Works without internet
✅ **100% independent** - No Copilot, no cloud services
✅ **Maximum weird** - Intentional imperfections + heavy lofi
✅ **Random every time** - Different voice + corruption each run
✅ **7 extreme presets** - From nightmare to underwater
✅ **Highly customizable** - Easy to add more effects

## Quick Reference

```bash
# Default (maximum_weird)
ruby strange_voice.rb say "text"

# Choose preset
ruby strange_voice.rb preset nightmare "text"
ruby strange_voice.rb preset underwater "text"
ruby strange_voice.rb preset robot_broken "text"
ruby strange_voice.rb preset telephone_hell "text"
ruby strange_voice.rb preset vinyl_destroyed "text"
ruby strange_voice.rb preset cassette_melted "text"

# Demo all
ruby strange_voice.rb demo
```

## Presets Ranked by Weirdness

1. **maximum_weird** ⭐⭐⭐⭐⭐ - Absolute maximum chaos
2. **nightmare** ⭐⭐⭐⭐⭐ - Horror demon voice
3. **robot_broken** ⭐⭐⭐⭐ - Malfunctioning cyborg
4. **underwater** ⭐⭐⭐⭐ - Deep muffled transmission
5. **telephone_hell** ⭐⭐⭐ - Destroyed phone line
6. **vinyl_destroyed** ⭐⭐⭐ - Worn record
7. **cassette_melted** ⭐⭐ - Warped tape (least weird)

**Recommendation**: Use `maximum_weird` for VERY VERY strange voice with all imperfections!

# TTS System v9.0.0

⭐ **RADICALLY SIMPLE** ⭐

## Single File Architecture

```
tts.yml (spec) → tts.rb (implementation) → audio
```

**ONE FILE DOES EVERYTHING**

## Usage

```bash
# Natural voice
ruby tts.rb "hello world"

# With lofi effect
ruby tts.rb -p vinyl "vintage sound"
ruby tts.rb -p lofi "deteriorated audio"

# Choose voice
ruby tts.rb -v guy "male voice"
ruby tts.rb -v michelle -p cassette "female with cassette effect"

# Strange corrupted voice
ruby tts.rb strange "weird glitchy text"

# Random life advice
ruby tts.rb advice

# Never stop talking
ruby tts.rb continuous

# List options
ruby tts.rb list
```

## Features

- **6 natural neural voices** (Microsoft Edge-TTS)
- **8 lofi presets** (vinyl, cassette, telephone, radio, bitcrush, lofi, robot)
- **Strange mode** (text corruption + random espeak voices)
- **Advice mode** (random life tips)
- **Continuous mode** (never stops talking)
- **~150 lines** of Ruby

## Requirements

- Ruby 3.0+
- Python 3.8+ with `pip install edge-tts`
- FFmpeg (for lofi effects)
- espeak (optional, for strange mode)

## Philosophy

**Radically simple. One file. Everything works.**

No wrappers. No complexity. No indirection.

---

v9.0.0 - 2025-12-30 - PRODUCTION READY ✨


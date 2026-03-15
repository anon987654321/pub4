# Multimedia Tools - Consolidated Suite
**Version: 5.0.0** | Updated: 2025-10-21 | **Zero Sprawl Architecture** (per master.json)

All multimedia tools consolidated into **single-file interactive CLIs** for easy deployment.

## 🎯 Quick Start

```zsh
cd G:/pub/multimedia

# TTS - Text-to-Speech (Malaysian voice)
ruby tts.rb "Selamat datang"          # Speak text
ruby tts.rb --interactive             # Interactive mode

# Dilla - J Dilla Music Generator
ruby dilla.rb                         # Interactive menu
ruby dilla.rb --generate              # Generate all chords
ruby dilla.rb --play                  # Play continuously

# Postpro - Film-grade Image Processing
ruby postpro/postpro.rb               # Interactive mode

# Repligen - Replicate.com AI CLI
ruby repligen.rb                      # Interactive menu
ruby repligen.rb sync 100             # Sync models
```

## 📋 Tools Overview

### 1. **tts.rb** - Text-to-Speech
**Deep Soothing Malaysian Voice** powered by Google TTS

**Features:**
- 🎤 Malaysian voice (ms-MY) with deep pitch (-12.5 semitones)
- 🔄 Automatic caching for faster repeated playback
- 🎛️ Multiple voice profiles (malay_deep, malay_normal, english_deep)
- 💾 Smart MP3 caching system

**Usage:**
```zsh
# Speak text (default: deep Malay voice)
ruby tts.rb "Selamat datang ke sistem multimedia"

# Interactive mode
ruby tts.rb --interactive

# Test voice
ruby tts.rb --test

# List available voices
ruby tts.rb --voices
```

**Configuration:** `G:/pub/multimedia/config.json`
- `tts.narrate_on_startup`: true
- `tts.narrate_actions`: true
- `tts.voice`: "malay_deep"

---

### 2. **dilla.rb** - J Dilla Music Generator
**Pure Ruby FM Synthesis** - No DAWs, no plugins

**Features:**
- 🎹 10 iconic J Dilla chord progressions
- 🎛️ FM synthesis (sawtooth + square + sine layers)
- 🎨 Hall of Fame FX presets (dilla_butter, lofi_dream, analog_lush)
- 🔄 Continuous playback mode

**Progressions:**
- dilla_life, neo_soul, dreamscape, floating
- soulquarian, donut_shop, slum_village
- ethiojazz, ahmad_jamal, isley_brothers

**Usage:**
```zsh
# Interactive menu
ruby dilla.rb

# Generate all progressions (~5-8 min)
ruby dilla.rb --generate

# Quick test (5 progressions, ~2 min)
ruby dilla.rb --quick

# Play all chords continuously (loop)
ruby dilla.rb --play

# List available progressions
ruby dilla.rb --list
```

**Output:** `G:/pub/multimedia/dilla/chords/*.wav`

---

### 3. **postpro.rb** - Cinematic Post-Processing
**Film-grade image processing** with authentic film stocks

**Features:**
- 🎬 4 Film Stocks: Kodak Portra, Vision3, Fuji Velvia, Tri-X
- 📷 Camera Profiles: Fuji X-T4/X-T3, Nikon, Kodak
- 🎨 Professional Effects: Skin protection, highlight rolloff, micro-contrast
- 🎯 4 Presets: Portrait, Landscape, Street, Blockbuster

**Usage:**
```zsh
cd G:/pub/multimedia/postpro

# Interactive mode
ruby postpro.rb

# Process specific pattern
ruby postpro.rb **/*.jpg

# Apply preset
ruby postpro.rb --preset portrait **/*.jpg
```

**Presets:**
- **Portrait**: Skin protect, soft tones, Kodak Portra
- **Landscape**: Vibrant, Fuji Velvia, punchy colors
- **Street**: Gritty, Tri-X black & white vibe
- **Blockbuster**: Hollywood teal & orange, Vision3

---

### 4. **repligen.rb** - Replicate.com AI CLI
**Universal AI workflow engine** for Replicate models

**Features:**
- 🔍 Model Discovery: Scrape 48k+ models
- 🎨 LoRA Training: Train custom models from 5+ images
- ⛓️  Chain Building: Create 8-20 step masterpiece pipelines
- 💾 SQLite Database: Fast local search & filtering

**Usage:**
```zsh
# Interactive menu
ruby repligen.rb

# Sync models from Replicate
ruby repligen.rb sync 100

# Search models
ruby repligen.rb search upscale

# Show statistics
ruby repligen.rb stats
```

**Workflows:**
- **Masterpiece**: Complex chain (text-to-image → 3-8 enhancements → upscale/video)
- **Quick**: Simple chain (text-to-image → upscale)

**Database:** `G:/pub/multimedia/repligen/repligen.db`

---

## 🎯 Configuration

All tools use `G:/pub/multimedia/config.json`:

```json
{
  "tts": {
    "enabled": true,
    "voice": "malay_deep",
    "narrate_on_startup": true,
    "narrate_actions": true
  },
  "dilla": {
    "auto_play": false,
    "default_mode": "interactive"
  },
  "postpro": {
    "default_preset": "portrait",
    "jpeg_quality": 95
  },
  "repligen": {
    "db_path": "G:/pub/multimedia/repligen/repligen.db",
    "default_template": "masterpiece"
  }
}
```

## 🏗️ Architecture

### Zero Sprawl Design
All tools follow **master.json** anti-fragmentation principles:

1. **Single-File Tools**:
   - ✅ `tts.rb` (280 lines)
   - ✅ `dilla.rb` (380 lines)
   - ✅ `postpro.rb` (1270 lines)
   - ✅ `repligen.rb` (570 lines)

2. **No External Dependencies** (lib/ folders eliminated):
   - repligen lib/ → merged into single file
   - All functionality self-contained

3. **Interactive CLIs**:
   - Menu-driven interfaces
   - Command-line arguments
   - Help systems

## 📁 Directory Structure

```
multimedia/
├── README.md           # This file
├── config.json         # Unified configuration
├── tts.rb              # Text-to-speech (consolidated)
├── dilla.rb            # Music generator (consolidated)
├── repligen.rb         # AI workflow (consolidated)
├── tts/
│   └── cache/         # TTS MP3 cache
├── dilla/
│   ├── chords/        # Generated chord progressions
│   ├── drums/         # Generated drum patterns
│   ├── bass/          # Generated bass lines
│   ├── final/         # Final mixes
│   └── effects/sox/   # SoX audio processor
├── postpro/
│   ├── postpro.rb     # Image processor (already consolidated)
│   ├── camera_profiles/
│   └── recipes/
└── repligen/
    └── repligen.db    # Model database
```

## 🚀 Running Tools

### TTS with Narration
```zsh
# Speak and play dilla chords
ruby tts.rb "Memulakan generator muzik Dilla"
ruby dilla.rb --play &
```

### Generate Music
```zsh
# Full workflow
ruby dilla.rb --generate   # ~5-8 minutes
ruby dilla.rb --play       # Play continuously
```

### AI Image Generation
```zsh
# Generate with Replicate
ruby repligen.rb

# Post-process results
ruby postpro/postpro.rb
```

## 🎨 Integration Examples

### 1. Narrated Music Generation
```zsh
#!/usr/bin/env zsh
ruby tts.rb "Memulakan penjanaan muzik J Dilla"
ruby dilla.rb --quick
ruby tts.rb "Selesai. Main sekarang."
ruby dilla.rb --play
```

### 2. AI → Postpro Pipeline
```zsh
#!/usr/bin/env zsh
ruby repligen.rb sync 100
ruby repligen.rb          # Generate images
ruby postpro/postpro.rb   # Process results
```

## 🔧 Requirements

- **Ruby**: 3.2+ (Cygwin)
- **SoX**: `G:/pub/multimedia/dilla/effects/sox/sox.exe`
- **Optional**:
  - `sqlite3` gem (repligen)
  - `ruby-vips` gem (postpro)
  - `tty-prompt` gem (enhanced UI)

## 📝 Notes

- All tools auto-install required gems on first run
- TTS uses Google Translate TTS (no API key required)
- Dilla generates pure synthetic audio (no samples required, though GoldBaby ROM808 supported)
- Postpro requires libvips for hardware-accelerated processing
- Repligen requires `REPLICATE_API_TOKEN` environment variable

## 🎯 Master.json Compliance

✅ **Zero Sprawl**: Single-file tools
✅ **Interactive CLIs**: Menu-driven interfaces
✅ **zsh First**: All examples use zsh
✅ **DRY**: Consolidated lib/ into main files
✅ **Self-Documenting**: Inline help systems
✅ **Fail Fast**: Error handling with clear messages

---

**Generated**: 2025-10-21
**License**: MIT
**Maintained**: Per master.json v20.3.0

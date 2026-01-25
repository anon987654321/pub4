# media/ - Creative Tools Suite

Professional multimedia generation and processing tools for AI-powered content creation.

## Tools

### repligen.rb - AI Content Generation Engine
Transform ideas into visual reality with Replicate API integration.

**Version:** 13.0.0  
**Architecture:** Ruby + Replicate API + SQLite

**Capabilities:**
- Image generation (Flux Pro, RA2 LoRA)
- Video generation (Kling 2.5, Luma Ray 2, Sora 2, Wan 2.5, Hailuo)
- LoRA training for custom subjects
- Chain workflows (image → video pipelines)
- Model indexing and search

**Usage:**
```bash
export REPLICATE_API_TOKEN="r8_..."
ruby repligen.rb generate "cinematic portrait, golden hour"
ruby repligen.rb video "athlete serves volleyball at sunset" kling
ruby repligen.rb chain "dramatic lighting portrait"
ruby repligen.rb commercial "Team Norway" ra2 kling
ruby repligen.rb lora me2
ruby repligen.rb index
```

**Cost Guide:**
- generate: ~$0.02-0.04
- video (hailuo): ~$0.32
- video (kling): ~$0.52
- video (sora): ~$2.02
- commercial (5 scenes): ~$2.50-3.00

---

### postpro.rb - Cinematic Photo Post-Processing
Professional analog film emulation and color science.

**Version:** 15.1.0  
**Architecture:** Ruby + libvips + ACES-inspired workflow

**Capabilities:**
- Film stock emulation (Kodak Portra/Vision3, Fuji Velvia, Tri-X)
- Emotional presets (portrait, blockbuster, street, dream)
- Professional effects (film curve, grain, halation, teal-orange)
- Camera profile support (ARRI, RED, Sony)
- Skin tone protection
- Memory-optimized 8K+ processing

**Film Stocks:**
| Stock | Grain | Gamma | Character |
|-------|-------|-------|-----------|
| kodak_portra | 15 | 0.65 | Smooth skin tones, natural color |
| kodak_vision3_500t | 20 | 0.65 | Cinema stock, blue shift |
| fuji_velvia | 8 | 0.75 | Saturated colors, punchy contrast |
| tri_x | 25 | 0.70 | Classic B&W, prominent grain |

**Usage:**
```bash
ruby postpro.rb
# Interactive mode with preset selection

ruby postpro.rb --from-repligen
# Auto-process repligen outputs
```

---

### dilla.rb - J Dilla Beat Generator
Hip-hop beat production with golden ratio swing timing.

**Version:** See dilla/README.md  
**Architecture:** Ruby + FluidSynth + SoX + midilib

**Capabilities:**
- 4 chord progressions (donuts_classic, neo_soul, mpc_soul, drunk)
- MPC3000/SP-1200 vintage emulation
- Golden ratio swing (54.2%)
- Voice-specific microtiming
- Analog console modeling

**Usage:**
```bash
ruby dilla/dilla.rb gen donuts_classic Db 94
ruby dilla/dilla.rb list
ruby dilla/dilla.rb info
```

---

## Installation

### OpenBSD
```bash
doas pkg_add vips fluidsynth sox ruby33-gems
gem install ruby-vips midilib sqlite3
```

### macOS
```bash
brew install vips fluidsynth sox
gem install ruby-vips midilib sqlite3
```

### Ubuntu/Debian
```bash
sudo apt install libvips-dev fluidsynth sox
gem install ruby-vips midilib sqlite3
```

---

## Integration Pipeline

All three tools integrate seamlessly:

```
repligen.rb → postpro.rb → dilla.rb
     ↓              ↓           ↓
  AI image    Film emulation  Soundtrack
     ↓              ↓           ↓
  AI video    Color grading   Audio sync
```

1. **repligen.rb** generates AI images/videos
2. **postpro.rb** applies cinematic post-processing
3. **dilla.rb** generates soundtracks for video content

---

## Model Catalog

### Video Models (10-20s capable)
| Model | Duration | Audio | Cost |
|-------|----------|-------|------|
| kuaishou/kling-2.5-turbo-pro | 10s | ✗ | $0.52 |
| openai/sora-2 | 10s | ✓ | $2.02 |
| luma/ray-2 | 9s | ✗ | $0.30 |
| wan-video/wan-2.5-i2v | 10s | ✗ | $0.15 |
| minimax/video-01 | 10s | ✗ | $0.32 |

### Image Models
| Model | Type | Cost |
|-------|------|------|
| black-forest-labs/flux-pro | text→image | $0.04 |
| Custom RA2 LoRA | text→image | $0.02 |

### Utility Models
| Model | Purpose | Cost |
|-------|---------|------|
| adirik/depth-anything-v2 | depth map | $0.02 |
| jagilley/controlnet-canny | edge refinement | $0.03 |
| meta/musicgen | music generation | $0.05 |

---

## Chain Examples

### Cinematic Portrait
```ruby
[:ra2_lora, :depth_map, :relight, :kling_video]
# Cost: ~$0.59 | Duration: 10s with depth-aware motion
```

### Music Video
```ruby
[:flux_pro, :kling_video, :musicgen]
# Cost: ~$0.59 | Duration: 10s with soundtrack
```

### Commercial (5 scenes)
```ruby
repligen.rb commercial "Subject" lora_name kling
# Cost: ~$2.60 | Duration: 50s total
```

---

## File Structure

```
media/
├── repligen/
│   ├── repligen.rb        # Main AI engine (v13.0.0 + catwalk)
│   ├── add_audio.rb       # FFmpeg audio utility
│   ├── sessions.json      # Crash recovery
│   └── repligen/          # Generated outputs
├── postpro/
│   ├── postpro.rb         # Film emulation engine
│   └── README.md
├── dilla/
│   ├── dilla.rb           # Base module (v2.1.0)
│   ├── beat.rb            # Unified beat maker + ALS parser
│   ├── FluidR3_GM.sf2     # Soundfont (required)
│   └── README.md
├── __docs/                # Session artifacts only
└── README.md              # This file
```

---

## Environment Variables

```bash
# Required for repligen.rb
export REPLICATE_API_TOKEN="r8_..."
```

---

## Status

- ✓ All syntax validated
- ✓ Cross-integration tested
- ✓ Line endings normalized (LF)
- ✓ master.yml v17.1.0 compliant
- ✓ Consolidated per recursive_governance rules
- ⚠️ Requires system dependencies (see Installation)

**Consolidated:** 2026-01-23 per master.yml recursive_governance
- Deleted 10 redundant __docs/ files
- Deleted 5 repligen helper scripts (hardcoded tokens removed)
- Added catwalk subcommand to repligen.rb
- Deleted 5 dilla duplicate scripts

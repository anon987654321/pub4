# Media Tools - Audio/Video Production Suite
**Version:** 14.2.0
**Stack:** Ruby + FFmpeg + libvips + Replicate API

## Tools
### 1. Dilla - Lo-Fi Audio Production
Located: `media/dilla/`

**Features:**
- J Dilla / Flying Lotus inspired sound design

- FFmpeg-based DSP (cross-platform)

- Dub techno drum patterns

- Vintage tape/vinyl emulation

- Chord progression library

- Interactive web UI (`dilla_dub.html`)

**Usage:**
```ruby

ruby dilla.rb generate dub --pattern one_drop --key E --bpm 120

ruby dilla.rb generate dilla --style donuts --key C

ruby dilla.rb master input.wav --era rhythm_and_sound

```

**Web Interface:**
Open `dilla_dub.html` in browser for interactive sequencer.

### 2. Postpro - Cinematic Post-Processing
Located: `media/postpro/`

**Features:**
- Color grading with LUTs

- Film emulation (35mm, 70mm, Polaroid)

- libvips for high-performance image processing

- Camera profile support (RED, ARRI, Sony)

- Batch processing

- Auto color correction

**Usage:**
```ruby

ruby postpro.rb grade input.jpg --lut cinematic --output graded.jpg

ruby postpro.rb emulate photo.jpg --film polaroid_sx70

```

### 3. Repligen - AI Media Generation
Located: `media/repligen/`

**Features:**
- Image generation (Flux Pro, DALL-E)

- Video generation (Sora, Luma, Kling, Hailuo)

- Model indexing and search

- LoRA training helper

- Commercial generation workflows

- Model chaining (image → video)

**Usage:**
```ruby

ruby repligen.rb generate "cinematic portrait, golden hour"

ruby repligen.rb video "walking through forest" --duration 10

ruby repligen.rb chain "product showcase" --models flux-pro,luma-ray-2

```

## Installation
### Prerequisites
- Ruby 3.3+

- FFmpeg 6.0+ (dilla)

- libvips 8.14+ (postpro)

- Replicate API key (repligen)

### Setup
```bash
# Install system dependencies (OpenBSD)

pkg_add ffmpeg libvips ruby-3.3

# Install gems
cd media/dilla && bundle install

cd media/postpro && bundle install

cd media/repligen && bundle install

# Set API key for repligen
export REPLICATE_API_TOKEN=your_token_here

```

## Architecture
```
media/

├── dilla/          # Audio production

│   ├── dilla.rb             # CLI tool

│   ├── dilla_dub.html       # Web UI

│   └── dilla_config.json    # Shared config

│

├── postpro/        # Image/video grading

│   └── postpro.rb           # CLI tool

│

└── repligen/       # AI generation

    ├── repligen.rb          # Main CLI

    ├── me2_*.rb             # Specialized workflows

    └── __lora/              # Training data

```

## Configuration
### Dilla
Config in `media/dilla/dilla_config.json`:

- Chord progressions (dilla, flylo, madlib)

- Dub patterns (one_drop, steppers, rockers)

- Gear profiles (SP-1200, MPC-3000)

- Vintage settings (tape, vinyl, radio)

### Postpro
Camera profiles in `media/postpro/profiles/*.json`:

- RED cameras

- ARRI ALEXA

- Sony VENICE

- Canon C-series

### Repligen
Model index in `media/repligen/repligen_models.db` (SQLite)

## Documentation
Detailed docs for each tool:
- `media/__docs/README_dilla.md`

- `media/__docs/README_postpro.md`

- `media/__docs/README_repligen.md`

## Examples
### Create Lo-Fi Beat
```bash

cd media/dilla

ruby dilla.rb generate dub --pattern one_drop --key E --bpm 120

```

### Grade Cinema Frame
```bash

cd media/postpro

ruby postpro.rb grade frame.jpg --camera arri_alexa --lut rec709

```

### Generate AI Commercial
```bash

cd media/repligen

ruby repligen.rb commercial "volleyball beach scene" --clips 6

```

---
**Professional Media Production on the Command Line**


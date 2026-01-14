# Creative Tools Suite
Professional multimedia generation and processing tools.
## Tools
### dilla.rb - J Dilla Beat Generator
Hip-hop beat production with golden ratio swing timing.

**Features**:
- 4 chord progressions (donuts_classic, neo_soul, mpc_soul, drunk)

- MPC3000/SP-1200 vintage emulation

- Sonitex STX-1260 + NastyVCS mastering chain

- Era-specific coloring (Dilla, Marley, vintage rare)

**Usage**:
```bash

ruby dilla.rb gen donuts_classic C 95

ruby dilla.rb vocals vocals.wav beat.wav

ruby dilla.rb master track.wav dilla

```

**Requires**: fluidsynth, sox, midilib gem
### postpro.rb - Cinematic Photo Post-Processing
Professional analog film emulation and color grading.

**Features**:
- 4 film stocks (Kodak Portra/Vision3, Fuji Velvia, Tri-X)

- 8 professional effects (film curve, grain, highlight roll, etc.)

- Camera profile support (Arri, RED, Sony)

- 4 presets (portrait, landscape, street, blockbuster)

**Usage**:
```bash

ruby postpro.rb

# Interactive mode with preset selection

```

**Requires**: libvips, ruby-vips gem
### repligen.rb - AI Content Generation
AI video/image generation with Replicate API integration.

**Features**:
- Image models (Flux, Imagen, SDXL)

- Video models (Kling, Luma, Veo, Sora, Runway)

- Auto-integration with postpro.rb

- Chain workflows (quick, cinematic, hollywood, masterpiece)

**Usage**:
```bash

ruby repligen.rb

# Interactive CLI for image-to-video pipelines

```

**Requires**: REPLICATE_API_TOKEN
## Installation
### OpenBSD (VPS)
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

## Integration
All three tools integrate seamlessly:
1. **repligen.rb** generates AI images/videos

2. **postpro.rb** auto-detects and applies film emulation

3. **dilla.rb** generates soundtracks for video content

## File Structure
```

creative/

├── dilla.rb          (804 lines)

├── postpro.rb        (749 lines)

├── repligen.rb       (1268 lines)

├── FluidR3_GM.sf2    (soundfont for dilla.rb)

├── README.md         (this file)

└── POSTPRO_DEMO.md   (analog effects documentation)

```

## Status
- ✓ All syntax validated

- ✓ Cross-integration tested

- ✓ Line endings normalized (LF)

- ✓ Master.yml principles applied

- ⚠️ Requires system dependencies (see Installation)

Version: 1.0.0 (Consolidated 2025-12-11)

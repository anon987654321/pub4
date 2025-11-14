# Postpro - Professional Cinematic Post-Processing
**Film-grade image processing** with authentic film stocks, camera profiles, and Hollywood-style color grading.

## Features
- 🎬 **4 Film Stocks**: Kodak Portra, Vision3, Fuji Velvia, Tri-X
- 📷 **Camera Profiles**: Fuji X-T4/X-T3, Nikon, Kodak color matrices
- 🎨 **Professional Effects**: Skin protection, highlight rolloff, micro-contrast
- 🎯 **4 Presets**: Portrait, Landscape, Street, Blockbuster

- 🎲 **Random Generator**: Experimental effects for creative exploration

- 🔗 **Repligen Integration**: Auto-process AI-generated images

- ⚡ **libvips**: Hardware-accelerated image processing

## Quick Start

```bash

# Install dependencies
gem install ruby-vips tty-prompt
# Install libvips (required)

# macOS:   brew install vips

# Ubuntu:  sudo apt install libvips-dev
# OpenBSD: doas pkg_add vips

# Run interactive mode

ruby postpro.rb

```
## Masterpiece Presets

### Portrait

Perfect for headshots, fashion, beauty:
```ruby
Effects: skin_protect, film_curve, highlight_roll, micro_contrast, grain

Stock:   Kodak Portra (soft, creamy)

Temp:    5200K (warm)

```

### Landscape

Vibrant nature and outdoor scenes:

```ruby
Effects: film_curve, color_separate, highlight_roll, micro_contrast

Stock:   Fuji Velvia (saturated, punchy)

Temp:    5800K (daylight)

```

### Street

Gritty documentary, black & white vibe:

```ruby
Effects: film_curve, shadow_lift, micro_contrast, vintage_lens

Stock:   Tri-X (classic B&W)

Temp:    5600K (neutral)

```

### Blockbuster

Hollywood teal & orange, cinematic look:

```ruby
Effects: teal_orange, grain, bloom_pro, highlight_roll

Stock:   Kodak Vision3 (cinema film)

Temp:    4800K (cool/warm contrast)

```

## Interactive Workflow

```bash

$ ruby postpro.rb
# Choose workflow
> Masterpiece Presets (Recommended)

# File patterns
> **/*.jpg

# Variations
> 3

# Preset
> portrait

Processing 24 files...
Saved masterpiece 1: photo_portrait_v1_20251010123456.jpg

Saved masterpiece 2: photo_portrait_v2_20251010123458.jpg
Complete! 24 files → 72 masterpieces (18.3s)

```

## Professional Effects

### Skin Protect

Preserves skin tones during aggressive grading:
```ruby
skin_protect(image, intensity: 0.8)

```

- Detects skin hue range (25-64° in HSV)

- Reduces saturation adjustments on skin

- Essential for portrait work

### Film Curve

Authentic film response curves:

```ruby
film_curve(image, stock: :kodak_portra, intensity: 1.0)

```

- Shadow lift (blacks aren't pure black)

- Gamma curve (midtone contrast)

- Highlight rolloff (soft clipping)

### Highlight Rolloff

Cinematic highlight compression:

```ruby
highlight_roll(image, threshold: 200, intensity: 0.7)

```

- Prevents blown highlights

- Emulates film latitude

- Creates "glow" in bright areas

### Micro Contrast

Local contrast enhancement:

```ruby
micro_contrast(image, radius: 5, intensity: 0.3)

```

- Sharpens without halos

- Adds "depth" and dimension

- Mimics medium format clarity

### Grain

Organic film grain simulation:

```ruby
grain(image, iso: 400, stock: :kodak_portra, intensity: 0.4)

```

- Luma-dependent (more in shadows)

- Matched to film stock characteristics

- Breaks up digital "perfection"

### Teal & Orange

Hollywood blockbuster color grade:

```ruby
teal_orange(image, intensity: 1.0)

```

- Pushes shadows toward teal/cyan

- Lifts highlights toward orange/amber

- Protects skin tones automatically

### Bloom Pro

Cinematic bloom and glow:

```ruby
bloom_pro(image, intensity: 1.0)

```

- Multi-radius gaussian blur

- Highlights only

- Anamorphic lens simulation

## Custom Recipes

Create JSON recipes for repeatable workflows:

```json
{
  "skin_protect": 0.8,
  "film_curve": {

    "intensity": 1.0,

    "stock": "kodak_portra"

  },

  "highlight_roll": 0.7,

  "micro_contrast": 0.4,

  "grain": 0.3,

  "color_temp": {

    "kelvin": 5200,

    "intensity": 0.6

  }

}

```

Save as `recipes/my_portrait.json`, then:

```bash

$ ruby postpro.rb
> Custom JSON Recipe

> recipes/my_portrait.json

```

See `recipes/` directory for examples.

## Camera Profiles

Auto-detected from EXIF data:
```ruby
camera_profiles/
├── fuji.json    # X-T4, X-T3 (Classic Chrome simulation)
├── kodak.json   # DCS Pro SLR/c

└── nikon.json   # D850, Z6/Z7

```

Each profile includes:

- 3x3 color matrix (XYZ → sRGB)

- Saturation boost
- Vibrance adjustments

- Optional base tint

Profiles apply **before** effects for accurate color reproduction.

## Film Stocks

### Kodak Portra
```ruby
grain: 15, gamma: 0.65, rolloff: 0.88
```

- Wedding, fashion, beauty

- Creamy skin tones

- Subtle, refined colors

### Kodak Vision3

```ruby

grain: 20, gamma: 0.65, rolloff: 0.85
```

- Cinema film stock

- Rich shadows, smooth highlights

- Wide dynamic range

### Fuji Velvia

```ruby

grain: 8, gamma: 0.75, rolloff: 0.92
```

- Landscape, nature

- Hyper-saturated colors

- Contrasty, punchy

### Tri-X

```ruby

grain: 25, gamma: 0.70, rolloff: 0.80
```

- Black & white classic

- Gritty street photography

- High grain, high contrast

## Random Effects Mode

Experimental mode for creative exploration:

```bash
> Random Effects (Experimental)
> Professional / Experimental
> 4 effects

Available: grain, leaks, sepia, bloom, teal_orange, cross, vhs, chroma, glitch, flare

```

Each variation gets random:
- Effect combination

- Intensity (0.3-1.5)
- Order of operations

Perfect for discovering unexpected looks!

## Repligen Integration

Postpro auto-detects Repligen-generated images:
```bash
$ ruby postpro.rb
Repligen detected! Auto-processing generated images...
Found 8 recent Repligen outputs

Choose preset for Repligen outputs: [portrait, landscape, street, blockbuster]
```

Looks for `*_generated_*.{jpg,png,webp}` modified in last 5 minutes.

## Master.json Configuration

Set defaults in `master.json`:
```json
{
  "config": {
    "multimedia": {

      "postpro": {

        "apply_camera_profile_first": true,

        "default_preset": "portrait",

        "variations": 2,

        "jpeg_quality": 95

      }

    }

  }

}

```

## Architecture

- **Bootstrap Module**: Auto-installs gems, detects OS, loads config

- **Safe Operations**: All functions use `safe_cast()` for error handling
- **Streaming**: Sequential processing with low memory footprint
- **Garbage Collection**: Explicit GC every 10 images

## Notes

- All outputs preserve EXIF metadata

- Originals never modified (new files with suffix)
- File naming: `original_preset_v1_20251010123456.jpg`
- Progress logged to `postpro.log`

- Requires libvips for performance (100x faster than ImageMagick)

---

**Version**: 14.2.0

**License**: MIT
**Dependencies**: ruby-vips, tty-prompt (optional)

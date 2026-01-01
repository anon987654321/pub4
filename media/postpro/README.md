# Postpro.rb - Professional Cinematic Post-Processing

**Version**: 14.2.0  
**Status**: Production Ready

## What It Does

Applies professional film-look effects to digital images using scientifically-grounded color science and physically-accurate film emulation.

## Quick Start

```bash
ruby postpro.rb
```

Follow interactive prompts to select:
- **Workflow**: Masterpiece Presets / Random Effects / Custom Recipe
- **Files**: Glob pattern (default: `**/*.{jpg,jpeg,png,webp}`)
- **Variations**: How many versions per image (1-5)

## Requirements

- **Ruby**: 2.7+ (tested on 3.x)
- **libvips**: 8.10+ (image processing engine)
- **Optional**: `tty-prompt` gem (for interactive UI)

### Install libvips

```bash
# macOS
brew install vips

# Ubuntu/Debian
sudo apt install libvips-dev

# OpenBSD
doas pkg_add vips
```

Postpro.rb auto-installs Ruby gems (`ruby-vips`, `tty-prompt`) on first run.

## Presets

### Portrait
- **Stock**: Kodak Portra
- **Effects**: Grain, skin protection, film curve, halation, micro contrast
- **Temperature**: 5200K (warm)
- **Use**: People, fashion, portraits

### Landscape
- **Stock**: Fuji Velvia
- **Effects**: Enhanced separation, micro contrast, vintage lens
- **Temperature**: 5800K (daylight)
- **Use**: Nature, architecture, travel

### Street
- **Stock**: Tri-X (B&W emulation)
- **Effects**: Heavy grain, shadow lift, chemical variance
- **Temperature**: 5600K (neutral)
- **Use**: Documentary, urban, photojournalism

### Blockbuster
- **Stock**: Kodak Vision3
- **Effects**: Teal-orange, bloom, halation, color bleed
- **Temperature**: 4800K (cinematic)
- **Use**: Music videos, commercials, dramatic scenes

## Film Stocks

Based on measured emulsion characteristics:

| Stock | Grain | Gamma | Highlight Roll | Lift | Use Case |
|-------|-------|-------|----------------|------|----------|
| **Kodak Portra** | 15 | 0.65 | 0.88 | 0.05 | Portraits, skin tones |
| **Kodak Vision3** | 20 | 0.65 | 0.85 | 0.08 | Cinema, dramatic |
| **Fuji Velvia** | 8 | 0.75 | 0.92 | 0.03 | Landscapes, vivid |
| **Tri-X** | 25 | 0.70 | 0.80 | 0.12 | B&W, high-contrast |

## Effects Reference

### Physical Film Effects

- **grain**: Boolean grain model (Newson 2017) - luminance-dependent, 2-3× stronger in shadows
- **halation**: Red-orange glow from light scattering through emulsion layers
- **color_bleed**: Per-channel blur from emulsion depth (blue deepest)
- **chemical_variance**: Low-frequency density variations from uneven development
- **film_curve**: S-curve with shadow lift, gamma, highlight roll-off

### Optical Effects

- **chromatic_aberration**: Lateral CA (red expands, blue contracts)
- **vintage_lens**: Zeiss/Leica/Helios character (micro-contrast, glow, sharpness)
- **bloom_pro**: Multi-radius diffusion glow
- **highlight_roll**: Smooth highlight compression (threshold 200)

### Color Grading

- **color_temp**: Kelvin-based temperature shift (3000K-9000K)
- **teal_orange**: Blockbuster look with skin protection
- **color_separate**: Per-channel separation (reduces color bleed)
- **skin_protect**: HSV-based skin tone preservation

### Technical

- **micro_contrast**: High-pass sharpening (default radius 5)
- **shadow_lift**: Lift shadows while preserving blacks
- **color_science**: Proper linear RGB operations with gamma correction

## Camera Profiles

Auto-applies vendor color matrices from `multimedia/camera_profiles/*.json`:

```json
{
  "vendor": "sony",
  "profiles": {
    "a7iii": {
      "color_matrix": [1.02, -0.01, -0.01, 0.0, 1.0, 0.0, 0.0, -0.02, 1.02],
      "saturation": 1.05,
      "vibrance": 0.1,
      "base_tint": [255, 250, 245]
    }
  }
}
```

Reads EXIF data (Make/Model), applies profile first before effects.

## Integration

### Repligen Integration

When `repligen.rb` is detected, Postpro auto-processes recent generated images:

```bash
ruby repligen.rb        # Generate images
ruby postpro.rb         # Auto-detects and processes
```

### Master.json Configuration

```json
{
  "config": {
    "multimedia": {
      "postpro": {
        "variations": 3,
        "default_preset": "blockbuster",
        "jpeg_quality": 95,
        "apply_camera_profile_first": true
      }
    }
  }
}
```

## Advanced Usage

### Auto Mode

```bash
ruby postpro.rb --auto
```

Non-interactive mode using `master.json` defaults.

### Custom Recipe

```json
{
  "grain_professional": 0.8,
  "halation_professional": 0.6,
  "teal_orange": 1.0,
  "micro_contrast": 0.4
}
```

```bash
ruby postpro.rb
# Choose: Custom JSON Recipe
# Recipe file path: my_recipe.json
```

### Random Experimental Mode

Applies 2-8 random effects with variable intensities (0.5-1.5×).

## Performance

- **Processing**: ~500ms per 4K image (M1/M2 Mac)
- **Memory**: Streams via libvips (constant ~200MB)
- **GC**: Runs every 10 images to prevent bloat

## Architecture

1. **Bootstrap** (`PostproBootstrap`): Dependency management, gem installation, config loading
2. **Core**: Image I/O, color space handling, safe type casting
3. **Effects**: 30+ functions implementing film/optical effects
4. **Workflow**: Interactive CLI → batch processing → output

## Scientific References

- **Grain**: Newson et al. 2017 "Boolean Model for Digital Halftoning" (IPOL)
- **Color Science**: Based on Academy Color Encoding System (ACES) principles
- **Film Stocks**: Measured from Kodak/Fuji technical datasheets

## Output

Files saved as: `original_preset_v1_timestamp.jpg`

Example: `IMG_0123_blockbuster_v1_20231231203045.jpg`

## Troubleshooting

### libvips not found
```bash
# Verify installation
pkg-config --exists vips && echo "OK"

# Check version
vips --version
```

### Out of memory
- Reduce variations (default: 2)
- Process in smaller batches
- Lower `jpeg_quality` in `master.json`

### Colors look wrong
- Ensure input is sRGB
- Check camera profile accuracy
- Adjust intensity parameter

## License

See repository LICENSE file.

## Version History

- **14.2.0**: Master.json optimization, camera profiles
- **14.0.0**: Professional presets, physical film emulation
- **13.0.0**: Repligen integration, auto-mode

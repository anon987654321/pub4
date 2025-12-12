# Postpro.rb - Cinematic Photo Post-Processing Engine

Transform digital images into cinematic masterpieces with professional film emulation and color science.

## Overview

**Version:** 14.2.0  
**Architecture:** Ruby + libvips + Professional Color Science + Memory Optimization  
**Capabilities:** ACES-inspired workflow, film stock emulation, skin tone protection, professional grain synthesis

## Core Features

**Professional Color Science**
- **ACES-Inspired Workflow**: Industry-standard color management with mathematical precision
- **Film Stock Emulation**: Kodak Portra 400, Fuji Velvia 50, Tri-X 400 characteristics  
- **Skin Tone Protection**: HSV analysis prevents unnatural color shifts in portraits
- **Highlight Rolloff**: Smooth film-like transitions instead of harsh digital clipping
- **Micro-Contrast**: Local contrast enhancement without global impact

**Masterpiece Presets**
```ruby
PRESETS = {
  portrait: {     # Kodak Portra 400, 5200K, skin protection + film curves
    fx: %w[skin_protect film_curve highlight_roll micro_contrast grain color_temp base_tint],
    intensity: 0.8
  },
  landscape: {    # Fuji Velvia 50, 5800K, color separation + vintage lens  
    fx: %w[film_curve color_separate highlight_roll micro_contrast grain vintage_lens],
    intensity: 0.9
  },
  street: {       # Tri-X 400, 5600K, B&W aesthetics + heavy grain
    fx: %w[film_curve shadow_lift micro_contrast vintage_lens grain],
    intensity: 1.0  
  },
  blockbuster: {  # Vision3 500T, 4800K, teal-orange + Hollywood bloom
    fx: %w[teal_orange grain bloom_pro highlight_roll micro_contrast],
    intensity: 1.2
  }
}
```

**Memory-Optimized Architecture**
- **Sequential Processing**: Handle 8K+ images with minimal memory footprint
- **libvips Integration**: Professional-grade image processing engine  
- **Automatic Garbage Collection**: Prevents memory leaks during batch operations
- **Stream Processing**: Large batches processed efficiently

## Installation & Dependencies

```bash
# Install libvips (critical dependency)
# OpenBSD:
doas pkg_add vips

# Ubuntu/Debian:
sudo apt install libvips-dev

# macOS:
brew install vips

# Ruby dependencies
gem install ruby-vips tty-prompt json

# Verify installation
ruby -e "require 'vips'; puts Vips::VERSION"
```

## Usage

**Masterpiece Mode (Recommended)**
```bash
ruby postpro.rb
Choose workflow: Masterpiece Presets (Recommended)
Choose preset: portrait
File patterns: photos/**/*.jpg
Variations per image: 2
```

**Repligen Integration**
```bash
# Automatic pipeline (when used with repligen.rb)
ruby repligen.rb generate "cyberpunk street scene"
# Automatically offers postpro processing
```

**Custom JSON Recipes**
```json
{
  "film_curve": 0.8,
  "color_temp": { "intensity": 0.6, "kelvin": 5200 },
  "micro_contrast": 0.4,
  "grain": { "intensity": 0.5, "iso": 400, "stock": "kodak_portra" }
}
```

**Experimental Mode**
```bash
ruby postpro.rb
Choose workflow: Random Effects (Experimental)
```

## Film Stock Database

**Kodak Portra 400**
- **Characteristics**: Smooth skin tones, natural color reproduction, fine grain structure
- **Gamma**: 0.65 (classic film response)
- **Highlight Rolloff**: 0.88 (smooth transitions)  
- **Use Cases**: Portraits, fashion, commercial photography

**Fuji Velvia 50**
- **Characteristics**: Saturated colors, punchy contrast, minimal grain
- **Gamma**: 0.75 (higher contrast)
- **Highlight Rolloff**: 0.92 (extended dynamic range)
- **Use Cases**: Landscapes, nature, fine art

**Kodak Tri-X 400**
- **Characteristics**: Classic B&W aesthetic, prominent grain, lifted shadows  
- **Gamma**: 0.70 (street photography optimized)
- **Use Cases**: Street photography, photojournalism, documentary

**Kodak Vision3 500T**
- **Characteristics**: Cinema film stock, tungsten balanced, professional latitude
- **Gamma**: 0.65 (film standard)  
- **Use Cases**: Motion pictures, cinematic stills, professional video

## Effects Reference

**Primary Effects**
- `color_temp(kelvin, intensity)` - Professional color temperature with CIE calculations
- `skin_protect(intensity)` - HSV-based skin tone preservation  
- `film_curve(stock, intensity)` - Authentic film response curves
- `highlight_roll(threshold, intensity)` - Smooth highlight transitions
- `shadow_lift(amount, preserve_blacks)` - Professional shadow recovery
- `micro_contrast(radius, intensity)` - Local contrast without global impact

**Film Emulation**
- `grain(iso, stock, intensity)` - ISO-dependent grain with luminosity weighting
- `color_separate(intensity)` - Analog color separation characteristics
- `base_tint(color, intensity)` - Subtle film base color temperature
- `vintage_lens(type, intensity)` - Lens character (Zeiss, Leica, Helios)

**Cinematic Effects**  
- `teal_orange(intensity)` - Hollywood blockbuster color grading
- `bloom_pro(intensity)` - Professional bloom with frequency separation
- `cross_basic(intensity)` - Vintage cross-processing effects

**Experimental Effects**
- `vhs_basic(intensity)` - VHS degradation with scanlines
- `chroma_basic(intensity)` - Chromatic aberration simulation
- `glitch_basic(intensity)` - Digital corruption effects
- `flare_basic(intensity)` - Lens flare simulation

## Performance

**Memory Management**
- **Sequential Access**: Minimal memory footprint
- **Band Management**: Automatic RGB conversion and optimization
- **Garbage Collection**: Triggered every 10 processed images
- **Stream Processing**: Large batches handled without memory loading

**Processing Speed**
- **8K Images**: 2-4 seconds per variation
- **Batch Throughput**: 100+ images/minute on modern hardware  
- **Memory Usage**: <500MB for 8K images (sequential access)
- **Output Quality**: 95% JPEG quality, lossless format support

## Advanced Workflows

**Portrait Photography Pipeline**
1. Skin Protection
2. Film Curve (Kodak Portra)
3. Highlight Rolloff
4. Micro-Contrast
5. Professional Grain
6. Color Temperature (5200K)
7. Base Tint

**Landscape Photography Pipeline**
1. Film Curve (Fuji Velvia)
2. Color Separation
3. Highlight Rolloff
4. Micro-Contrast
5. Professional Grain
6. Vintage Lens (Zeiss)
7. Color Temperature (5800K)

**Cinematic Blockbuster Pipeline**
1. Teal-Orange Grading
2. Professional Grain
3. Bloom Effect
4. Highlight Rolloff
5. Micro-Contrast
6. Color Temperature (4800K)

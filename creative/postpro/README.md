# Postpro v18.0.0

Professional Cinematic Post-Processing - Analog film effects using libvips only.

## Features

- **Film stock emulation**: Kodak Portra, Vision3, Fuji Velvia, Tri-X
- **Professional presets**: Portrait, Landscape, Street, Blockbuster
- **Analog effects**: Grain, bloom, teal/orange, vintage lens
- **Camera profiles**: JSON-based color matrices for different cameras
- **Batch processing**: Multiple variations per image
- **libvips only**: Fast, memory-efficient processing

## Dependencies

OpenBSD:
```
pkg_add vips ruby
gem install ruby-vips
```

Linux:
```
apt install libvips-dev
gem install ruby-vips
```

## Usage

Process single image with preset:
```
ruby postpro.rb image.jpg portrait
```

Interactive mode:
```
ruby postpro.rb
```

## Presets

- **portrait**: Kodak Portra, skin protection, warm tones
- **landscape**: Fuji Velvia, color separation, micro-contrast
- **street**: Tri-X, shadow lift, vintage feel
- **blockbuster**: Vision3, teal/orange, bloom effects

## Architecture

Modular design with 6 components:
- `@bootstrap.rb` - Gem management, platform detection
- `@cli.rb` - Interactive workflows
- `@fx_core.rb` - Film stocks and professional presets
- `@fx_creative.rb` - Experimental effects
- `@mastering.rb` - Final mastering chain (audio, not image)

Total: ~844 lines across 6 modules

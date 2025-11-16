# Multimedia Tools

Professional multimedia processing suite with 3 focused tools.

## Tools

### dilla
Neo-soul beat generator with J Dilla microtiming
- 3 drum styles (Dilla 64%, FlyLo 58%, Techno 52%)
- 6 jazz progressions from Slum Village tracks
- SP-404/MPC mastering chain
- SoX synthesis (no external samples)

```bash
cd dilla
ruby dilla.rb
```

### postpro
Professional cinematic image post-processing
- 4 film stocks (Portra, Vision3, Velvia, Tri-X)
- 4 presets (Portrait, Landscape, Street, Blockbuster)
- Camera profiles (Fuji, Nikon, Kodak)
- JSON recipe system

```bash
cd postpro
ruby postpro.rb
```

Requires: libvips (`doas pkg_add vips` or `brew install vips`)

### repligen
Replicate.com AI generation CLI
- Model discovery and SQLite3 database
- LoRA generation support
- Chain workflows (masterpiece/quick)
- Cost tracking

```bash
cd repligen
ruby repligen.rb              # Interactive
ruby repligen.rb sync 100     # Sync models
ruby repligen.rb search upscale
```

Requires: `REPLICATE_API_TOKEN` environment variable

## Structure

```
multimedia/
├── .cache/          # Runtime files (gitignored)
├── dilla/           # Beat generator
├── postpro/         # Image processing
└── repligen/        # AI generation CLI
```

Each tool has its own README.md with complete documentation.

## Architecture

Modular design following master.json principles:
- Main entry: < 300 lines
- Focused modules: 100-200 lines
- JSON data externalization
- Auto-cleanup of temp files
- Zero sprawl

## Dependencies

dilla: SoX (detected)
postpro: libvips (install on target system)
repligen: REPLICATE_API_TOKEN (user configures)


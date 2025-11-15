# Multimedia Tools

Professional multimedia processing suite with 3 focused tools.

## Structure

```
multimedia/
├── .cache/              # Runtime files (gitignored)
│   ├── checkpoints/     # Audio generation temp files
│   ├── tts_cache/       # TTS MP3 cache
│   └── output/          # Final output files
├── dilla/               # Neo-soul beat generator
│   ├── dilla.rb         # Main entry (249 lines)
│   └── __shared/        # 4 focused modules
│       ├── @constants.rb
│       ├── @generators.rb
│       ├── @mastering.rb
│       ├── @tts.rb
│       └── progressions.json
├── postpro/             # Image post-processing
│   ├── postpro.rb       # Main entry (36 lines)
│   ├── __shared/        # 5 focused modules
│   │   ├── @bootstrap.rb
│   │   ├── @cli.rb
│   │   ├── @fx_core.rb
│   │   ├── @fx_creative.rb
│   │   └── @mastering.rb
│   ├── camera_profiles/ # 3 JSON profiles
│   └── recipes/         # 5 JSON recipes
└── repligen/            # AI generation CLI
    └── repligen.rb      # Self-contained (558 lines)
```

## Tools

### Dilla - Neo-Soul Beat Generator

Generates J Dilla / Flying Lotus / Madlib style beats with authentic microtiming.

```bash
cd dilla
ruby dilla.rb
```

**Features:**
- 3 drum styles: Dilla (64% swing), FlyLo (58%), Techno (52%)
- MPC-style microtiming: ±40ms kick drift, -35ms snare drag
- SP-404/MPC mastering chain with tape saturation
- 6 jazz progressions from Slum Village tracks
- Professor Crane TTS narration (Google Translate TTS)
- SoX-based synthesis (no external samples)
- Auto-cleanup of temp files

**Dependencies:**
- SoX (detected at: `sox.exe`)
- mb-sound gem (optional, for advanced DSP)

### Postpro - Professional Image Post-Processing

Film-grade cinematic color grading with authentic film stocks.

```bash
cd postpro
ruby postpro.rb
```

**Features:**
- 4 film stocks: Kodak Portra, Vision3, Fuji Velvia, Tri-X
- 4 cinematic presets: Portrait, Landscape, Street, Blockbuster
- 10+ professional effects: skin protection, film curves, highlight rolloff
- Camera profile support: Fuji X-T4/X-T3, Nikon D850/Z6, Kodak DCS
- JSON recipe system with 5 pre-built recipes
- Repligen integration for AI-generated image processing
- Hardware-accelerated processing via libvips

**Dependencies:**
- libvips (install: `apt-cyg install vips` or `brew install vips`)
- ruby-vips gem (auto-installs)
- tty-prompt gem (optional, for interactive menu)

**Usage:**
```bash
ruby postpro.rb                        # Interactive mode
ruby postpro.rb --auto                 # Auto mode (default preset)
ruby postpro.rb --from-repligen        # Process Repligen outputs
```

### Repligen - Replicate.com AI Generation CLI

Model discovery, LoRA generation, and chain workflows for Replicate.com.

```bash
cd repligen
ruby repligen.rb              # Interactive menu
ruby repligen.rb sync 100     # Sync 100 models
ruby repligen.rb search upscale
ruby repligen.rb stats
```

**Features:**
- Model discovery with intelligent type inference
- SQLite3 database for offline model browsing
- LoRA generation support
- Chain workflow system (masterpiece/quick templates)
- Cost tracking for prediction runs
- Interactive menu + CLI arguments

**Setup:**
1. Get API token: https://replicate.com/account/api-tokens
2. Set environment variable or config file:
   ```bash
   export REPLICATE_API_TOKEN=r8_...
   # OR
   echo '{"api_token":"r8_..."}' > ~/.config/repligen/config.json
   ```

## Design Principles

- **Modular Architecture**: Each tool split into focused modules (~100-200 lines)
- **Zero Sprawl**: 3 tools, clear hierarchy, shared runtime cache
- **Data Externalization**: JSON for progressions, profiles, recipes
- **Auto-cleanup**: Temp files removed after processing
- **Self-contained**: Minimal external dependencies
- **Production Ready**: All tools syntax-checked and functional

## Notes

- All tools follow master.json conventions
- Runtime files in `.cache/` (gitignored)
- Camera profiles and recipes in JSON for easy customization
- TTS cache reduces API calls
- SoX synthesis avoids copyright issues with samples

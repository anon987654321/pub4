# multimedia

Single-file interactive CLIs for audio/image/AI workflows. Ruby 3.2+.

## Tools

### tts.rb — Text-to-Speech

Deep Malaysian voice (ms-MY, -12.5 semitones). Google TTS. MP3 caching.

```zsh
ruby tts.rb "Selamat datang"   # speak text
ruby tts.rb --interactive      # interactive mode
ruby tts.rb --voices           # list voices
```

### dilla.rb — J Dilla Music Generator

Pure Ruby FM synthesis. 10 Dilla chord progressions. SoX effects.

```zsh
ruby dilla.rb                  # interactive menu
ruby dilla.rb --generate       # generate all progressions (~5-8 min)
ruby dilla.rb --play           # play continuously
```

### postpro.rb — Cinematic Post-Processing

4 film stocks (Portra, Vision3, Velvia, Tri-X). Presets: portrait, landscape, street, blockbuster.

```zsh
ruby postpro/postpro.rb        # interactive mode
ruby postpro/postpro.rb --preset portrait **/*.jpg
```

Requires `ruby-vips` (libvips).

### repligen.rb — Replicate.com AI CLI

Model discovery (48k+ models). LoRA training. Pipeline chains. SQLite cache.

```zsh
ruby repligen.rb               # interactive menu
ruby repligen.rb sync 100      # sync models
ruby repligen.rb search upscale
```

Requires `REPLICATE_API_TOKEN`.

## Configuration

`config.json` — unified config for all tools.

## Layout

```
multimedia/
  config.json
  tts.rb
  dilla.rb
  repligen.rb
  tts/cache/
  dilla/chords/  drums/  bass/  final/
  postpro/
  repligen/repligen.db
```

## Requirements

- Ruby 3.2+ (native or Cygwin)
- SoX for dilla audio output
- `sqlite3` gem (repligen)
- `ruby-vips` gem (postpro)

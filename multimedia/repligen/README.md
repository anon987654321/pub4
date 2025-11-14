# Repligen - Replicate.com CLI
**Universal AI workflow engine**: Scrape Replicate models, train LoRAs, build random masterpiece chains

## Features
- 🔍 **Model Discovery**: Scrape 48k+ models from Replicate.com
- 🎨 **LoRA Training**: Train custom models from 5+ images
- ⛓️  **Chain Building**: Create 8-20 step masterpiece pipelines
- 💾 **SQLite Database**: Fast local search & filtering

- 🎯 **Interactive CLI**: Natural language interface

- 💰 **Cost Tracking**: Monitor API spending

## Quick Start

```bash

# Install dependencies
gem install sqlite3 ferrum
# Set API token

export REPLICATE_API_TOKEN="r8_..."

# Run interactive CLI
ruby repligen.rb

```
## Interactive Commands

```bash

repligen> scrape 100                    # Build model database
repligen> lora https://img1.jpg ...     # Train custom LoRA (5+ images)
repligen> masterpiece cyberpunk sunset  # Random 8-20 step chain

repligen> chain 15 epic dragon battle   # Custom length chain

repligen> search upscale                # Find models by keyword

repligen> stats                         # Database statistics

```

## Command Line Usage

```bash

# Scrape models
ruby repligen.rb --scrape 50
# Show stats

ruby repligen.rb --stats

# Help
ruby repligen.rb --help

```
## Chain Types

Repligen builds random chains from scraped models:

1. **Generation** (text-to-image): FLUX, SDXL, Imagen3
2. **Enhancement**: Upscale, style transfer, processing
3. **Polish**: Final upscale or video conversion
### Example Chain

```

1. stability-ai/sdxl:latest          $0.05
2. nightmareai/real-esrgan:latest    $0.02
3. lucataco/style-transfer:latest    $0.03

4. stability-ai/stable-video:latest  $0.12

────────────────────────────────────

Total cost: $0.22

```

## LoRA Training

Train custom models from your images:

```bash
repligen> lora https://photo1.jpg https://photo2.jpg ... (min 5)
```
Uses `ostris/flux-dev-lora-trainer`:

- **Steps**: 1000

- **LoRA Rank**: 16
- **Optimizer**: adamw8bit

- **Auto-caption**: Enabled

## Database

Models stored in `repligen.db` with:

- Full metadata (owner, name, description)
- Inferred types (text-to-image, upscale, video, etc.)
- Cost estimates

- Run counts

### Statistics

```bash

repligen> stats
📊 DATABASE STATISTICS
Total models: 48,234

By Category:
  text-to-image           12,456

  upscale                  3,891
  image-to-video           2,103

  style-transfer           1,789

  ...

```

## Utilities

### scrape_models.rb

Direct API scraper for specific models:
```bash
ruby scrape_models.rb stability-ai/sdxl

```
### scrape_replicate_explore.rb

Advanced explore page scraper with infinite scroll:

```bash
ruby scrape_replicate_explore.rb 100  # Scroll 100 pages

```
## Architecture

- **ModelDatabase**: SQLite3 with full-text search

- **ReplicateClient**: HTTP client with retry/polling
- **ChainBuilder**: Random pipeline generator
- **InteractiveCLI**: TTY-based REPL

## Cost Management

Default budget tracking:

- Estimated cost per model
- Running total per chain
- Alert before expensive operations

## Dependencies

- `sqlite3` (required): Database storage

- `ferrum` (optional): Headless Chrome for scraping
- Ruby 3.2+
## Notes

- Database builds incrementally (scrape multiple times)

- Chains execute sequentially with 1s rate limiting
- Failed steps skip gracefully with previous output
- All outputs saved with timestamped filenames

---

**Version**: 3.0.0

**License**: MIT
**Docs**: See CLAUDE.md for integration patterns

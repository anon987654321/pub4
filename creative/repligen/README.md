# Repligen v8.0.0

Replicate.com AI Generation CLI - Model discovery, chain workflows, and creative generation.

## Features

- **SQLite3 database**: Local catalog of 1000+ models
- **Ferrum web scraping**: Scrape replicate.com/explore for model discovery
- **Chain workflows**: Masterpiece (T2I + upscale + style + I2V), Quick (T2I + upscale)
- **Cost tracking**: Per-model and total cost estimation
- **LoRA support**: Direct generation with LoRA models
- **Interactive menu**: TTY-prompt for easy navigation
- **API integration**: Full Replicate.com API support

## Dependencies

Required:
```
gem install sqlite3
```

Optional (for web scraping):
```
gem install ferrum
```

API Token:
```
export REPLICATE_API_TOKEN=r8_...
```
Or store in `~/.config/repligen/config.json`

## Usage

Interactive mode:
```
ruby repligen.rb
```

Sync models via API:
```
ruby repligen.rb sync 1000
```

Scrape models from website (requires ferrum):
```
ruby repligen.rb scrape 50
```

Search database:
```
ruby repligen.rb search upscale
```

Show statistics:
```
ruby repligen.rb stats
```

## Chain Workflows

**Masterpiece**: T2I → multiple upscale/style steps → I2V  
**Quick**: T2I → single upscale

Automatically selects models from database and executes in sequence.

## Architecture

Single consolidated file (845 lines):
- Bootstrap module (gem management)
- Config module (token handling)
- Database class (SQLite3 operations)
- API class (HTTP client)
- ChainBuilder (workflow execution)
- Interactive menu

Note: Full featured version with ModelRAG and postpro integration available in repository (1,770 lines).

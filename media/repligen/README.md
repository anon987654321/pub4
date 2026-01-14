# Repligen - AI Media Generation Pipeline
Professional AI media generation with natural language cinematography.
## Quick Start
```bash
cd repligen

export REPLICATE_API_TOKEN="your_token"

# Generate image with natural language
ruby repligen.rb generate "Close-up portrait of Norwegian athlete, golden hour lighting on beach, shot on ARRI Alexa Mini LF with 85mm lens at T1.8"

# Generate 10s video
ruby repligen.rb video "Volleyball serve at sunset, dramatic slow motion"

# Execute model chain (RA2 LoRA → Video)
ruby repligen.rb chain "cinematic portrait with dramatic lighting"

# Train custom LoRA
mkdir -p __lora/subject_name

# Add 10-20 photos to __lora/subject_name/

ruby repligen.rb lora subject_name

# Generate multi-clip commercial
ruby repligen.rb commercial "Team Norway" ra2

# Index Replicate models to local database
ruby repligen.rb index

# Search indexed models
ruby repligen.rb search "video generation"

```

## Natural Language Prompting (FLUX 2)
✅ **Do:**
- Write conversational descriptions (15-75 words)

- Lead with primary subject

- Specify camera, lens, lighting

- Reference film stocks (Kodak Vision3 500T, Portra 400)

- Use professional cinematography terms

❌ **Don't:**
- Keyword-stack ("masterpiece, best quality, 8K, ultra detailed")

- Use quality tags (waste tokens on FLUX 2)

- Use negative prompts (not supported)

- Write verbose descriptions (>75 words)

### Good Example
```

"Portrait of woman in her late 30s with auburn hair and freckles,

subtle confident smile, Rembrandt lighting with soft rim light,

neutral gray studio backdrop, shot on 85mm f/1.8 lens,

shallow depth of field, editorial photography"

```

## LoRA Training
1. Create folder: `__lora/subject_name/`
2. Add 10-20 varied photos (different angles, lighting)

3. Run: `ruby repligen.rb lora subject_name`

4. Follow instructions to train on Replicate (~$10, 15-30 min)

5. Use trigger word `SUBJECT_NAME` in prompts

**Tips:**
- Use original photos, no AI variations

- Include variety: close-ups, full body, indoor/outdoor

- Avoid heavy filters or makeup

- Quality > quantity (15 great photos > 50 mediocre)

## Costs
| Operation | Cost | Duration |
|-----------|------|----------|

| Single image (Flux Pro) | $0.04 | ~5s |

| 10s video (Hailuo) | $0.30 | ~60s |

| Image + video | $0.34 | ~65s |

| 3-scene commercial | ~$1.00 | ~5min |

| LoRA training | ~$10 | 15-30min |

## Output
All generated media saves to current directory with timestamped filenames.
## Post-Processing
Apply film emulation and color grading with `../postpro.rb`:
```bash
# Upload to OpenBSD VPS

scp video.mp4 dev@your-vps:/home/dev/raw/

# Apply cinematic grading
ssh dev@your-vps 'ruby postpro.rb --video raw/video.mp4 --preset blockbuster'

```

Available presets: portrait, landscape, street, blockbuster
Film stocks: Kodak Portra 400, Fuji Velvia 50, Tri-X 400

## Version
v13.0.0 - Consolidated single-file architecture with:
- Natural language cinematography

- LoRA training and enhancement

- Multi-clip commercial generation

- Model chain execution (RA2 → Video)

- Local model indexing and search

- SQLite database for model discovery


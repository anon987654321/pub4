# Repligen - Interactive AI Generation
## Usage

```bash

ruby repligen.rb

```
## Interactive Menu
```

🎨 REPLIGEN - Interactive AI Generation

============================================================
What would you like to do?
  1. Generate with LoRA URL      ← Paste any Replicate model URL

  2. Sync models from Replicate  ← Scrape API, store in DB
  3. Search models               ← Query local database
  4. Show statistics             ← View synced models
  5. Run chain workflow          ← Multi-step generation
  6. Exit
```
## LoRA Workflow
1. Select "Generate with LoRA URL"

2. Paste model URL: `replicate.com/owner/model-name`

3. Enter prompt: "cinematic portrait, dramatic lighting"
4. Wait for generation (shows progress with dots)
5. Images saved to `output/owner_model_timestamp/`
6. Optional: Process with postpro for film stock look
## Example
```

LoRA model URL: replicate.com/black-forest-labs/flux-schnell

Generation prompt: masterpiece, cinematic lighting, cyberpunk
🚀 Generating with black-forest-labs/flux-schnell...
Prompt: masterpiece, cinematic lighting, cyberpunk

.........
💾 Downloading https://replicate.delivery/...
✓ Saved: output/black-forest-labs_flux-schnell_1729048392/output.png
✓ Complete! Output: output/black-forest-labs_flux-schnell_1729048392
Process with postpro? (Y/n)

```
## Database
- Location: `repligen.db` (SQLite3)

- Synced models: 100+ (text-to-image, video, upscale, etc.)

- Search by type, name, description
## Integration
- **repligen**: Generates images via Replicate API

- **postpro**: Applies cinematic film stock processing (libvips)

- **Workflow**: Generate → Save → Process → Final output

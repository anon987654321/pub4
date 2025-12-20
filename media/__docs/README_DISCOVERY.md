# Repligen 9.0 - Motion Graphics Discovery System

**Status:** Ready for indexing (Ruby environment needs debugging)  
**Date:** 2025-12-12  
**Commit:** e096d36

## 🎯 Vision

Generate **never-before-seen motion graphics** by chaining random AI models in unexpected combinations, creating emergent visual effects through algorithmic serendipity.

## 📦 Components

### 1. model_indexer.rb - Model Database Builder
**Purpose:** Index all 50,000+ Replicate models

**Features:**
- Fetches all collections via API
- Indexes models with metadata
- Builds SQLite database
- Search and statistics functions

**Usage:**
```bash
export REPLICATE_API_TOKEN='r8_...'
ruby model_indexer.rb index     # Index all models
ruby model_indexer.rb stats     # Show database stats
ruby model_indexer.rb search depth  # Search for models
```

**Database Schema:**
- `models`: id, owner, name, description, category, run_count, cost
- `collections`: slug, name, description, model_count
- `model_collections`: mapping table

---

### 2. chain_generator.rb - Random Chain Creator
**Purpose:** Generate compatible model chains

**Categories:**
- **Generators**: image-generation, video-generation, text-to-video
- **Effects**: style-transfer, image-to-image, video-editing
- **Depth**: depth-estimation, 3d-generation
- **Motion**: video-interpolation, animation
- **Audio**: music-generation, audio-reactive
- **Upscale**: super-resolution, restoration
- **Utility**: background-removal, segmentation

**Preset Chains:**
```bash
ruby chain_generator.rb cinematic    # Portrait → depth → motion → style → upscale
ruby chain_generator.rb psychedelic  # Image → deep dream → kaleidoscope → morph
ruby chain_generator.rb glitch       # Generate → glitch → pixel sort → RGB split
ruby chain_generator.rb random 7     # Random 7-step chain
ruby chain_generator.rb explore 100  # Generate 100 random chains
```

---

### 3. repligen_v9.rb - AI Orchestrator
**Purpose:** Execute chains with Llama 3.3 70B directing

**Latest Models (Dec 2025):**
- **Image**: Flux 2 Pro, ra2 LoRA, Flux 2 Dev
- **Video**: Veo 3.1, Runway Gen-4.5, Kling 2.6, Luma Ray 2
- **LLM**: Llama 3.3 70B (FREE orchestrator)

**Features:**
- tty-prompt interactive CLI
- Cinematic workflow for ra2 LoRA
- Prompt enhancement
- Cost tracking

**Usage:**
```bash
ruby repligen_v9.rb                          # Interactive mode
ruby repligen_v9.rb cinematic "portrait"     # Command line
```

---

## 🎨 Example Chains

### Cinematic Portrait
```
1. anon987654321/ra2 → Portrait generation
2. depth-anything/v2 → Depth map
3. stabilityai/stable-video-diffusion → Add motion
4. style-transfer-model → Artistic style
5. topaz/video-enhance → Upscale 4K
```

### Psychedelic Trip
```
1. flux-2-pro → Base image
2. deep-dream → Psychedelic patterns
3. kaleidoscope-effect → Kaleidoscope
4. color-shift → Color manipulation
5. video-morph → Fluid morphing
6. audio-reactive → Music sync
```

### Glitch Art
```
1. flux-2-dev → Quick generation
2. glitch-effect → Digital corruption
3. pixel-sort → Pixel sorting
4. rgb-split → Chromatic aberration
5. noise-injection → Analog noise
```

---

## 🚀 Workflow

### Phase 1: Index Models (Tonight)
```bash
cd G:pubmedia
export REPLICATE_API_TOKEN='your_api_token_here'
ruby model_indexer.rb index
```

**Expected:** 
- ~100 collections
- ~5,000+ models indexed
- SQLite database created
- Duration: 5-10 minutes

### Phase 2: Generate Chains
```bash
# Generate 100 random chains
ruby chain_generator.rb explore 100

# Review chains/ directory
ls chains/
```

### Phase 3: Execute Best Chains
```bash
# Use repligen_v9.rb to execute promising chains
ruby repligen_v9.rb

# Or integrate chain execution into repligen
```

### Phase 4: Discovery
- Run chains
- Save outputs
- Analyze results
- Identify "greatest hits"
- Create presets

---

## 💡 The Magic

**Why This Works:**

1. **Emergent Behaviors**: Models weren't designed to work together
2. **Unexpected Interactions**: Chain outputs create novel inputs
3. **Serendipity at Scale**: Random exploration finds hidden gems
4. **Llama as Director**: AI chooses parameters intelligently

**Example Emergent Effect:**
```
depth_map → style_transfer → video_morph → audio_reactive
```
Could create: *Depth-aware style that morphs to music in ways no single model could achieve*

---

## 📊 Technical Details

**API Endpoints:**
- `GET /v1/collections` - List all collections
- `GET /v1/collections/{slug}` - Get models in collection
- `POST /v1/predictions` - Run model
- `GET /v1/predictions/{id}` - Check status

**Rate Limiting:**
- 1 request/second during indexing
- Pagination via `next` cursor

**Cost Estimation:**
- Indexing: FREE (read-only)
- Chain execution: $0.50 - $2.00 per chain
- Exploration mode (100 chains): $50 - $200

---

## 🐛 Known Issues

1. **Ruby hanging on Windows**: Need to test on OpenBSD VPS
2. **Model schemas**: Need to fetch detailed input/output schemas
3. **Compatibility matrix**: Need to build smart routing
4. **Cost tracking**: Need to fetch actual model costs

---

## 🎯 Next Steps

1. **Debug Ruby API calls** on OpenBSD VPS
2. **Run full indexing** (5-10 min)
3. **Generate 100 random chains**
4. **Execute top 10 chains**
5. **Document discoveries**
6. **Create "greatest hits" presets**

---

## 🌟 Vision

**Goal:** Create a self-discovering motion graphics engine that:
- Generates chains never conceived by humans
- Finds emergent visual effects
- Learns from results
- Creates "impossible" aesthetics

**This could genuinely revolutionize motion graphics!** 🎨🚀

---

**Files:**
- `model_indexer.rb` - Model database builder
- `chain_generator.rb` - Random chain creator
- `repligen_v9.rb` - AI orchestrator
- `repligen_models.db` - SQLite database (created on first run)
- `chains/` - Generated chain JSON files

**Repository:** https://github.com/anon987654321/pub4  
**Commit:** e096d36

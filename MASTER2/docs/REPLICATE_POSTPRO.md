# Replicate & Postpro: AI-Powered Media Generation & Enhancement

## Vision

Transform MASTER2 into a **creative powerhouse** for AI-driven media generation and enhancement. Replicate and Postpro modules provide direct access to cutting-edge generative AI models, enabling filmmakers, artists, and developers to create **cinematic-quality** images, videos, and enhanced media with simple Ruby interfaces.

This is not just an API wrapper—it's a **production-ready creative toolkit** that brings Hollywood-grade visual effects and AI generation into your Ruby workflow.

## The Big Picture

### Why This Matters

The democratization of AI-powered creativity is here. What once required multi-million dollar VFX studios and specialized artists can now be achieved with a few lines of Ruby code:

- **Image Generation**: Flux Pro, SDXL, Ideogram V2 - state-of-the-art text-to-image models
- **Video Generation**: Hailuo 2.3, Kling 2.5, Luma Ray 2, Sora 2 - cinematic video from text
- **Enhancement**: Real-ESRGAN 4x, GFPGAN, CodeFormer - restore and upscale with AI
- **Audio**: MusicGen, Bark TTS - generate soundscapes and speech
- **Transcription**: Whisper - accurate speech-to-text

### The Architecture

```
MASTER2 Pipeline
    ↓
Replicate Module (Image/Video/Audio Generation)
    ├─ WILD_CHAIN Model Catalog (categorized AI models)
    ├─ Direct Replicate.com API integration
    ├─ Result monad pattern (no exceptions)
    ├─ Automatic polling & retry
    └─ Budget tracking integration
    
Postpro Module (Enhancement & Post-Processing)
    ├─ Upscaling (4x, 8x with AI)
    ├─ Face Restoration (GFPGAN, CodeFormer)
    ├─ Denoising & Sharpening
    ├─ Color Grading presets
    └─ Batch operations
    
Cinematic Pipeline (High-Level Workflows)
    ├─ Multi-model chaining
    ├─ Built-in presets (Blade Runner, Wes Anderson, etc.)
    └─ Discovery mode for new aesthetics
```

## Core Philosophy

### 1. **Production-Ready**
Not a toy or proof-of-concept. Used for real creative work:
- Robust error handling (Result monad)
- Retry logic with exponential backoff
- Budget tracking and limits
- Logging and debugging support

### 2. **Ruby-Native Integration**
Seamless integration with MASTER2's pipeline:
- Same Result pattern as the rest of MASTER2
- Integrated with LLM budget tracking
- Works with session management
- REPL commands available

### 3. **Extensible & Discoverable**
Easy to add new models and capabilities:
- WILD_CHAIN catalog structure
- Model categorization (image_gen, video_gen, enhance, audio, transcribe)
- Self-documenting via `categories` and `models_for` methods

## Replicate Module

### Overview

The `Replicate` module provides access to 30+ cutting-edge AI models via Replicate.com API. It handles the complexity of async predictions, polling, retries, and error handling.

### WILD_CHAIN Model Catalog

A curated collection of the best AI models, organized by capability:

#### Image Generation (5 models)
- **Flux Pro** - State-of-the-art photorealism
- **Flux Dev** - Fast iteration, excellent quality
- **SDXL** - Stable Diffusion XL, highly controllable
- **Ideogram V2** - Best for text rendering in images
- **Recraft V3** - Vector-friendly generation

#### Video Generation (5 models)
- **Hailuo 2.3** (Minimax) - High-quality video synthesis
- **Kling 2.5** - Fast, smooth motion
- **Luma Ray 2** - Photorealistic video
- **WAN 2.5** - Image-to-video specialist
- **Sora 2** (OpenAI) - Cinematic quality, long duration

#### Enhancement (4 models)
- **Real-ESRGAN 4x** - General-purpose upscaling
- **GFPGAN** - Face restoration specialist
- **CodeFormer** - Advanced face enhancement
- **Clarity Upscaler 4x** - Detail preservation

#### Audio (2 models)
- **MusicGen** (Meta) - Music generation from text
- **Bark TTS** (Suno) - Natural text-to-speech

#### Transcription (1 model)
- **Whisper** (OpenAI) - State-of-the-art speech recognition

### API Examples

#### Basic Image Generation

```ruby
# Generate an image with Flux Pro
result = MASTER::Replicate.generate_image(
  prompt: "cinematic shot of a cyberpunk city at night, neon lights, rain"
)

if result.ok?
  puts "Image URL: #{result.value[:urls].first}"
  puts "Prediction ID: #{result.value[:id]}"
else
  puts "Error: #{result.error}"
end
```

#### Video Generation

```ruby
# Generate a video with Hailuo
result = MASTER::Replicate.generate_video(
  prompt: "drone shot flying through a forest at golden hour, cinematic"
)

if result.ok?
  puts "Video URL: #{result.value[:urls].first}"
end
```

#### Image Enhancement

```ruby
# Upscale with Real-ESRGAN
result = MASTER::Replicate.enhance_image(
  image_url: "https://example.com/photo.jpg"
)

if result.ok?
  puts "Enhanced: #{result.value[:urls].first}"
end
```

#### Model Discovery

```ruby
# List all categories
categories = MASTER::Replicate.categories
# => [:image_gen, :video_gen, :enhance, :audio, :transcribe]

# Get models in a category
models = MASTER::Replicate.models_for(:image_gen)
models.each do |m|
  puts "#{m[:name]}: #{m[:model]}"
end

# Get all models
all_models = MASTER::Replicate.all_models
# => Array of hashes with :category, :model, :name
```

### Advanced Features

#### Custom Model Parameters

```ruby
result = MASTER::Replicate.generate(
  prompt: "portrait of a woman",
  model: "stability-ai/sdxl",
  params: {
    negative_prompt: "blurry, distorted",
    num_inference_steps: 40,
    guidance_scale: 7.5,
    width: 1024,
    height: 1024
  }
)
```

#### Model Information

```ruby
info = MASTER::Replicate.model_info("black-forest-labs/flux-pro")
# => { category: :image_gen, model: "...", name: "Flux Pro" }
```

## Postpro Module

### Overview

The `Postpro` module provides high-level enhancement operations optimized for common workflows. While `Replicate` gives you raw access to models, `Postpro` provides curated operations for specific tasks.

### Operations

#### Upscale
Intelligent 4x upscaling using AI:

```ruby
result = MASTER::Postpro.upscale(
  image_url: "photo.jpg",
  scale: 4  # Optional: 2, 4, or 8
)
```

#### Face Restoration
Specifically optimized for faces:

```ruby
result = MASTER::Postpro.restore_face(
  image_url: "old_photo.jpg"
)
```

#### Generic Enhancement
Choose your operation:

```ruby
result = MASTER::Postpro.enhance(
  image_url: "photo.jpg",
  operation: :upscale,  # or :face_restore, :denoise, :color_grade, :sharpen
  params: { strength: 0.8 }
)
```

#### Batch Processing
Process multiple images:

```ruby
urls = ["photo1.jpg", "photo2.jpg", "photo3.jpg"]
results = MASTER::Postpro.batch_enhance(
  image_urls: urls,
  operation: :upscale
)

results.value.each do |r|
  puts "#{r[:url]} -> #{r[:result].ok? ? 'Success' : 'Failed'}"
end
```

#### List Operations

```ruby
ops = MASTER::Postpro.operations
ops.each do |op|
  puts "#{op[:id]}: #{op[:name]} - #{op[:description]}"
end

# Output:
# upscale: Upscale 4x - Upscale 4x
# face_restore: Face Restoration - Face Restoration  
# denoise: Denoise - Remove noise from images
# color_grade: Color Grading - Apply color grading presets
# sharpen: Sharpen - Enhance image sharpness
```

## CLI Commands

### REPL Usage

```bash
$ ./bin/master

# Generate image
master> repligen "cyberpunk city at night"
🎨 Generating image: cyberpunk city at night
✓ Image generated: https://replicate.delivery/...

# Generate video  
master> generate-video "drone flying through forest"
🎬 Generating video: drone flying through forest
✓ Video generated: https://replicate.delivery/...

# Enhance/upscale
master> upscale photo.jpg
🔧 Upscaling image...
✓ Done: https://replicate.delivery/...

# List postpro operations
master> postpro
Postpro Operations:
  upscale - Upscale 4x
  face_restore - Face Restoration
  denoise - Denoise
  color_grade - Color Grading
  sharpen - Sharpen

# Apply specific enhancement
master> postpro upscale photo.jpg
🔧 Enhancing with upscale...
✓ Enhanced: https://replicate.delivery/...
```

## Integration with MASTER2

### Budget Tracking

All Replicate/Postpro operations respect MASTER2's budget system:

```ruby
# Check budget before generation
puts "Remaining: #{MASTER::LLM.budget_remaining}"

result = MASTER::Replicate.generate_image(prompt: "...")

puts "Cost: #{result.value[:cost]}"  # If available
puts "New balance: #{MASTER::LLM.budget_remaining}"
```

### Result Monad Pattern

Consistent error handling across all operations:

```ruby
result = MASTER::Replicate.generate_image(prompt: "test")

case result
when ->(r) { r.ok? }
  process_image(result.value[:urls].first)
when ->(r) { r.err? }
  MASTER::Logging.error("Generation failed: #{result.error}")
  alert_user(result.error)
end
```

### Session Integration

Operations are logged in session history:

```ruby
session = MASTER::Session.current
# All Replicate/Postpro calls automatically logged
session.history  # Contains generation metadata
```

## Production Use Cases

### 1. **Automated Social Media Content**
Generate daily image variations for Instagram:

```ruby
themes = ["sunset", "cityscape", "nature", "abstract"]
theme = themes.sample

result = MASTER::Replicate.generate_image(
  prompt: "#{theme}, professional photography, 4K",
  model: :flux
)

if result.ok?
  # Post to Instagram via API
  instagram_post(result.value[:urls].first)
end
```

### 2. **Video Production Pipeline**
Create video content from scripts:

```ruby
scenes = parse_script("script.txt")

scenes.each do |scene|
  video_result = MASTER::Replicate.generate_video(
    prompt: scene[:description]
  )
  
  if video_result.ok?
    # Enhance with upscaling
    enhanced = MASTER::Postpro.upscale(
      image_url: video_result.value[:urls].first,
      scale: 4
    )
    
    save_scene(scene[:number], enhanced.value[:urls].first)
  end
end
```

### 3. **Photo Restoration Service**
Batch restore old photos:

```ruby
Dir.glob("uploads/*.jpg").each do |photo|
  # Restore faces
  restored = MASTER::Postpro.restore_face(image_url: photo)
  
  if restored.ok?
    # Upscale
    final = MASTER::Postpro.upscale(
      image_url: restored.value[:urls].first,
      scale: 4
    )
    
    save_to_output(photo, final.value[:urls].first)
  end
end
```

### 4. **Cinematic Pipeline**
Chain models for film-quality output (see [CINEMATIC_PIPELINE.md](CINEMATIC_PIPELINE.md)):

```ruby
pipeline = MASTER::Cinematic::Pipeline.new
  .chain('stability-ai/sdxl', { 
    prompt: 'cyberpunk aesthetic, blade runner style',
    guidance_scale: 12 
  })
  .chain('tencentarc/gfpgan', { scale: 2 })
  .chain('nightmareai/real-esrgan', { scale: 4 })

result = pipeline.execute("input.jpg", save_intermediates: true)
```

## Configuration

### Environment Variables

```bash
# Required
export REPLICATE_API_KEY="r8_..."

# Optional (in MASTER2 config)
export MASTER_REPLICATE_TIMEOUT=300  # Timeout in seconds
export MASTER_POLL_INTERVAL=2        # Polling interval
```

### Timeout Configuration

Replicate operations use `MASTER::Timeouts`:

```ruby
# From llm.rb (merged from timeouts.rb)
MASTER::Timeouts::REPLICATE_TIMEOUT  # 300 seconds default
MASTER::Timeouts::POLL_INTERVAL      # 2 seconds default
```

## Error Handling

### Common Errors

```ruby
result = MASTER::Replicate.generate_image(prompt: "test")

case result.error
when /API key not set/
  # Set REPLICATE_API_KEY
when /Rate limit/
  # Back off and retry
when /timeout/
  # Increase timeout or retry
when /model not found/
  # Check model ID spelling
end
```

### Retry Logic

Built-in retry with exponential backoff:

```ruby
# Automatic retry on transient failures
# Configured in circuit_breaker.rb
# 3 attempts with exponential backoff
```

## Performance & Costs

### Generation Times (Approximate)

| Model Type | Typical Time | Cost Range |
|------------|--------------|------------|
| Image (Flux Pro) | 10-30s | $0.10-0.30 |
| Image (SDXL) | 5-15s | $0.05-0.15 |
| Video (Hailuo) | 60-180s | $0.50-2.00 |
| Upscale (4x) | 10-20s | $0.05-0.10 |
| Face Restore | 5-10s | $0.03-0.08 |

*Actual costs vary by Replicate.com pricing*

### Optimization Tips

1. **Use appropriate tiers**: Don't use Flux Pro when Flux Dev suffices
2. **Batch operations**: Reduces API overhead
3. **Cache results**: Store generated URLs
4. **Monitor budget**: Track costs in MASTER2 budget system
5. **Async processing**: Use background jobs for long operations

## Future Enhancements

### Planned Features

- [ ] **Local model support**: Run models locally via Ollama/LocalAI
- [ ] **Model caching**: Cache frequently-used models
- [ ] **Smart model selection**: AI chooses best model for prompt
- [ ] **Cost prediction**: Estimate before generation
- [ ] **Quality scoring**: AI rates output quality
- [ ] **Automatic retry with fallback**: Try different models if one fails
- [ ] **Streaming output**: Progressive image generation display
- [ ] **Model fine-tuning**: Train custom models via Replicate

### Research Directions

- **Evolutionary algorithms** for pipeline optimization
- **Aesthetic scoring** using CLIP/other models
- **Semantic caching** to avoid duplicate generations
- **Multi-modal chaining** (text → image → video → audio)
- **Real-time generation** for interactive applications

## Contributing

### Adding New Models

Edit `lib/replicate.rb` to add models to `WILD_CHAIN`:

```ruby
WILD_CHAIN = {
  image_gen: [
    # ... existing models ...
    { model: "new-org/new-model", name: "New Model" }
  ]
}
```

### Adding New Operations

Edit `lib/replicate.rb` to add operations to `Postpro::OPERATIONS`:

```ruby
OPERATIONS = {
  # ... existing operations ...
  new_op: {
    name: "New Operation",
    models: ["model-id"],
    description: "What it does"
  }
}
```

## Credits & Acknowledgments

### Built On
- [Replicate.com](https://replicate.com) - AI model hosting platform
- MASTER2 Pipeline Architecture - Result monad, session management
- Ruby Standard Library - HTTP client, JSON parsing

### Model Credits
- **Flux** by Black Forest Labs
- **SDXL** by Stability AI
- **Real-ESRGAN** by Xinntao
- **GFPGAN** by Tencent ARC Lab
- **Whisper** by OpenAI
- **Bark** by Suno AI
- And many more amazing AI researchers

## License

Part of MASTER2. See main repository license (MIT).

## Support & Community

- **Issues**: GitHub Issues for bugs and feature requests
- **Discussions**: GitHub Discussions for questions
- **Examples**: See `MASTER2/examples/` for more code samples
- **Documentation**: This file and [CINEMATIC_PIPELINE.md](CINEMATIC_PIPELINE.md)

---

**Remember**: This is not just an API wrapper. This is a **creative production toolkit** that brings the power of cutting-edge AI into your Ruby workflow. Use it to build amazing things. 🎨🎬✨

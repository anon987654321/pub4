# Replicate Plugin for MASTER2

AI-powered image, video, and audio generation via Replicate.com API.

## Overview

The Replicate plugin provides direct access to 30+ cutting-edge generative AI models through a unified Ruby interface. Generate images, videos, audio, and transcriptions with state-of-the-art models from Stability AI, Black Forest Labs, OpenAI, Meta, and more.

## Installation

The plugin is built into MASTER2. Just set your API key:

```bash
export REPLICATE_API_KEY="r8_..."
```

## Quick Start

```ruby
# Generate an image
result = MASTER::Replicate.generate_image(
  prompt: "cyberpunk city at night, neon lights, cinematic"
)

if result.ok?
  puts "Image URL: #{result.value[:urls].first}"
end

# Generate a video
result = MASTER::Replicate.generate_video(
  prompt: "drone shot flying through a forest at golden hour"
)

# List available model categories
MASTER::Replicate.categories
# => [:image_gen, :video_gen, :enhance, :audio, :transcribe]

# Get models in a category
MASTER::Replicate.models_for(:image_gen)
# => [{ model: "black-forest-labs/flux-pro", name: "Flux Pro" }, ...]
```

## WILD_CHAIN Model Catalog

The plugin includes 17 carefully curated AI models across 5 categories:

### Image Generation (5 models)

| Model | Best For |
|-------|----------|
| **Flux Pro** | State-of-the-art photorealism |
| **Flux Dev** | Fast iteration, excellent quality |
| **SDXL** | Highly controllable, stable diffusion |
| **Ideogram V2** | Text rendering in images |
| **Recraft V3** | Vector-friendly generation |

### Video Generation (5 models)

| Model | Best For |
|-------|----------|
| **Hailuo 2.3** (Minimax) | High-quality video synthesis |
| **Kling 2.5** | Fast, smooth motion |
| **Luma Ray 2** | Photorealistic video |
| **WAN 2.5** | Image-to-video conversion |
| **Sora 2** (OpenAI) | Cinematic quality, long duration |

### Enhancement (4 models)

| Model | Best For |
|-------|----------|
| **Real-ESRGAN 4x** | General-purpose upscaling |
| **GFPGAN** | Face restoration |
| **CodeFormer** | Advanced face enhancement |
| **Clarity Upscaler 4x** | Detail preservation |

### Audio (2 models)

| Model | Best For |
|-------|----------|
| **MusicGen** (Meta) | Music generation from text |
| **Bark TTS** (Suno) | Natural text-to-speech |

### Transcription (1 model)

| Model | Best For |
|-------|----------|
| **Whisper** (OpenAI) | Accurate speech recognition |

## CLI Commands

```bash
$ ./bin/master

master> repligen "cyberpunk city at night"
🎨 Generating image...
✓ Image generated: https://replicate.delivery/...

master> generate-video "drone flying through forest"
🎬 Generating video...
✓ Video generated: https://replicate.delivery/...
```

## Related Plugins

- **[Postpro](../postpro/README.md)** - Image enhancement operations
- **[Cinematic](../../docs/CINEMATIC_PIPELINE.md)** - Multi-model pipeline chaining

## License

Part of MASTER2. See main repository license (MIT).

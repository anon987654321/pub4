# Postpro Plugin for MASTER2

AI-powered image enhancement and post-processing operations.

## Overview

The Postpro plugin provides high-level enhancement operations for images using AI models. While the Replicate plugin gives raw access to models, Postpro offers curated operations optimized for common workflows like upscaling, face restoration, and batch processing.

## Installation

The plugin is built into MASTER2. Requires Replicate API access:

```bash
export REPLICATE_API_KEY="r8_..."
```

## Quick Start

```ruby
# Upscale an image 4x
result = MASTER::Postpro.upscale(
  image_url: "photo.jpg",
  scale: 4
)

# Restore faces in old photos
result = MASTER::Postpro.restore_face(
  image_url: "old_photo.jpg"
)

# List available operations
MASTER::Postpro.operations
# => [{ id: :upscale, name: "Upscale 4x", ... }, ...]
```

## Operations

### Upscale

AI-powered image upscaling with detail preservation.

**Models Used:** Real-ESRGAN, Clarity Upscaler

```ruby
result = MASTER::Postpro.upscale(
  image_url: "photo.jpg",
  scale: 4  # 2, 4, or 8
)
```

### Face Restoration

Specialized enhancement for faces with AI reconstruction.

**Models Used:** GFPGAN, CodeFormer

```ruby
result = MASTER::Postpro.restore_face(
  image_url: "old_photo.jpg"
)
```

### Batch Processing

Process multiple images with a single operation.

```ruby
urls = ["photo1.jpg", "photo2.jpg", "photo3.jpg"]

result = MASTER::Postpro.batch_enhance(
  image_urls: urls,
  operation: :upscale
)
```

## CLI Commands

```bash
$ ./bin/master

# List operations
master> postpro
Postpro Operations:
  upscale - Upscale 4x
  face_restore - Face Restoration

# Upscale an image
master> upscale photo.jpg
🔧 Upscaling image...
✓ Done: https://replicate.delivery/...
```

## Related Plugins

- **[Replicate](../replicate/README.md)** - Low-level model access
- **[Cinematic](../../docs/CINEMATIC_PIPELINE.md)** - Multi-model pipelines

## License

Part of MASTER2. See main repository license (MIT).

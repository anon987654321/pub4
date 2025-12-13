# REPLICATE MODEL CATALOG - December 2025
# Comprehensive database for unprecedented motion graphics chains

## VIDEO GENERATION (10-20 second capable)

### Premium Cinematic (Native Audio)
- **google-deepmind/veo-2** (Dec 2024)
  - Text/image to video, 720p/1080p, up to 8s, physics simulation
  - Cost: ~$0.80, Type: image→video, audio: native
  
- **runway/gen-4-5** (Dec 2025) 
  - Industry top-rated, realistic physics, synchronized audio
  - Cost: ~$0.60, Type: text/image→video, audio: native
  
- **kuaishou/kling-2-6** (Dec 2025)
  - Multi-character dialogue, singing, ambient sounds, 1080p
  - Cost: ~$0.50, Type: text/image→video, audio: native
  
- **luma/ray-2**
  - Fast 9s clips, style transfer, good motion
  - Cost: ~$0.30, Type: text/image→video

### Fast/Affordable
- **alibaba/wan-2-5** (Open source)
  - Background audio, i2v/t2v, rapid output
  - Cost: ~$0.15, Type: text/image→video
  
- **minimax/hailuo** 
  - Realistic character motion, expressive
  - Cost: ~$0.20, Type: text→video
  
- **stability-ai/stable-video-diffusion**
  - Our current model, reliable, no audio
  - Cost: ~$0.10, Type: image→video

## IMAGE GENERATION

### Latest Premium
- **google/imagen-4** (Feb 2025)
  - Sharp visuals, advanced text rendering, watermarking
  - Cost: ~$0.02, Type: text→image
  
- **black-forest-labs/flux-2-pro**
  - Context-aware, high-res, 4K capable
  - Cost: ~$0.04, Type: text→image
  
- **ideogram/v3-turbo**
  - Stunning realism, creative control, text rendering
  - Cost: ~$0.03, Type: text→image

### Fast/Specialized  
- **anon987654321/ra2** (Your custom LoRA)
  - Girlfriend portrait model
  - Cost: ~$0.02, Type: text→image

## UPSCALING & ENHANCEMENT

- **topaz-labs/video-ai**
  - Professional video upscaling
  - Cost: ~$0.15, Type: video→video
  
- **topaz-labs/photo-ai**
  - Image upscaling, restoration
  - Cost: ~$0.05, Type: image→image
  
- **tencentarc/gfpgan**
  - Face restoration, damage repair
  - Cost: ~$0.03, Type: image→image
  
- **sczhou/codeformer**
  - Low-quality image recovery
  - Cost: ~$0.03, Type: image→image

## DEPTH & 3D MODELS

- **marigold-depth**
  - Monocular depth estimation, create depth maps
  - Cost: ~$0.02, Type: image→depth_map
  
- **zoedepth**
  - High-quality depth from single image
  - Cost: ~$0.02, Type: image→depth_map

## RELIGHTING & LIGHTING EFFECTS

- **ic-light**
  - AI relighting, change lighting direction/intensity
  - Cost: ~$0.05, Type: image→image
  
- **controlnet-brightness**
  - Adjust exposure, lighting conditions
  - Cost: ~$0.03, Type: image→image

## MOTION & ANIMATION

- **animate-diff**
  - Animate static images with motion
  - Cost: ~$0.10, Type: image→video
  
- **roop** (face swap)
  - Deepfake face replacement
  - Cost: ~$0.05, Type: image+image→image

## STYLE TRANSFER & EFFECTS

- **bria/erase**
  - Object removal, clean backgrounds
  - Cost: ~$0.02, Type: image→image
  
- **bria/genfill**
  - Generative fill, object addition
  - Cost: ~$0.03, Type: image→image

## AUDIO GENERATION

- **resemble-ai/chatterbox**
  - Natural speech, emotion control, instant cloning
  - Cost: ~$0.10, Type: text→audio
  
- **meta/musicgen**
  - Music generation from text
  - Cost: ~$0.05, Type: text→audio

## CHAIN COMPATIBILITY MATRIX

```
TEXT → IMAGE: imagen-4, flux-2-pro, ideogram-v3, ra2
IMAGE → IMAGE: topaz-photo, gfpgan, codeformer, bria-erase, bria-genfill
IMAGE → VIDEO: veo-2, gen-4-5, kling-2-6, luma-ray-2, wan-2-5, svd
VIDEO → VIDEO: topaz-video
TEXT → VIDEO: runway, kling, hailuo, wan
TEXT → AUDIO: musicgen, chatterbox
```

## EXAMPLE CHAINS FOR 10-20 SECOND VIDEOS

### Chain 1: "Cinematic Portrait Evolution"
```ruby
[:ra2, :gfpgan, :flux-2-pro, :kling-2-6]
# RA2 portrait → face restore → style enhance → 10s video with audio
# Cost: $0.02 + $0.03 + $0.04 + $0.50 = $0.59
```

### Chain 2: "3D Depth Enhanced Motion"  
```ruby
[:ra2, :marigold-depth, :ic-light, :kling-2-6]
# Generate → depth map → relight → animate with depth
# Cost: $0.02 + $0.02 + $0.05 + $0.50 = $0.59
```

### Chain 3: "Ultra HD Motion Graphics"  
```ruby
[:imagen-4, :topaz-photo, :bria-genfill, :veo-2, :topaz-video]
# Generate → upscale 4x → enhance → video → upscale video
# Cost: $0.02 + $0.05 + $0.03 + $0.80 + $0.15 = $1.05
```

### Chain 4: "Music Video Generator"
```ruby
[:flux-2-pro, :kling-2-6, :musicgen]
# Image → video with dialogue → add music layer
# Cost: $0.04 + $0.50 + $0.05 = $0.59
```

### Chain 5: "Chaos Mode" (8-15 models)
```ruby
[
  :ra2,           # Custom portrait
  :marigold,      # Extract depth
  :gfpgan,        # Face restore
  :ic-light,      # Relight dramatically
  :bria-genfill,  # Add elements
  :flux-2-pro,    # Re-render enhanced
  :topaz-photo,   # Upscale
  :ideogram-v3,   # Style transfer
  :kling-2-6,     # Animate 10s with audio
  :musicgen       # Add soundtrack
]
# Cost: ~$0.85
# Result: Unprecedented 10s motion graphic with depth, relighting, audio
```

## IMPLEMENTATION PRIORITIES

1. **Immediate (v11.0)**
   - Add Kling 2.6 (10-20s with native audio)
   - Add Veo-2 (cinematic quality)
   - Add Runway Gen-4.5 (top-rated)
   - Add Topaz upscaling
   - Add MusicGen

2. **Phase 2 (v11.1)**
   - Add style transfer (Bria suite)
   - Add face restoration (GFPGAN)
   - Add Luma Ray-2
   - Add Wan 2.5

3. **Phase 3 (v11.2)**  
   - Add Ideogram v3
   - Add Imagen 4
   - Add Flux 2 Pro
   - Full chaos mode with all 20+ models

## NOTES
- All video models support 10-20s except SVD (max 5s)
- Native audio models: Veo-2, Gen-4.5, Kling 2.6
- For longer videos: Chain multiple video segments
- Budget: Aim for $0.50-$1.00 per chain for quality
- Chaos mode: Random 8-15 models, $0.70-$1.50

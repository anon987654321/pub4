# Cinematic AI Pipeline

## Overview

The Cinematic AI Pipeline transforms MASTER2 into a creative production tool for film-quality image and video transformations. Chain multiple Replicate.com generative AI models to create stunning cinematic effects, color grading, and visual styles.

## Features

- **Pipeline Builder**: Chain 2+ Replicate models in sequence
- **Built-in Presets**: Ready-made cinematic looks (Blade Runner, Wes Anderson, Film Noir, etc.)
- **Custom Presets**: Save and share your own pipeline configurations
- **Discovery Mode**: Generate random pipelines to discover new aesthetics
- **Intermediate Outputs**: Optionally save each pipeline stage

## Quick Start

### Using Built-in Presets

```ruby
# Apply a preset to an image
result = MASTER::Cinematic.apply_preset("input.jpg", "blade-runner")
puts result.value[:final]  # URL or path to output
```

### Building Custom Pipelines

```ruby
# Create a custom pipeline
pipeline = MASTER::Cinematic::Pipeline.new

# Chain models
pipeline.chain('stability-ai/sdxl', { 
  prompt: 'cinematic color grade, teal and orange',
  guidance_scale: 12.0 
})

pipeline.chain('tencentarc/gfpgan', { scale: 2 })
pipeline.chain('nightmareai/real-esrgan', { scale: 4 })

# Execute pipeline
result = pipeline.execute("input.jpg", save_intermediates: true)

if result.ok?
  puts "Final output: #{result.value[:final]}"
  
  # Access intermediate stages
  result.value[:stages].each_with_index do |stage, i|
    puts "Stage #{i}: #{stage[:model]} -> #{stage[:output]}"
  end
end
```

### Saving Custom Presets

```ruby
pipeline = MASTER::Cinematic::Pipeline.new
pipeline.chain('stability-ai/sdxl', { prompt: 'golden hour lighting' })

# Save for reuse
pipeline.save_preset(
  name: 'my-golden-hour',
  description: 'Custom golden hour look with warm tones',
  tags: ['sunset', 'warm']
)

# Load and use later
loaded = MASTER::Cinematic::Pipeline.load('my-golden-hour')
result = loaded.value.execute("photo.jpg")
```

### Discovery Mode

```ruby
# Generate and test random pipelines
result = MASTER::Cinematic.discover_style("input.jpg", samples: 10)

if result.ok?
  top_pipelines = result.value[:discoveries]
  
  top_pipelines.each_with_index do |discovery, i|
    puts "#{i+1}. Score: #{discovery[:score]}"
    puts "   Stages: #{discovery[:pipeline].stages.size}"
    puts "   Output: #{discovery[:result][:final]}"
  end
end
```

## CLI Commands

### List Available Presets

```bash
# From REPL
cinematic list
```

Output:
```
Cinematic Presets
----------------------------------------
  • blade-runner [builtin]
    Cyberpunk aesthetic: neon, rain, cyan/orange split tones

  • wes-anderson [builtin]
    Symmetrical, pastel palette, centered compositions
  
  • my-custom [custom]
    My custom preset
```

### Apply a Preset

```bash
cinematic apply blade-runner input.jpg
```

### Discover New Styles

```bash
cinematic discover input.jpg 20
```

### Build Interactive Pipeline

```bash
cinematic build
```

## Built-in Presets

### Blade Runner
Cyberpunk aesthetic with neon lights, rain-soaked streets, cyan and orange split tones.

```ruby
MASTER::Cinematic.apply_preset("photo.jpg", "blade-runner")
```

### Wes Anderson
Symmetrical composition, pastel palette, whimsical and nostalgic tones.

```ruby
MASTER::Cinematic.apply_preset("photo.jpg", "wes-anderson")
```

### Film Noir
High contrast black and white, dramatic shadows, 1940s detective aesthetic.

```ruby
MASTER::Cinematic.apply_preset("photo.jpg", "noir")
```

### Golden Hour
Warm, soft, glowing light typical of magic hour photography.

```ruby
MASTER::Cinematic.apply_preset("photo.jpg", "golden-hour")
```

### Teal & Orange
Hollywood blockbuster look: teal shadows, orange highlights.

```ruby
MASTER::Cinematic.apply_preset("photo.jpg", "teal-orange")
```

## Custom Preset Format

Presets are stored as YAML files in `data/pipelines/`:

```yaml
---
name: my-preset
description: Custom cinematic look
tags:
  - custom
  - experimental
stages:
  - model: stability-ai/sdxl
    params:
      prompt: "cinematic color grade"
      guidance_scale: 10.0
  - model: tencentarc/gfpgan
    params:
      scale: 2
created_at: '2026-02-10T23:55:00Z'
```

## API Reference

### MASTER::Cinematic

#### `apply_preset(input, preset_name)`
Apply a named preset to an input.

**Parameters:**
- `input` (String): Path or URL to input image/video
- `preset_name` (String): Name of preset to apply

**Returns:** `Result` with final output

#### `list_presets()`
List all available presets (built-in and custom).

**Returns:** `Result` with hash containing `:presets` array

#### `discover_style(input, samples: 10)`
Generate random pipelines and find top aesthetic matches.

**Parameters:**
- `input` (String): Input image/video
- `samples` (Integer): Number of random pipelines to generate

**Returns:** `Result` with `:discoveries` array

### MASTER::Cinematic::Pipeline

#### `new()`
Create a new empty pipeline.

#### `chain(model_id, params = {})`
Add a model to the pipeline.

**Parameters:**
- `model_id` (String): Replicate model ID (e.g., 'stability-ai/sdxl')
- `params` (Hash): Model-specific parameters

**Returns:** `self` for chaining

#### `execute(input, save_intermediates: false)`
Run the pipeline on input.

**Parameters:**
- `input` (String): Input image/video path or URL
- `save_intermediates` (Boolean): Save each stage output to `var/pipeline/`

**Returns:** `Result` with `:final` output and `:stages` array

#### `save_preset(name:, description:, tags: [])`
Save pipeline as reusable preset.

**Parameters:**
- `name` (String): Preset name
- `description` (String): Human-readable description
- `tags` (Array<String>): Categorization tags

**Returns:** `Result` with `:path` to saved file

#### `Pipeline.load(name)`
Load a saved preset by name.

**Parameters:**
- `name` (String): Preset name

**Returns:** `Result` containing loaded `Pipeline` instance

#### `Pipeline.random(length: 5, category: :all)`
Generate a random pipeline.

**Parameters:**
- `length` (Integer): Number of stages
- `category` (Symbol): `:image`, `:video`, `:color`, or `:all`

**Returns:** `Result` containing `Pipeline` instance

## Requirements

- **Replicate API Key**: Set `REPLICATE_API_KEY` environment variable
- **Models**: Requires access to Replicate models (some may need paid plan)

## Examples

### Example 1: Cyberpunk Music Video Frame

```ruby
pipeline = MASTER::Cinematic::Pipeline.new
  .chain('stability-ai/sdxl', {
    prompt: 'cyberpunk city, neon lights, rain, volumetric fog',
    guidance_scale: 13.0,
    num_inference_steps: 40
  })
  .chain('tencentarc/gfpgan', { scale: 2 })
  .chain('nightmareai/real-esrgan', { scale: 4 })

result = pipeline.execute('frame_001.jpg', save_intermediates: true)
```

### Example 2: Vintage Film Look

```ruby
pipeline = MASTER::Cinematic::Pipeline.new
  .chain('stability-ai/sdxl', {
    prompt: '1970s film grain, vintage color, faded',
    strength: 0.6
  })

result = pipeline.execute('modern_photo.jpg')
```

### Example 3: Batch Processing

```ruby
Dir.glob('frames/*.jpg').each do |frame|
  result = MASTER::Cinematic.apply_preset(frame, 'blade-runner')
  
  if result.ok?
    output_name = File.basename(frame, '.jpg') + '_processed.jpg'
    File.write(output_name, result.value[:final])
  end
end
```

## Integration with Weaviate

When Weaviate is available, pipelines are automatically indexed for semantic search:

```ruby
# Search for presets by description
results = MASTER::Weaviate.search_class(
  'Pipeline',
  query: 'warm sunset golden hour',
  limit: 5
)
```

## Future Enhancements

- Video support (frame-by-frame or video models)
- Real-time preview in web UI
- LUT extraction for Premiere/DaVinci Resolve
- Evolutionary algorithms for aesthetic optimization
- Batch processing UI
- Model discovery and automatic chaining

## Credits

Built on top of:
- [Replicate.com](https://replicate.com) - AI model hosting
- MASTER2 Pipeline Architecture
- Weaviate Vector Database (optional)

## License

Part of MASTER2 - see main repository license.

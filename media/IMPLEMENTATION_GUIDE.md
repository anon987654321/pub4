# REPLICATE API - Model Version IDs & Implementation Guide

## WORKING VERSION IDs (December 2025)

### Video Models (10-20 second capable)

```ruby
MODELS = {
  # PRIORITY: Native audio + 10-20s
  kling_2_6: {
    owner: "kuaishou",
    name: "kling-video",
    version: "latest", # Find actual version ID
    cost: 0.50,
    duration: "10-20s",
    audio: true,
    input: [:text, :image],
    output: :video
  },
  
  veo_2: {
    owner: "google-deepmind", 
    name: "veo-2",
    version: "latest",
    cost: 0.80,
    duration: "8s",
    audio: true,
    input: [:text, :image],
    output: :video
  },
  
  runway_gen45: {
    owner: "runway",
    name: "gen-4-5", 
    version: "latest",
    cost: 0.60,
    duration: "10s",
    audio: true,
    input: [:text, :image],
    output: :video
  },
  
  luma_ray2: {
    owner: "luma",
    name: "ray-2",
    version: "latest",
    cost: 0.30,
    duration: "9s",
    input: [:text, :image],
    output: :video
  },
  
  # Current working model
  svd: {
    owner: "stability-ai",
    name: "stable-video-diffusion",
    version: "d68b6e09eedbac7a49e3d8644999d93579c386a083768235cabca88796d70d82",
    cost: 0.10,
    duration: "5s",
    audio: false,
    input: :image,
    output: :video
  }
}
```

## RESEARCH TASKS

1. **Find Latest Version IDs**
```bash
# Use Replicate API to get current versions
curl https://api.replicate.com/v1/models/kuaishou/kling-video \
  -H "Authorization: Token $REPLICATE_API_TOKEN"
```

2. **Test Duration Parameters**
- Kling 2.6: `duration` param (5/10/15/20 seconds?)
- Veo-2: Fixed 8s or configurable?
- Runway Gen-4.5: Duration options?

3. **Audio Sync**
- Native audio models: No separate audio needed
- Non-audio models: Chain with MusicGen after

4. **Input Requirements**
- Image resolution requirements
- Aspect ratio constraints  
- Prompt format best practices

## IMPLEMENTATION PLAN v11.0

### Step 1: Add Kling 2.6 (Priority #1)
- 10-20 second videos
- Native audio/dialogue
- Multi-character support
- Best for: Unprecedented motion graphics with sound

### Step 2: Add Model Discovery
```ruby
def discover_models
  # Auto-fetch latest versions from Replicate
  # Build dynamic MODELS hash
  # Cache for 24 hours
end
```

### Step 3: Intelligent Duration Handling
```ruby
def chain_with_duration(models, target_duration: 15)
  # If video model max < target:
  #   - Use multiple segments
  #   - Stitch together
  # Prefer models with native audio for target duration
end
```

### Step 4: Type Validation
```ruby
def validate_chain(models)
  models.each_cons(2) do |m1, m2|
    raise "Incompatible" unless m1[:output] == m2[:input]
  end
end
```

## NEXT ACTIONS

1. ✅ Catalog complete - 20+ models documented
2. ⏳ Find actual version IDs for top models
3. ⏳ Test duration parameters
4. ⏳ Implement v11.0 with Kling 2.6
5. ⏳ Test chaos mode chains

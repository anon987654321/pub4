# Advanced Prompting Techniques for Replicate.com Image Generation Models

**FLUX 2 and Nano Banana Pro have fundamentally changed AI image generation** by shifting from keyword-stacking to natural language prompting. The biggest breakthrough of 2025: traditional SDXL-style prompts (quality tags, weight syntax, extensive negative prompts) actively hurt results on these new models. Instead, describe what you want conversationally, lead with your subject, and leverage JSON-structured prompts for precise control. Nano Banana Pro—Google's Gemini 3 Pro-based model released November 2025—excels at text rendering and multi-image reasoning, while FLUX 2's **32 billion parameter architecture** with Mistral Small 3.1 text encoder delivers professional cinematography through natural language descriptions alone.

---

## FLUX 2: The natural language prompting revolution

FLUX 2 represents a paradigm shift requiring completely different prompting strategies than its predecessors. The model processes natural language sentences better than comma-separated keywords, and **does not support negative prompts at all**—you must describe what you want, never what to avoid.

### Core prompting structure

The optimal FLUX 2 prompt follows a clear hierarchy: primary subject first, then key features, lighting, environment, and style descriptors last. Prompts between **15-75 words** perform best; verbose descriptions degrade quality. Quality tags like "masterpiece" or "best quality" waste tokens and add nothing.

**Effective template:**
```
"[Primary subject with key details], [action or pose], [lighting description], 
[environment/setting], [camera/lens specification], [style descriptor]"
```

**Professional portrait example:**
```
"Portrait of a woman in her late 30s with auburn hair and freckles, 
subtle confident smile, Rembrandt lighting with soft rim light on shoulders, 
against neutral gray studio backdrop, shot on 85mm f/1.8 lens, 
shallow depth of field, editorial photography"
```

### JSON-structured prompts unlock precision control

FLUX 2 Pro and Dev support structured JSON prompts for programmatic precision—a hidden capability many users overlook. This enables exact color specification via hex codes, precise camera parameters, and multi-layer scene construction.

```json
{
  "scene": "Professional studio portrait",
  "subjects": [{
    "description": "Executive in navy suit, silver hair, confident expression",
    "position": "Center frame, rule of thirds eye placement"
  }],
  "lighting": {
    "key": "Softbox at 45 degrees camera left",
    "fill": "Reflector camera right at 0.5 stop under",
    "rim": "Hair light from above-behind"
  },
  "camera": {
    "lens_mm": 85,
    "aperture": "f/2.8",
    "sensor": "Full frame"
  },
  "color_palette": ["#1B365D", "#C0C0C0", "#F5F5F5"],
  "style": "Corporate editorial, natural skin texture"
}
```

### Multi-reference image editing with FLUX 2 Pro

FLUX 2 Pro accepts up to **8 reference images** (9MP total limit) using the `@` symbol syntax for sophisticated compositions:

```
"Portrait of @image1 wearing the vintage jacket from @image2, 
posed in the location of @image3, with lighting style from @image4"
```

---

## Nano Banana Pro: Google's reasoning-powered image model

**Nano Banana Pro is Google DeepMind's flagship image generation model** built on Gemini 3 Pro, released November 20, 2025. The name originated as an internal Google codename, and the model has accumulated **3.4 million runs** on Replicate in just weeks.

### Unique capabilities that differentiate it

Nano Banana Pro fundamentally differs from diffusion models through its **autoregressive architecture with built-in reasoning**. Key differentiators include:

- **Text rendering excellence**: Industry-leading accuracy for rendering legible text across multiple languages, maintaining pixel-perfect typography even with stylistic variations
- **Reasoning within images**: Can interpret textual information in images, solve problems shown in photos, and create infographics from documents
- **Character consistency**: Processes up to **14 reference images** simultaneously, maintaining consistent appearances of up to 5 people across scenes
- **Real-world knowledge integration**: Connects to Google Search for real-time data (weather, sports scores, recipes) to generate data-driven visualizations
- **4K resolution output**: Professional-grade results at various aspect ratios

### Optimal prompting patterns

Nano Banana responds exceptionally well to conversational, detailed descriptions and even supports markdown formatting for complex requests:

**Multi-edit with markdown:**
```
Transform this photo with the following changes:
- Change the background to a sunset beach scene
- Add realistic sunglasses to the subject
- Adjust lighting to match golden hour
- Keep all facial features and clothing identical
```

**Buzzwords that genuinely improve output:**
```
"Pulitzer Prize-winning cover photo for The New York Times featuring 
[subject description], professional photojournalism, decisive moment"
```

**Complex composition test prompt:**
```
"Create a three-dimensional pancake in the shape of a skull, 
garnished on top with blueberries and maple syrup dripping down 
the contours realistically"
```

### Comparison with competing models

| Capability | Nano Banana Pro | FLUX Kontext Pro | Seedream 4 |
|------------|-----------------|------------------|------------|
| **Text rendering** | Excellent | Good | Moderate |
| **Built-in reasoning** | Gemini 3 Pro | Limited | None |
| **Character consistency** | 5 people, 14 refs | Good | Excellent |
| **Speed** | Fast (~6s) | Fastest (~3s) | Fast |
| **Background editing** | Moderate | Close to original | Best |

---

## Professional cinematography prompting techniques

### Cinema camera and lens specifications

Professional results come from specific camera and lens references that FLUX models understand deeply. **ARRI Alexa** keywords produce the most cinematic results:

```
"Hyperrealistic portrait shot with ARRI Alexa Mini LF, 
ARRI Signature Prime 47mm lens at T1.8, 
cinematic low-key lighting with motivated practical lights, 
shallow depth of field, rich shadow detail, 
natural skin tones with subtle subsurface scattering"
```

**Effective camera keywords by aesthetic:**

| Camera System | Keywords | Visual Characteristics |
|---------------|----------|------------------------|
| ARRI Alexa | `ARRI Alexa Mini LF`, `Alexa 65` | Film-like rolloff, exceptional dynamic range |
| RED | `RED Weapon 8K`, `RED DRAGON sensor` | Ultra-sharp, fine texture detail |
| Panavision | `Panavision anamorphic`, `C-series` | Oval bokeh, horizontal flares |
| Cooke | `Cooke S4/i`, `Speed Panchros` | Warm rendering, soft bokeh |

### Anamorphic lens simulation

Anamorphic aesthetics require specific terminology for the characteristic horizontal flares and oval bokeh:

```
"Wide cinematic movie still, 2.39:1 aspect ratio, 
signature oval anamorphic bokeh with horizontal blue lens flares, 
shot on Atlas Orion 40mm Anamorphic, 
ARRI Alexa Mini LF, moderate contrast, 
film grain texture"
```

### Focal length effects on composition

| Focal Length | Visual Effect | Prompt Usage |
|--------------|---------------|--------------|
| 24mm | Wide environmental context | `"24mm wide angle, environmental portrait"` |
| 35mm | Natural documentary feel | `"35mm lens, natural perspective"` |
| 50mm | Classic, versatile | `"50mm f/1.2, standard portrait"` |
| 85mm | Beautiful compression, bokeh | `"85mm portrait lens, creamy bokeh"` |
| 135mm | Strong subject isolation | `"135mm f/1.8, telephoto compression"` |

---

## Film stock emulation and color science

### Kodak motion picture film stocks

**Kodak Vision3 500T** produces the quintessential Hollywood night look:

```
"Night street scene in rain-slicked Tokyo alley, 
shot on Kodak Vision3 500T 5219, ARRI Alexa, 
tungsten-balanced color science with exceptional latitude, 
neon reflections in puddles, practical lighting from storefronts, 
cinematic film grain, rich shadow detail"
```

**CineStill 800T** for characteristic halation:

```
"Portrait in neon-lit bar, shot on CineStill 800T, 
distinctive red-orange halation around bright light sources, 
tungsten color balance, warm highlights against teal shadows, 
visible film grain, atmospheric mood"
```

### Still photography film emulation

| Film Stock | Keywords | Characteristics |
|------------|----------|-----------------|
| Portra 400 | `"Kodak Portra 400, natural skin tones, soft highlights"` | Warm, fine grain, wedding favorite |
| Ektar 100 | `"Kodak Ektar 100, ultra-fine grain, saturated"` | Vivid colors, landscape use |
| Tri-X | `"Kodak Tri-X 400, high contrast B&W, pronounced grain"` | Classic photojournalism |
| Fuji Pro 400H | `"Fujifilm Pro 400H, soft pastels, natural skin"` | Discontinued cult favorite |
| Ektachrome E100 | `"Kodak Ektachrome, vibrant slide film, cool blues"` | Punchy, saturated |

### Decade-specific aesthetic formulas

**1970s Eastmancolor:**
```
"Street photography, 1970s film aesthetic, warm Eastmancolor tones, 
soft contrast, visible grain structure, faded yellow-orange color cast, 
natural vignetting, nostalgic"
```

**1980s VHS:**
```
"Still frame from VHS tape, neon-lit arcade scene, 
distinct video tracking lines, magenta-cyan color bleed, 
low resolution, scan line artifacts, retro 80s lo-fi aesthetic"
```

**1990s disposable camera:**
```
"Candid party photo, 90s disposable camera aesthetic, 
harsh direct flash, slight overexposure, green-yellow tint, 
snapshot quality, authentic grain"
```

---

## Technical parameter optimization

### CFG scale recommendations by model

The **guidance scale dramatically varies** across model families—using SDXL settings on SD3 or FLUX produces terrible results:

| Model | CFG Range | Sweet Spot | Notes |
|-------|-----------|------------|-------|
| SDXL | 7-10 | 7.5 | Classic stable diffusion range |
| SD3 | 3.5-4.5 | 4.0 | Much lower; high values "burn" images |
| FLUX Dev | 3.5-5 | 3.5 | Below 3.5 fails; above 5 oversaturates |
| FLUX Schnell | 0 | 0 | Distilled model, CFG disabled |
| LCM LoRAs | 0-2 | 1.5 | Outside range produces artifacts |

### Steps optimization

| Model | Recommended | Maximum Useful |
|-------|-------------|----------------|
| SDXL | 20-25 | 50 |
| SD3 | 26-36 | 40 |
| FLUX Dev | 24-32 | 40 |
| FLUX Schnell | 2-4 | 4 |
| SDXL Turbo | 1 | 1 |

### Negative prompting techniques (for compatible models)

FLUX models don't support negative prompts, but for SDXL and SD 1.5, this universal template prevents common artifacts:

```
worst quality, low quality, blurry, jpeg artifacts, watermark, 
text, signature, cropped, bad anatomy, deformed, extra limbs, 
fused fingers, poorly drawn hands, poorly drawn face, 
disfigured, mutation, duplicate
```

**For photorealistic work, add:**
```
cartoon, cg, 3d render, illustration, anime, painting, 
sketch, artwork, oversaturated, overexposed
```

---

## Experimental and avant-garde techniques

### Double exposure compositions

```
"Double exposure cinematic portrait of woman in profile, 
silhouette seamlessly blending with misty forest landscape, 
trees appear to grow from facial contours, 
soft natural backlighting, ethereal mood, 
high contrast black and white, artistic"
```

### Infrared photography simulation

```
"Landscape in infrared photography style, 
bright white foliage against dark sky, Wood Effect, 
false color infrared processing, 
surreal ethereal atmosphere, dreamlike quality"
```

### Glitch aesthetics

```
"Portrait with glitch art aesthetic, 
RGB channel separation, horizontal scan line distortion, 
data moshing effect, corrupted digital artifact, 
cyberpunk color palette, experimental"
```

---

## Workflow combinations and model chaining

### Professional multi-model workflow

The most effective professional workflow chains multiple models:

1. **Ideation**: Generate concepts with Nano Banana Pro (reasoning helps complex scenes)
2. **Refinement**: Edit specific elements with FLUX Kontext Pro
3. **Upscaling**: Enhance to print resolution with Real-ESRGAN or Recraft Crisp Upscale
4. **Final polish**: Face restoration with GFPGAN if needed

### FLUX Kontext editing rules

Critical prompting rules for Kontext that the community has discovered:

- **Never use pronouns**: "The woman with short black hair" not "her"
- **Quotation marks for text**: `Replace "SALE" with "OPEN"`
- **Explicit preservation**: "...while keeping identical facial features and clothing"
- **Start from original**: Don't chain edited images; always edit from source

```
"Change the woman with auburn hair's outfit to a navy blazer 
and white blouse, keep her face, expression, and hair 
exactly the same, maintain the same studio lighting"
```

---

## Key discoveries and hidden features

### Hex color code precision (FLUX 2 exclusive)

```
"Product photography of luxury handbag, 
exact brand color #8B4513, 
background gradient from #F5F5DC to #FFFFFF"
```

### Selfie generation trick

Include smartphone filename references for authentic casual aesthetics:
```
"Candid selfie, IMG_2847.JPG, natural bathroom lighting, 
slight motion blur, amateur quality, 
authentic social media aesthetic"
```

### Material descriptions that work

Physical property descriptions outperform generic quality terms:
- ✅ "Brushed aluminum with subtle anisotropic reflections"
- ❌ "High-quality metal surface"
- ✅ "Weathered copper with green verdigris patina"
- ❌ "Expensive-looking antique metal"

---

## Conclusion: The new prompting paradigm

The shift from keyword-stacking to natural language represents the most significant change in AI image prompting since Stable Diffusion's release. **Three principles define professional results in late 2025:**

First, **describe scenes cinematically**—reference specific cameras, lenses, film stocks, and lighting setups rather than abstract quality terms. Second, **leverage model-specific features**: JSON prompts for FLUX 2 precision, multi-image references for character consistency, and Nano Banana's reasoning for complex compositions. Third, **abandon SDXL-era habits**: quality tags, weight syntax, and extensive negative prompts actively degrade results on modern models.

The most powerful technique remains the simplest: write clear, specific descriptions of exactly what you want to see, structured with subject first and style last, using the technical vocabulary of professional photography and cinematography. The models have evolved to understand natural language—the best prompts read like shot descriptions from a film director, not lists of keywords.
# ME2 LoRA Training Instructions
## Quick Start (Web UI - Easiest)
1. **Prepare training images:**
   - Already have 15 images in `__lora/me2/`

   - Need 10-20 high quality images minimum

2. **Create zip file:**
   ```bash

   cd __lora

   zip -r me2_training.zip me2/*.jpg

   ```

3. **Upload to cloud storage:**
   ```bash

   # Option A: Upload to Replicate directly via their web UI

   # Go to: https://replicate.com/ostris/flux-dev-lora-trainer/train

   # Option B: Use a temporary hosting service
   # Upload me2_training.zip to file.io or similar

   curl -F "file=@me2_training.zip" https://file.io

   ```

4. **Train on Replicate:**
   - Go to: https://replicate.com/ostris/flux-dev-lora-trainer/train

   - **Input images**: Paste the URL to your zip file

   - **Trigger word**: `ME2`

   - **Steps**: 1000-1500 (more steps = better quality)

   - **Learning rate**: 0.0004 (default)

   - **LoRA rank**: 16 (default, higher = more detail)

   - **Autocaption**: Enable

   - **Autocaption prefix**: `ME2 person,`

   - **Resolution**: `512,768,1024`

   - Click **Create training**

5. **Wait 15-30 minutes** for training to complete
6. **Your model will be at:** `anon987654321/me2` (or your username)
## Cost
- ~$10 per training run

- Budget $10-30 for 2-3 iterations to get it perfect

## Using the trained LoRA
```ruby
# Test with repligen

ruby repligen_simple.rb "ME2 woman portrait, beautiful natural lighting"

# Or use directly via API:
require "net/http"

require "json"

res = Net::HTTP.post(
  URI("https://api.replicate.com/v1/predictions"),

  {

    version: "YOUR_TRAINED_MODEL_VERSION",

    input: {

      prompt: "ME2 woman as professional athlete, confident pose",

      aspect_ratio: "16:9"

    }

  }.to_json,

  {

    "Authorization" => "Token #{ENV['REPLICATE_API_TOKEN']}",

    "Content-Type" => "application/json"

  }

)

```

## Tips for Best Results
1. **Image Quality:**
   - Use varied angles and lighting

   - Include close-ups and full body shots

   - Avoid heavy makeup or filters

   - Mix indoor and outdoor shots

2. **Consistency:**
   - Same person throughout

   - Clear, well-lit photos

   - Minimal background clutter

3. **Training Parameters:**
   - Start with 1000 steps

   - If results are too strong/overfit: reduce steps to 500-800

   - If results are too weak: increase to 1500-2000

   - Adjust learning rate between 0.0003-0.0005 for fine-tuning

## After Training
Once complete, use the trigger word `ME2` in all prompts:
- "ME2 woman as beach volleyball athlete"

- "ME2 person in professional sports photography"

- "Beautiful portrait of ME2, cinematic lighting"

The LoRA will work best with natural, realistic prompts similar to the training data.

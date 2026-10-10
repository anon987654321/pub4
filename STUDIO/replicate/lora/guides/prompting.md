# Prompting the models we use

Researched 2026-10-10 from Replicate's model pages and blog, the ai-toolkit repository, the Hugging Face FLUX.1-dev card, Google's Veo guides, Kling's quickstart and the Wan technical report (ar5iv.labs.arxiv.org/abs/2503.20314). A rule marked (inference) or (unverified) is a hypothesis to test with a draft run, not a finding. The pinned live schemas in `_toolkit/video_models.yml` outrank anything here about parameter names.

## FLUX.1-dev person LoRA: training (ostris/flux-dev-lora-trainer)

- Defaults: 1000 steps, learning rate 0.0004, rank 16, batch 1, resolution 512,768,1024, caption dropout 0.05. Replicate says leave steps at 1000 for faces; ai-toolkit's example uses 2000 and calls 500 to 4000 a good range. replicate.com/ostris/flux-dev-lora-trainer/train, replicate.com/blog/fine-tune-flux-with-faces
- Images: at least 10, 12 to 20 recommended, 1024 px or larger, and varied in setting, clothing, light and angle. Real photographs only; stylised or rendered images bake their look in.
- Rank 16 stays until captions are written by hand, because the schema warns caption quality matters more at higher ranks.
- Trigger word: a made-up string, never a real word, and the same in every caption and every prompt. Replicate warns against `TOK`. `ragnhild` and `johann_lora` are names the base model may already know; a nonsense token such as `rgnhld_x` is safer (inference).
- Captions: describe what changes (clothes, place, light, pose) and leave out the face and fixed traits. This is the common community rule and the caption law in `curate.rb`; no authoritative source confirms it. A bare trigger sometimes beat long captions (anecdote).
- JPG, JPEG or PNG only; ai-toolkit reports problems with WebP.
- ai-toolkit saves a checkpoint every 250 steps. If a LoRA looks overcooked, compare an earlier one.
- The `layers_to_optimize_regex` shortcut for likeness is Discord lore and may weaken the LoRA (unverified); we do not use it.

## FLUX.1-dev person LoRA: generation (black-forest-labs/flux-dev-lora)

- `lora_scale` defaults to 1; the schema calls 0 to 1 sane. Raise to 1.2 or 1.3 if the likeness is weak, drop to 0.7 to 0.9 if the skin goes plastic.
- `guidance` defaults to 3, range 0 to 10. Use 2.5 to 3.5 for natural skin; high values give a waxy, burnt look.
- Steps 28 to 50. `go_fast` defaults on (fp8) and is non-deterministic even with a seed; set it false for finals and for any A/B.
- Portrait ratios: 4:5, 2:3, 3:4. Output png for masters; `output_quality` is ignored for png.
- The model is guidance-distilled, so negative prompts do nothing. State what you want instead of what to avoid.
- Write prose, subject first, then action, setting, light and camera. State age and gender and ask for unobscured facial detail. Name a real camera and film, such as "85mm f/1.8, Kodak Portra 400", over "professional photo"; the BFL guide says so for FLUX.2, and it probably carries over. docs.bfl.ai/guides/prompting_guide_flux2
- Skin: "visible pores, natural skin texture, soft window light" in prose helps against the plastic look. Vendor claims, so A/B them.

## Wan 2.2 i2v fast (draft)

- The image fixes the look; the prompt names only what moves. Order: subject action, camera, pace. One action and one camera move. Animate only what is visible.
- The text encoder takes 512 tokens at most, and Wan was trained on long captions (style, content, detail), so a medium prompt of 40 to 80 words beats one line (inference on length).
- The input is the first frame. The face holds best with small motion: a blink, a slight smile, a small head turn.
- The Pruna wrapper hardcodes the negative prompt and fixes guidance, so put constraints in positives: "steady face, natural expression". pruna.support.site/article/wan-i2v-fast
- 81 frames is about 5 s. 480p is the cheap draft; `go_fast` is on by default; set a seed to reproduce a draft.
- Handheld selfie: "handheld selfie camera, slight natural sway, arm's-length framing, looks at the lens, blinks, small smile." Avoid orbits and fast pans (inference).

## Veo 3.1 Fast (final)

- Elements: subject, action, scene, camera movement, lens, light, mood. Describe motion and camera, not looks; the image carries identity. Google says the word "portrait" emphasises facial detail. ai.google.dev/gemini-api/docs/veo
- If the face drifts, cut appearance adjectives or change the first frame. "Same person" wording does not help.
- Durations 4, 6 or 8 s; 1080p needs 8 s. 9:16 is available. Audio is generated; describe sound in its own sentences and put speech in quotes with a speaker. Image-to-video of an adult person may be restricted in EU, UK and CH regions. The Replicate flags for audio off and negative prompt were not verified.
- Say what to avoid as a list of things, not as "no" or "don't".

## Kling v2.1

- Formula: subject plus movement, optionally background plus movement. Keep the movement physically plausible; descriptions far from the image cause a cut. kling.ai/quickstart/image-to-video-guide
- One gesture per clip. 5 or 10 s. A short negative prompt of nouns ("blur, distortion, extra fingers, text") is supported by third parties; the official guide does not mention it. Its schema has no seed, so a draft cannot be reproduced.

## Cross-model default

One subject action, one camera move, one light note, and no appearance words. Draft on Wan with the motion sentence, then run the same sentence on Veo or Kling for the final.

## Not verified

The Replicate trainer's prose readme, the BFL FLUX.1 prompting page, the ar5iv full text of the FLUX paper (so the T5-plus-CLIP encoder claim is background knowledge), and the Replicate input schemas for the video models as the agent could read them. Our own pinned schemas, read on 2026-10-10, are the reference for names and limits.

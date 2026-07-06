# Ragnhild LoRA v2 realism plan

Created: 2026-06-30

## Quick diagnosis

- Current folder: `DEPLOY/tools/repligen/lora/ragnhild`
- Current training set: 18 images, mostly 480x640 or 464x688, plus one 574x1024 selfie.
- Captions are all identical: `a photo of ragnhild`.
- Source pool was 291 extracted frames, but the final curation is `even_sample`, not beauty/identity/quality ranked.
- Local `ai-toolkit` training failed because `black-forest-labs/FLUX.1-dev` is gated and the local environment was not authenticated.
- Replicate v1 did train, destination `basicfeatures/ragnhild`, version `6197a9e142d14f8d8f8e824ea243a2496710240d461bcbc9593a76cbe8c7d5c0`.
- The dataset appears partly derived from generated/video material, so v2 needs more real stills or very careful filtering to avoid a synthetic feedback loop.

## Highest leverage v2 changes

1. Rebuild `train/` from 35-70 manually curated images instead of 18 even-sampled frames.
2. Replace identical captions with descriptive captions that preserve identity and separate changeable attributes.
3. Add 8-15 genuine source photos if available: phone selfies, daylight, imperfect angles, social candids, and non-glamorous reference shots.
4. Split v2 into two adapters if needed: identity LoRA and analog-photo style LoRA.
5. Use Replicate/H200 for the main v2 run, or fix local Hugging Face auth before relying on the MPS path.
6. Generate v2 samples every 150-250 steps and compare identity, skin texture, teeth, eyes, hairline, and expression.
7. Make a small v2 video from a v2 still/keyframe only after the image LoRA passes likeness review.

## Suggested v2 training targets

- Dataset size: 35-70 images.
- Identity stills: 25-45.
- Expression/body/angle coverage: 10-20.
- Beauty/analog references: 8-15, preferably separate style LoRA unless they are actual subject photos.
- Resolution target: keep originals if sharp; avoid upscaling weak frames before training.
- Trigger: keep `ragnhild`, but use captions with `[trigger]` where supported.
- Rank: start 32 for likeness; test 16 and 64 as ablations.
- Steps: start around 1,500-2,500 for 40-60 images, then select checkpoint by visual comparison rather than final step by default.
- Learning rate: start `1e-4`; test `7e-5` if overcooked or `1.5e-4` if underfit.
- Caption dropout: 0.03-0.08.
- Text encoder: usually off for FLUX identity LoRA unless a controlled ablation proves otherwise.

## Caption template

Use captions like:

```text
[trigger], woman, close-up portrait, brown hair, oval face, soft smile, natural skin texture, daylight window light, shallow depth of field, 35mm candid photo
```

Vary the non-identity parts per image: angle, crop, expression, lighting, location, lens feel, clothing, and camera distance. Do not repeat the exact same phrase for every image.

## v2 video snippet recipe

Goal: one short 4-8 second snippet, subtle movement, identity locked, no aggressive morphing.

Recommended flow:

1. Generate 8-12 candidate v2 stills with the LoRA.
2. Pick the closest identity still, preferably a half-body or close portrait with clean eyes and hands out of frame.
3. Run image-to-video with low-to-medium motion.
4. Use analog post-processing lightly: grain, halation, small gate weave, and restrained vignette.
5. Review frame 1, middle frame, and final frame for identity drift.

Example command shape for this repo:

```sh
cd /Users/mac/Documents/GitHub/pub4/MASTER
bundle exec ruby bin/video cinematic \
  --backend kling \
  --lora basicfeatures/ragnhild:<V2_VERSION> \
  --total-minutes 0.1 \
  --chunk-seconds 6 \
  --motion-intensity 0.35 \
  --prompt "ragnhild, woman, intimate analog portrait, daylight through a window, soft natural smile, realistic skin texture, 35mm Kodak Portra look, gentle handheld camera, shallow depth of field"
```

If using ComfyUI/AnimateDiff, prefer 48-81 frames, low motion LoRA weight, and camera phrases like `slow handheld micro push-in`, `subtle breathing`, `hair barely moving`.

## 250 ways to make v2 more realistic, analog, and beautiful

### Source and consent

001. Ask the subject what specifically felt wrong: likeness, age, expression, skin, hair, styling, mood, or beauty standard.
002. Collect 5 favorite real photos from the subject and treat them as the aesthetic north star.
003. Collect 5 rejected outputs and label exactly why each failed.
004. Add real current photos instead of relying on generated frames.
005. Avoid training heavily on synthetic video frames if the complaint is realism.
006. Keep a written consent note for source use and intended generation style.
007. Ask the subject to choose preferred expressions.
008. Ask the subject to choose preferred camera distance.
009. Ask the subject to choose preferred hair presentation.
010. Ask the subject to choose preferred wardrobe boundaries.

### Dataset curation

011. Manually score frames from 1-5 for likeness before adding them.
012. Remove frames with motion blur unless they are beautiful and identity-clear.
013. Remove frames with distorted eyes.
014. Remove frames with warped teeth.
015. Remove frames with plastic skin.
016. Remove frames with asymmetrical AI artifacts.
017. Remove duplicate near-identical video frames.
018. Keep only one frame per micro-expression burst.
019. Balance close-ups with medium portraits.
020. Include one or two full-body shots only if they are sharp.
021. Include left three-quarter face.
022. Include right three-quarter face.
023. Include front-facing face.
024. Include slight downward gaze.
025. Include slight upward gaze.
026. Include neutral expression.
027. Include warm smile.
028. Include candid half-smile.
029. Include serious expression.
030. Include laughing expression if the teeth are correct.
031. Include indoor daylight.
032. Include outdoor shade.
033. Include golden-hour light.
034. Include soft overcast light.
035. Include low-light only if sharp.
036. Remove images with hard flash if not desired.
037. Remove unflattering lens distortion.
038. Prefer 50mm-like perspective for portraits.
039. Prefer 85mm-like perspective for beauty close-ups.
040. Avoid extreme wide-angle selfies unless they are important to likeness.
041. Use crop variants sparingly.
042. Avoid heavy face retouching in source images.
043. Avoid makeup extremes unless subject wants them.
044. Keep hair color consistent if identity is unstable.
045. Include different hairstyles only after the base identity works.
046. Use real camera EXIF photos where possible.
047. Include a few imperfect candid shots.
048. Include real skin texture.
049. Include ears/hairline when available.
050. Include neck and shoulders to anchor anatomy.
051. Avoid training on frames with cut-off chin in most images.
052. Avoid training on images where the face is tiny.
053. Avoid training on images where hands cover face.
054. Avoid sunglasses unless desired.
055. Avoid heavy filters, beauty apps, and face tune.
056. Keep image count high enough for variation but low enough for quality.
057. Create a `rejects/` folder with reasons.
058. Create an `approved/` folder chosen by the subject.
059. Create an `identity_core/` folder of the 12 best likeness images.
060. Create an `aesthetic_support/` folder of analog-style real images.

### Captioning

061. Replace identical captions with image-specific captions.
062. Use `[trigger]` in captions where the trainer supports replacement.
063. Caption face angle.
064. Caption expression.
065. Caption crop.
066. Caption lighting.
067. Caption background.
068. Caption camera distance.
069. Caption lens feeling.
070. Caption analog qualities only when visible.
071. Do not caption changeable clothing as identity.
072. Do not caption temporary makeup as identity.
073. Do not caption background objects as identity.
074. Caption hair only in broad terms if it should remain flexible.
075. Caption eye direction.
076. Caption smile intensity.
077. Caption skin texture neutrally.
078. Caption ethnicity/age only if accurate, consented, and useful.
079. Avoid overloaded keyword soup.
080. Keep captions natural-language for FLUX.
081. Put the trigger early.
082. Use `woman` or an accurate class token consistently.
083. Add `candid photo` where the source is candid.
084. Add `studio portrait` only for studio images.
085. Add `selfie` only for selfie-perspective images.
086. Add `soft daylight` only when present.
087. Avoid `perfect face` in captions.
088. Avoid `AI generated` in captions.
089. Use one caption line per image.
090. Audit captions for accidental contradictions.
091. Keep caption dropout modest.
092. Test shuffle tokens off and on as an ablation.
093. Use a caption prefix on Replicate that matches identity context.
094. Include trigger in the prefix.
095. Avoid training captions that all say only `a photo of ragnhild`.

### Training settings

096. Train rank 16 as a flexible baseline.
097. Train rank 32 as the primary likeness candidate.
098. Train rank 64 only if identity is weak and dataset quality is high.
099. Keep alpha equal to rank for the first pass.
100. Lower learning rate if faces look melted.
101. Lower steps if the LoRA copies training poses.
102. Increase steps if the subject disappears.
103. Save checkpoints every 150-250 steps.
104. Compare checkpoints blind.
105. Use fixed seed prompts for checkpoint comparison.
106. Use a prompt grid across lighting and expression.
107. Use `guidance_scale` around 3-4.5 for FLUX tests.
108. Increase inference steps for weak datasets.
109. Test LoRA strength 0.55.
110. Test LoRA strength 0.7.
111. Test LoRA strength 0.85.
112. Test LoRA strength 1.0 only if needed.
113. Avoid judging from one prompt.
114. Keep text encoder off initially.
115. Test text encoder training only in a separate ablation.
116. Keep EMA if samples are smoother.
117. Test no EMA if identity softens too much.
118. Use bf16/float16 consistently.
119. Avoid local MPS as the source of truth until authenticated and validated.
120. Prefer cloud GPU for final v2.
121. Record exact dataset hash per run.
122. Record exact config per run.
123. Record checkpoint chosen by subject.
124. Use a naming scheme like `ragnhild_v2_rank32_2k`.
125. Keep v1 frozen for comparison.

### Realism prompt craft

126. Prompt for a specific camera body or film stock only lightly.
127. Use `35mm candid photo` for natural realism.
128. Use `medium format portrait` for beauty editorial.
129. Use `Kodak Portra 400` for gentle skin tones.
130. Use `Fuji 400H` for soft pastel greens.
131. Use `Ilford HP5` for black-and-white tests.
132. Use `available light` instead of overproduced lighting.
133. Use `window light`.
134. Use `overcast daylight`.
135. Use `soft shadow detail`.
136. Use `subtle film grain`.
137. Use `halation` sparingly.
138. Use `natural pores`.
139. Use `slight skin texture`.
140. Use `unretouched beauty portrait`.
141. Avoid `hyperreal`.
142. Avoid `perfect symmetrical face`.
143. Avoid `glossy CGI`.
144. Avoid `doll-like`.
145. Avoid `airbrushed`.
146. Avoid heavy makeup unless intentional.
147. Avoid `fashion model` if it changes her face.
148. Prompt the emotional mood clearly.
149. Prompt the location concretely.
150. Prompt the camera distance concretely.
151. Use a negative phrase for plastic skin when backend supports negatives.
152. Use a negative phrase for extra teeth when backend supports negatives.
153. Use a negative phrase for face distortion when backend supports negatives.
154. Keep prompts shorter for identity tests.
155. Use richer prompts only after identity passes.

### Analog photography aesthetics

156. Add real film reference language.
157. Favor soft contrast over crushed blacks.
158. Favor highlight rolloff over HDR.
159. Add slight underexposure tests.
160. Add slight overexposure tests.
161. Add warm daylight tests.
162. Add cool window-light tests.
163. Add color negative film tests.
164. Add black-and-white contact sheet tests.
165. Add editorial crop tests.
166. Add documentary crop tests.
167. Add point-and-shoot flash tests only if subject likes them.
168. Add natural background clutter.
169. Avoid sterile gray backgrounds.
170. Avoid fake bokeh circles.
171. Use shallow depth of field moderately.
172. Keep eyes sharp.
173. Keep face not waxy.
174. Preserve tiny asymmetries.
175. Preserve natural under-eye texture.
176. Preserve flyaway hair.
177. Preserve real fabric texture.
178. Preserve natural lip texture.
179. Avoid excessive sharpening.
180. Avoid denoise-heavy output.
181. Add light grain post-process after generation, not in every caption.
182. Add mild vignette post-process.
183. Add tiny gate weave only for video.
184. Add film-breathing only for video.
185. Keep analog effects subtle enough to pass as camera behavior.

### Beauty and identity review

186. Build a 4x4 identity proof sheet.
187. Build a 4x4 beauty proof sheet.
188. Include v1/v2 side-by-side comparisons.
189. Ask the subject to mark `yes`, `close`, `no`.
190. Ask the subject to mark favorite lighting.
191. Ask the subject to mark favorite expression.
192. Ask the subject to mark least flattering artifacts.
193. Score likeness separately from beauty.
194. Score analog feel separately from likeness.
195. Score realism separately from style.
196. Keep a small rubric: eyes, nose, mouth, face shape, hair, vibe.
197. Do not ship a video before still images pass the rubric.
198. Prefer one excellent image over many okay images.
199. Keep the winning seed and prompt.
200. Keep the losing seeds and failure notes.

### Video snippet

201. Use image-to-video from the best v2 still.
202. Keep duration 4-8 seconds.
203. Keep motion intensity low.
204. Use slow push-in.
205. Use subtle handheld drift.
206. Use natural blinking only if model handles it.
207. Avoid big head turns.
208. Avoid talking mouth motion.
209. Avoid hands entering frame.
210. Avoid hair whipping.
211. Avoid fast camera motion.
212. Avoid background transformations.
213. Test first/middle/last frame for identity drift.
214. Generate 6 candidates and pick one.
215. Use 24 fps for cinematic smoothness.
216. Use 16:9 for cinematic, 4:5 for portrait social.
217. Keep face large enough but not extreme close-up.
218. Use one clear light source.
219. Keep analog post after I2V, not before.
220. Apply light grain.
221. Apply restrained vignette.
222. Apply slight warmth.
223. Apply no sharpening unless needed.
224. Avoid frame interpolation if it warps the face.
225. Export a short MP4 and a contact sheet of sampled frames.

### Pipeline improvements

226. Add a manual curation manifest with score fields.
227. Add a caption audit script.
228. Add duplicate detection for video frames.
229. Add blur detection.
230. Add face-size filtering.
231. Add a `--curation ranked` mode instead of only even sampling.
232. Add a `--max-per-source` cap.
233. Add a `--min-frame-gap` option.
234. Add an `approved_by_subject` flag.
235. Add sample prompt grids to `meta.json`.
236. Add Replicate version history to `meta.json`.
237. Add v1/v2 output folders.
238. Add a Makefile target for `ragnhild-v2-train`.
239. Add a Makefile target for `ragnhild-v2-video`.
240. Add a post-train proof sheet generator.
241. Add ffmpeg frame extraction from generated video.
242. Add automatic side-by-side contact sheets.
243. Add subject feedback notes as structured JSON.
244. Add a local fallback model path for gated FLUX.
245. Add a preflight check for Hugging Face auth.
246. Add a preflight check for Replicate token.
247. Add clear warning when all captions are identical.
248. Add clear warning when dataset is mostly generated frames.
249. Add clear warning when image resolution is below target.
250. Add a final `ship/no-ship` checklist before creating public outputs.

## Research notes

- Replicate's `ostris/flux-dev-lora-trainer` notes that proper-name trigger words work, LoRA rank 16-32 is a good range, rank 64 can help likeness, and weak datasets benefit less from style flexibility.
- `ostris/ai-toolkit` expects paired image/caption files and supports `[trigger]` replacement when `trigger_word` is configured.
- Hugging Face Diffusers describes LoRA as a lightweight adapter method and DreamBooth-style personalization as associating a special word with example images.
- Hugging Face AnimateDiff docs frame image/video animation as a natural next step after image personalization techniques such as DreamBooth and LoRA.

Sources:

- https://replicate.com/ostris/flux-dev-lora-trainer/readme
- https://github.com/ostris/ai-toolkit
- https://github.com/ostris/ai-toolkit/blob/main/notebooks/FLUX_1_dev_LoRA_Training.ipynb
- https://huggingface.co/docs/diffusers/tutorials/using_peft_for_inference
- https://huggingface.co/docs/diffusers/training/dreambooth
- https://huggingface.co/docs/diffusers/api/pipelines/animatediff

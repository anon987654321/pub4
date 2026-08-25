# What makes a photograph good

Research note, 2026-08-25. Written because three STUDIO tools now depend on the
answer and none of them had it written down: **lora** decides what a dataset
should contain, **repligen** decides what to ask a model for, and **postpro**
decides what to do to the result.

The useful finding is that these four layers fail independently, and only one of
them is postpro's to fix. Knowing which is which is the difference between
grading a photograph and trying to grade a mistake.

---

## 1. Geometry — decided before anything else, and postpro cannot touch it

**Focal length does not distort a face. Distance does.** An 85mm lens is not
flattering because of the glass; it is flattering because you have to stand
2–3 m away to fill the frame with a head, and at that distance the nose is not
meaningfully closer to the sensor than the ears. At 40 cm it is, by a large
proportion, and the nose enlarges while the ears recede.

This is why portrait photographers work at 85–135mm, and why 135mm reads as
flatter still: the working distance grows to 3–5 m.

**And it is exactly why selfies look like selfies.** A selfie is an arm's
length. The geometry is fixed by anatomy at roughly 40–70 cm, which is the
distortion range. No lighting, no grade and no retouch removes it, because it
is a projection, not a rendering.

**The opportunity that only exists in generation.** A generated image has no
real camera in it. It can be asked for the *geometry* of a 3 m portrait while
keeping the *framing and gaze* of a selfie — held eye contact, intimate crop,
casual setting. Those two have never been available at once, because in the
physical world the framing implies the distance. This is the single most
specific thing to ask a model for, and it is invisible if you prompt for
"selfie" and let the model reproduce the distortion it learned from millions of
real ones.

Ask for the distance, not the lens.

## 2. Light — shape it at capture; postpro can grade it, not move it

The classical patterns, and what each does to a face:

| pattern | key light | effect |
|---|---|---|
| **butterfly** (Paramount) | above, on-axis | small shadow under the nose that must not reach the lip; the beauty/fashion default; smooths |
| **loop** | ~45° off-axis | small shadow looping beside the nose; the most universally flattering |
| **Rembrandt** | past 45° | nose and cheek shadows meet, leaving a lit triangle on the far cheekbone; moody |
| **split** | 90° | face divided exactly in half; dramatic, cinematic |

Two modifiers that matter more than the pattern:

- **Short lighting** puts the key on the side of the face *away* from camera. It
  slims. **Broad lighting** lights the near side, and widens. Most people want
  short.
- **Catchlights** — the light source reflected in the eye — are what make eyes
  read as alive. Around 10 or 2 o'clock. Their *shape* also tells you the light:
  a round catchlight is a beauty dish or brolly, a rectangle is a softbox, a
  small hard dot is bare flash or sun.

A grade can deepen or lift what the light did. It cannot put a shadow on the
other side of a nose.

## 3. Expression — the layer that decides whether anyone cares

Technique is a floor, not a ceiling. An off expression sinks a technically
perfect frame, and no other layer compensates.

- **The eyes carry it.** They are the connection between subject and viewer, and
  the thing the eye goes to first.
- **People detect a manufactured expression reliably.** A held smile reads as
  held. The recommendation from portrait practice is to shoot *just after* a
  laugh, as the face settles — genuine contentment rather than a performed
  smile.
- **Imperfection reads as truth.** Lines, asymmetry, a scar. The most
  compelling portraits are frequently the least corrected ones.

For a dataset this is a selection criterion, not a technique: choose sources
where the expression is real, because a LoRA trained on held smiles will
generate held smiles.

## 4. The optical signature — this one **is** postpro's, and it is the AI tell

This is why generated portraits look wrong, and it is well-characterised:

- **Skin is too clean.** Models are trained on retouched photography, so they
  reproduce the retouching: no pores, no micro-texture, no blemishes. The result
  reads as wax.
- **Specular highlights are uniform.** A model infers light from caption words
  without any model of how light enters skin. Real skin is translucent — light
  scatters below the surface (subsurface scattering) and comes back warm and
  soft. Rendered skin is opaque, and the highlights sit *on* it identically
  across forehead and cheek.
- **Eye reflections are too perfect**, in the same way and for the same reason.

The result sits in the uncanny valley: not stylised enough to be read as an
image, not correct enough to be read as a photograph.

**postpro is the right tool for precisely this failure**, and it is not a
coincidence — grain, halation, H&D curves and reciprocity are a model of what
film did to light, and what film did to light is the opposite of what a
diffusion model omits. Grain restores micro-texture. Halation restores the
bleed around a specular highlight that a rendered image lacks. An H&D curve
restores the shoulder that makes highlights roll rather than clip.

---

## So: can postpro make a bad photo good?

Honestly, by layer:

| layer | can a grade fix it? |
|---|---|
| 4. optical signature, plastic skin, digital cleanliness | **Yes** — this is what it is for |
| 2. light, as tonality and contrast | **Partly** — it can shape what the light did |
| 1. geometry, perspective distortion | **No** — a projection, not a rendering |
| 3. expression, gesture, moment | **No** |

Plus the ordinary unrecoverables: focus, motion blur, and highlights clipped
with no data behind them.

That split is the useful part. It says get geometry and expression right at
generation — where, unusually, both are *promptable* — and leave the optical
signature to the grade, where there is a real emulation stack already built.

## Two things that are not true yet

- **postpro is stills only.** libvips, and every input glob is
  `jpg/jpeg/png/webp`. "The standard filter on all our photos and videos" is
  currently half of that. Video would want an ffmpeg path — which this tree has
  deep experience of in dilla, so it is a real option rather than a wish.
- **Nothing applies it by default.** repligen's `--postpro PRESET` is opt-in,
  one flag on one command. If the grade is meant to be the house look on
  everything, that is a default and a pipeline, not a flag.

## Sources

Focal length and distance: [DIYP](https://www.diyphotography.net/85mm-portrait-lens-guide/),
[Fstoppers 50/85/135](https://fstoppers.com/gear/50mm-vs-85mm-vs-135mm-ultimate-portrait-lens-comparison-714921),
[Fstoppers on what actually flatters](https://fstoppers.com/gear/right-focal-length-portraits-isnt-what-most-people-think-901135).
Lighting patterns: [Fstoppers](https://fstoppers.com/lighting/getting-started-portrait-lighting-4-classic-patterns-explained-901256),
[SLR Lounge](https://www.slrlounge.com/common-key-light-patterns/),
[Studio Q](https://www.studioqphotography.com/blog/portrportrait-lighting-patterns-butterfly-loop-rembrandt-split-short-broad).
Expression: [Rafal Wegiel](https://www.rafalwegiel.com/rafalwegielblog/the-power-of-facial-expression-in-headshot-photography-a-technical-and-psychological-perspective),
[RMCAD](https://www.rmcad.edu/blog/the-psychology-of-portrait-photography-making-subjects-feel-at-ease/).
The AI tell: [Imagera](https://imagera.ai/blog/fix-ai-skin-plastic-look-2026),
[Morphic](https://morphic.com/resources/how-to/fix-ai-generated-skin-realistic).

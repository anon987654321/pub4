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

## MASTER's law, refitted

`MASTER/data/rules.yml` is 3,947 lines and 228 rules, and none of them can see a
photograph — they are evaluated over source text, and the only image reference
in the whole scanner tree is a payload encoder attaching files to an LLM
request. The single rule that mentions imagery, `ANALOG_WARMTH`, is a
`detect_semantic` question asked of *code* at severity `info`.

But the rules are stated as principles rather than as syntax, and several of
them arrived in software *from* visual design in the first place — Alexander's
centres and levels of scale are architecture, and the squint test is a painter's
trick that graphic design borrowed and code borrowed after that. Refitting them
is closer to returning them than to translating them.

Where a reading below is measurable, the metric that measures it is named.
Where it is not, it says so; a rule that cannot be checked is a principle, not
a gate, and pretending otherwise is the failure this file's neighbours keep
finding.

### Composition

**`STRONG_CENTERS`** — *each module has one clear centre that organises the
whole.* A frame has one subject and everything else is subordinate to it. Two
competing centres is the commonest composition failure and it reads as
restlessness rather than as an error. Not measurable here.

**`LEVELS_OF_SCALE`** — *detail steps smoothly across scales, with no jarring
jumps.* A photograph should resolve at every distance: the silhouette at a
glance, the features at arm's length, the pores and fabric weave up close. A
jump — sharp face, mushy background texture — is what upscaling and heavy
denoise produce, and it is why an AI portrait can look right in a thumbnail and
wrong at full size. Partly measurable: `Uncanny#texture` collapses when the
smallest scale is gone.

**`SQUINT_TEST`** — *structure evident at a glance.* Squint at the frame until
detail disappears. If the subject no longer separates from the background, the
composition depends on detail the viewer will not always have. This is the
original photographic use; software borrowed it.

**`ANTI_DIVITIS`** — *no styling-only wrappers.* Nothing in the frame that is
not doing work. A prop that is there to fill space is a div with no semantics.

**`SURFACE_AREA`** — *minimise the boundary between inside and outside.* Every
element in frame is a thing the viewer must account for. Fewer, larger, deliberate.

### Honesty

**`LEAST_ASTONISHMENT`** — the strongest rule in the file for generated work.
Nothing in the frame should make a viewer stop and count: fingers, teeth,
earrings that differ, a catchlight in one eye and not the other. Astonishment
here is not delight, it is the moment the picture stops being a photograph.

**`DEFINE_ERRORS_OUT`** and **`POKA_YOKE`** — *design so the error cannot arise.*
Perspective distortion is not correctable at any effort, so the fix is to stand
three metres away, where it cannot happen. Blown highlights hold no information,
so the fix is to expose for them. Both are capture-time decisions that make a
post-production failure impossible rather than survivable.

**`PARSE_DONT_VALIDATE`** — *convert untrusted input into a trusted shape once,
at the boundary.* Fix at capture, not in the grade. `rescue.rb` exists to say
which half of a photograph is still negotiable, and its answer is one layer of
four.

### The set

**`DRY`** — two frames of the same moment are one photograph stored twice. This
is the duplicate that cost this project an image: same cap, same dog, same strip
lights, seconds apart. Measurable: perceptual distance between prepared frames.

**`CONSISTENT_ERROR_STRATEGY`** — *one strategy per module.* One grade across a
set, or the set reads as a pile. Exposure normalised to the set's own median
before grading is this rule applied.

**`MAGIC_COLOR`** — *colour references a token, not a raw value.* A grade
references a stock. "Warmer" is a raw hex; `kodak_portra` is a token, and it
carries an H&D curve, a dye matrix and a grain sigma that agree with each other.

### Process

**`CHESTERTONS_FENCE`** — understand why an element is in frame before removing
it. The clutter on the table may be the reason the picture is warm.

**`REVERSIBILITY`** — keep the ungraded original. Every grade in this repo is
applied to a copy for exactly this reason, and the one time a set was graded in
place, the recovery came out of git.

**`DESIGN_IT_TWICE`** — two setups before committing to one. Cheap in
photography and almost free in generation.

**`BROKEN_WINDOWS`** — one visible flaw undermines a frame that is otherwise
right, and viewers find it faster than they find anything you did well.

**`FULL_BY_DEFAULT`** — *defaults are maximal correctness, no fake-choice tiers.*
postpro's `house` runs the whole analog chain with no flag to discover, and the
camera-profile pass is on rather than waiting to be switched on.

**`ANALOG_WARMTH`** — the one rule already written for imagery, and the one this
project disagrees with in part. Its prescription is "film grain, vintage lens
softness, subtle colour cast"; `house` carries the grain and the cast and
deliberately drops the softness, because simulated defocus on a frame that was
already taken through a lens is invention rather than emulation, and softness is
the one artefact nothing downstream can undo. The operator's instruction
outranks the rule (soul > rules > this), and the disagreement is recorded rather
than quietly resolved.

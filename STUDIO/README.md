# STUDIO

Four media tools that share one conviction: **a claim about an image or a sound
is worth nothing until something measures it.**

| Tool | What it is | Contract |
|---|---|---|
| `dilla/` | beat construction — Detroit lean, genre-agnostic in intent | `dilla/README.md` |
| `postpro/` | the house grade: analog photographic emulation for stills and video | `postpro/README.md` |
| `repligen/` | image generation, and long chains of radically different models | `repligen/README.md` |
| `lora/` | person-specific fine-tunes, so a name survives across worlds | `lora/README.md` |

Two documents carry the theory rather than the code: `PHOTOGRAPHY.md` (what
makes a photograph good, in four layers) and `AMBITION.md` (168 proposals, and
which of them are built).

---

## Read this part first

This tree has a dominant defect class, and it is not the one you expect.

**The instrument is wrong more often than the reasoning.** Measurement code
here has been wrong about the code it measures more often than the code has
been wrong about the world. Before believing a finding, check the finding's
source against a case whose answer you already know.

Three from one session, all of which read as correct until checked:

- `POSTPRO_EXPLAIN` reported per-step `avg` and `spread`, and both are nearly
  blind to a gaussian blur. It logged `spread-0.0021` — small enough to ignore —
  for the step that removed 57% of a picture's texture. The grade had been
  destroying photographs for as long as anyone had been running it, and the
  per-step report agreed everything was fine. It measures texture now.
- A dead-effect sweep reported 11 effects that changed nothing. Four were real.
  The probe image was greyscale, which made `desaturate` a legitimate no-op —
  the probe was the confound.
- A reproducibility test compared two readings and failed at the tenth decimal
  on byte-identical output. libvips reduces across threads and the summation
  order is not fixed, so the grade was reproducible and the instrument was not.
  It hashes the file now.

**Inert config and dead wiring.** Declarations with no reader are everywhere:
a `lens:` key named in five presets that no effect read, nine stocks' worth of
hand-tuned colour matrices with zero readers, `fractsurf` called with a `seed:`
argument it does not accept — so grain raised on every call, was rescued to the
input, and *the most-used effect in the file was the one that never ran*. Before
trusting a setting, find its reader. Before adding a fix, consider adding the
gate instead.

**Ruby and zsh, not GNU text tools.** `sed`, `awk`, `find`, `head`, `tail`,
`wc`, `perl` and `python` are banned in shell calls and committed scripts. BSD
variants break GNU idioms and this repo deploys to OpenBSD.

---

## What we know about prompting

Gathered from Black Forest Labs' own guidance and from what the tools measure,
not from folklore.

**Structure: Subject + Action + Style + Context, main element first.** The model
weights the opening of the prompt most heavily. Bury the subject and the subject
competes with the scenery.

**30–80 words.** This is a real ceiling, not a style note. `repligen` compiles a
caller's prompt together with vocabulary fields — subject distance, key side,
catchlight, skin, selfie geometry — and all of them at once reaches 142 words,
nearly double the guidance. Past the ceiling the later fields stop describing
the subject and start competing with it. The vocabularies are a menu, not a
checklist, and `warn_prompt_length` says so at compile time.

**No negative prompts.** FLUX 2 has no negative conditioning. Every capability
entry carries `negative_prompt_key: nil`, and what would have been a negative
is folded into the positive instead — `POSITIVE_SKIN_GUIDANCE` asks for visible
pores and specular variation rather than asking against plastic skin.

**Hex codes beat colour words.** `#8B4513` is a colour; "warm brown" is a
region. The same applies to camera language: name the body, the lens and the
aperture, because those constrain geometry and depth of field in a way that
"cinematic" does not.

**Distance, not focal length, distorts a face.** The single most useful fact in
`PHOTOGRAPHY.md`. A nose looks enlarged because the camera was 40 cm away, not
because the lens was wide — perspective is a function of subject distance alone.
This is why a selfie flatters nobody and why no grade can fix it: it is a
projection, not a rendering. Prompt for the distance you want.

**FLUX 2 does character consistency without training.** `flux-2-max` and
`-pro` take up to 8 reference images, `-flex` 10, `-klein-4b` 5. For "the same
person in a new place", try this before training a LoRA — it is minutes instead
of hours and needs no dataset.

**FLUX 3 exists and cannot be trained on yet.** Launched 2026-07-23 into gated
early access: video and robot-action first, image "in the coming weeks",
open-weight Dev last. There is no FLUX 3 LoRA path. A FLUX.1-dev LoRA is not a
FLUX 2 adapter either — the base generation is a decision, not a setting.

---

## The analog emulation, and how deep it actually goes

`postpro` is not a filter stack with film names on it. Each effect models a
physical mechanism, and the useful consequence is that when one is wrong, the
physics says which way.

**H&D curves per stock.** Density against log exposure, with per-channel offsets
— which is what actually creates a stock's colour cast, as distinct from its
dye crosstalk. Fourteen stocks, each with its own box speed, grain sigma,
sublayer structure and focal-plane offset.

**Grain is a crystal size, not a percentage.** Cell sizes are calibrated at 2K
and scale with image width, so a 600 px thumbnail and a 4K print share an
emulsion rather than sharing a fraction. Silver halide clusters follow a
lognormal distribution, so the field is `exp(gaussian)` blurred at cluster
scale; the shadow-biased envelope puts grain where film puts it. The ISO term is
relative to the stock's *own* box speed — rating a film faster than it is, which
is what pushing means and what pushing costs.

**DIR couplers.** Development byproducts from one dye layer inhibit its
neighbours. This desaturates pure hues and *sharpens* edges — the acutance
effect. Getting this right matters more than it sounds: the implementation built
every output band from a blurred copy of the image, which inverted the sign of
the whole effect and cost 52% of a photograph's micro-detail in one step. The
diffusion belongs to the inhibitor, not to the picture. A layer's own density is
sharp; what reaches it from its neighbours has diffused. Written that way, the
edge effect falls out of the physics instead of being bolted on afterwards.

**Halation runs before the curve**, because it happens in the emulsion — light
passes the dye layers, reflects off the base, and re-exposes from behind.

**Emulsion defocus.** Each dye layer sits at a different depth, so blue (nearest
the lens) is sharpest and red the softest. Stock-specific: `cinestill_800t` has
had its remjet removed and scatters most.

Also modelled: bleach bypass as retained metallic silver, reciprocity failure,
print-film stocks as a separate transfer, orange mask, split grading, lateral
chromatic aberration with longitudinal focus spread, film-transport grain
anisotropy.

### The rule that governs all of it

**The grade must not subtract from what the photograph already has.**

Every preset was tuned against *generated* images, and against those the chain
is purely additive — a render arrives with no micro-texture and no toe, so
defocus costs nothing, the curve has the whole tonal range, and grain is the
entire point. Point the same chain at a real photograph and each of those
becomes a subtraction from something that was already there.

So the subtractive steps scale by what the source arrived with, on by default
and not reachable by a flag. A flat render measures near zero and gets the full
grade unchanged; a photograph measures high and gets the defocus and the curve
backed off, while grain, the stock's colour and the toe still apply. A grade
that damages photographs unless you know to disable it damages photographs.

`uncanny.rb` is how any of this is checkable: four numbers — texture (Laplacian
energy), specular spread, clipping, tonal range. **The number to watch is the
delta, not the value.** If the film emulation is doing what it claims, texture
rises and clipping falls. When it does the opposite, that is a bug report.

`rescue.rb` is the honest half. `PHOTOGRAPHY.md` splits a photograph into four
layers, and a grade can reach exactly one:

| Layer | Reachable? |
|---|---|
| geometry — perspective from shooting too close | **no**, at any effort |
| light — the pattern the key made | partly, as tonality |
| expression — the moment | **no** |
| optical — plastic skin, clipping, cast, digital cleanliness | **yes** |

So `rescue` names what it cannot fix every single time, detected or not. Their
absence from a report would read as their absence from the photograph, and
neither is measurable from pixels. "Reshoot at three metres" is a more useful
answer than a grade that was never going to work.

---

## LoRA, in one screen

A subject LoRA learns **whatever is constant across its training images.** Every
practical rule follows from that one sentence.

- **Never grade a dataset.** The model would learn Portra's grain as part of the
  person's face, welded on and impossible to ask for less of later. A graded set
  looks better in a contact sheet, which is exactly when someone will be tempted.
- **Normalise exposure, because brightness says nothing about a face.** Correct
  toward the set's own median so the correction cannot introduce a centre the
  photographs did not already have.
- **Leave colour variety alone unless it is extreme.** The more the light differs
  between frames, the harder the model works to separate the person from the
  room. Only a cast strong enough to become an attribute of the face is a
  problem. Measure it as a channel *ratio* — levels conflate cast with exposure,
  so a dark frame reads far cleaner than it is.
- **Vary everything else on purpose**: angle, distance, expression, background,
  light. Ten frames of one moment are one example with nine copies.
- **Bucket, do not crop.** Trainers bucket by aspect ratio; centre-cropping a
  1080×1920 phone photograph discards 44% of it and takes the crown of the head
  whenever the subject is not dead centre.
- **One short edge across the set.** A 2048 px image holds four times the
  information of a 1024 px one, and hyperparameters tuned for 1024 turn
  destructive against it. And never train above the source: a 1080p original
  trained at 2048 teaches the upscaler's artefacts and calls them the subject.
- **`autorot` before measuring anything.** A JPEG stores sensor pixels plus an
  orientation tag; viewers apply it, libvips hands back what is stored. Four
  frames in one set were `orientation=6`, measured as landscape, and written into
  the dataset on their side. A LoRA trained on that learns a sideways face.
- **The filename carries no training signal.** ai-toolkit resolves `<stem>.txt`,
  then `default.txt`, then a configured default, then the empty string — it never
  reads the filename. So hashes and readable stems are equally safe, and the
  thing worth checking is that both halves of a pair still agree. A broken pair
  is not an error; it is a silently uncaptioned image, indistinguishable from the
  8% that `caption_dropout_rate` empties on purpose.
- **Edit every caption by hand.** The token is knowable; what is *in* the picture
  is not measurable from pixels, and a guessed caption teaches the wrong word.

---

## Checks

```zsh
cd STUDIO && rbenv exec rake test            # the whole suite
cd STUDIO && rbenv exec rake test:postpro    # one tool
cd STUDIO && rbenv exec rake isolation       # tests that only pass in company
```

Run the smallest check that proves the work, and do not report done without its
output. A guard green over hand-picked tests is unmeasured — run the whole set.

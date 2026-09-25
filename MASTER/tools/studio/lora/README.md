# Person-LoRA

**Dette er ikke et filter lagt over et tilfeldig ansikt.** Det er et forsøk på å
gi deg tilbake deg selv i lys som er snillere — norsk, voksen, varm, ekte — slik
at et bilde kan kjennes som et bedre minne, ikke en fremmed versjon av deg.
Målet er et lite sett portretter som tåler nær blikk: ansiktet ditt først,
stemning og magi etterpå, aldri omvendt.

FLUX.1-dev er valgt fordi den treffer et sjeldent punkt mellom fotorealisme og
kontroll: en stor rectified-flow-transformer som forstår lys, hud, perspektiv og
fotografisk språk bedre enn eldre diffusjonsmodeller, og som faktisk lytter til
prompten i stedet for å levere generisk AI-glatthet. Den er åpen nok til at vi
kan trene en personspesifikk LoRA oppå, sterk nok til at finjustering gir ekte
likhet i stedet for bare stil, og presis nok til at vi kan variere location,
objektiv og filmstock uten at ansiktet faller fra hverandre — det er derfor den
slår raske generalist-generatorer når målet er ett navn, ett ansikt, mange
verdener.

Teknisk sett starter vi med kuraterte referansebilder med tekstcaptions, trener
en lav-rang LoRA-adapter (rank 32) oppå diffusjonsmodellen
`black-forest-labs/FLUX.1-dev` via flow-matching og ai-toolkit, slik at modellen
lærer en personspesifikk representasjon i vektrommet i stedet for å gjette
ansikt fra prompt alene; under trening caches latenter til disk, LoRA-vektene
oppdateres over 1800 steg med AdamW 8-bit og EMA, validering skjer med 12 faste
fotografiske prompts, og hele kjeden styres av Ruby — kun ai-toolkit sin
`run.py` er Python-grensen. Det skiller seg fra generiske bildegeneratorer som
Grok Imagine, GPT-image eller Google Imagen fordi de er generalistiske
tekst-til-bilde-modeller uten persistent, personbundet finjustering: de kan lage
plausible portretter fra beskrivelse, men holder sjelden stabil identitet på
tvers av lys, vinkel, antrekk og stil, og de kan ikke trenes på godkjente
kildebilder med en eksplisitt likeness-sløyfe. Her eies hele kjeden lokalt, kan
reproduseres og forbedres iterativt. Spørsmålet er alltid det samme: er det
Ragnhild? Er det Johann?

## Four train lanes

Same dataset and trigger; pick the lane that fits ops cost.

`--train-kaggle` is free, on a 16 GB T4, capped at 12 hours a session and about
30 a week. `--train-colab` is free on the same T4 and needs no phone
verification. `--train` runs locally on M2 MPS, or over SSH on a rented 24 GB
pod at an hourly rate. `--train-replicate` runs about 1000 steps on a hosted
H100 and charges per run.

Anything after the lane flag goes to that lane: `./lora --train-kaggle
--dry-run --steps 600`.

### Kaggle (`run_train_kaggle.rb`)

Ruby packages the dataset, generates the notebook and its metadata, pushes,
polls and pulls the weights back. The notebook it writes is a shim: install
Ruby, clone pub4 and ai-toolkit, hand back to `./lora --train`. The Python
boundary stays exactly where it is in every other lane.

Two Kaggle limits shape the design. A GPU session is capped at 12 h and the
weekly quota at ~30 h, so an 1800-step run spans sessions — checkpoints ride
between them inside the dataset, and ai-toolkit resumes from the newest one, so
running the lane again continues rather than restarts. And `/kaggle/working` is
capped at 20 GB while FLUX.1-dev is larger than that, so the model cache goes to
`/kaggle/tmp` (~60 GB, discarded at session end) and only the LoRA is written to
the output.

One-time setup on kaggle.com:

1. **API token** — Settings → API → *Create New Token* downloads `kaggle.json`;
   put it at `~/.kaggle/kaggle.json` (`chmod 600`), or export `KAGGLE_USERNAME`
   and `KAGGLE_KEY`. Install the CLI: `pipx install kaggle`.
2. **Phone-verify the account** — Settings → Phone Verification. Without it a
   notebook cannot reach the internet, so the model download and both git
   clones fail.

   This is what kills a run, and it is worth knowing what it looks like, because
   the log does not say "phone verification" anywhere. The
   notebook dies on `socket.gaierror: [Errno -3] Temporary failure in name
   resolution` — DNS, at the first step that reaches the network — and then
   IPython's own traceback formatter crashes while rendering it, so the last 60
   lines of the log are `TypeError: object of type 'NoneType' has no len()`
   inside `ultratb.py` and the real cause is 80 lines further up. Pull the log
   with `kaggle kernels output <owner>/<kernel> -p <dir>` and search for
   `gaierror` rather than reading the tail.
3. **A notebook secret holding the HF token** — the notebook has to exist before
   a secret can be attached to it, so push once (`./lora --train-kaggle
   --async`), open the notebook, then Add-ons → Secrets → attach one. The label
   is free text and Kaggle offers no lookup by value, so tell the lane which one
   to read: `--secret LABEL`, or `LORA_KAGGLE_SECRET` in the environment.
   Defaults to `HF_TOKEN`. The value must be a Hugging Face token that has
   accepted the FLUX.1-dev licence. Push again.

The notebook and dataset are both created private and should stay that way.

### Colab (`run_train_colab.rb`)

There is no API to push to — Colab is a browser — so this writes
`<subject>/colab.ipynb` and prints the URL that opens it. The notebook clones
this repo for the toolkit, takes the captioned dataset from Drive, mounts Drive so a
disconnect costs the session rather than the training, and hands back to
`./lora --train`. `--no-drive` keeps everything in `/content`, which dies with
the runtime.

The clone carries no photographs. Every `dataset/` is ignored by git, so the
notebook looks for the set in `MyDrive/lora/<subject>/dataset` and stops with a
fix line when it is not there.

### Replicate (`run_train_replicate.rb`)

Zips `dataset/`, uploads via the Files API, trains
`ostris/flux-dev-lora-trainer` into a private destination model
(`$user/<subject>-flux`, override with `LORA_REPLICATE_DEST`), polls, and pulls
`output.weights` into `weights/$MODEL/`. Requires `REPLICATE_API_TOKEN`. Async
via `--async` plus `REPLICATE_WEBHOOK_URL`.

A LoRA trained this way is already a hosted model, so `--generate-replicate`
renders on it without a GPU here. Every frame is graded as it lands: postpro
draws a different preset per sitting and writes it to `out/<set>_postpro/`
beside the ungraded render, since a regrade needs the render and a render costs
money where a grade costs seconds. `--grade portrait` fixes one look over the
set and `--grade none` skips it. It pins the version the training wrote into
`weights/$MODEL/replicate_training.json`, renders one sitting at a time into
`out/<set>/`, skips a frame already on disk so a stopped run resumes, and lays
the set out as a contact sheet beside it. Name a prompt set with `--set` and
narrow it with `--only`.

### RunPod

24 GB+ GPU (RTX 4090 / A5000 / L4 / A40), PyTorch 2.x + CUDA 12 template,
50 GB+ disk. `export HF_TOKEN=hf_... SUBJECT=<subject>`, then
`_toolkit/setup_runpod.sh --train`, then `tmux attach -t <subject>`.

## Prompt sets

A prompt set is what a subject is rendered as. Every written sitting lives in
`ideas.yml`, tagged with its brief: `shoots` is fifty sittings of light, `warp`
is the press shoot, and `best` is twenty-four of those named by reference.
`scenarios`, `selfies` and `distance` are drawn by `preprompt/lib/craft.rb`
from its vocabularies, numbered so a sitting is the same on every run, and
each fits CLIP's 77 tokens.

`selfies` keeps what makes a selfie read as one — the framing, the held gaze,
an arm in frame or not — and refuses the geometry. The camera stands two or
three metres back with the lens that holds the crop from there, so the nose is
not enlarged and the ears do not fall away, and the bare word never reaches the
prompt. Each draws an in-between moment rather than a smile, a place, a light
the place can have, and the catchlight that light makes.

`distance` is one plain sitting at six stated camera distances from 0.45 to 5
metres, with the lens widening as the camera closes in so the crop holds. It
states only the number, so it measures what the model does with distance
rather than whether it follows a description of distortion.

## Devices

`LORA_DEVICE` picks a profile in `render_config.rb`, which rewrites the training
YAML rather than keeping a config per machine.

`cuda` runs bf16 with adamw8bit, unquantised, bucketing at 512, 768 and 1024.
`cuda_t4` runs fp16 with adamw8bit, quantised, at 512 only. `mps` runs fp16
with plain adamw, quantised, at 512. `cpu` runs bf16 with adamw, quantised, at
512.

`cuda_t4` is a profile, not a device ai-toolkit knows — it emits `cuda`. Turing
has no bf16 at all, so inheriting the `cuda` dtype there is a hard failure
rather than a slow path, and 16 GB does not hold FLUX.1-dev unquantised.

`cpu` is an escape hatch rather than a lane, and it has a profile of its own for
a specific reason: as an allowed value with no profile it inherited `adamw8bit`,
which is bitsandbytes and CUDA-only, on the one device guaranteed to have no
CUDA. It gets `adamw` and a single bucket now, and it warns, because 1800 CPU
steps of a 12B model is not a run anyone finishes.

## Status

**ragnhild**: a trained FLUX.1-dev LoRA exists. It sits in the private
Replicate model `anon987654321/ragnhild-flux`, and its weights are in
`ragnhild/weights/ragnhild/lora.safetensors`, which git ignores. It learned from
seven captioned photographs with random stems, prepared by `curate.rb` at 1024
on the short edge, over 1000 steps at rank 16. The dataset is ignored too, so
none of those faces are published. Five of the seven are the same flat-lit shot
against a pale wall, and the set is below the ten-to-thirty the guidance asks
for; a wider set is the next likeness gain.

The adapter holds her fringe and her face across all twelve validation lights.
Render it at full strength, since lowering it drops the fringe first, and leave
her age out of the prompt, since the photographs already carry it. The
descriptor in `ragnhild/subject.env` says why.

An earlier 17-image set is gone, along with the 40
source photographs it came from — removed at `b7d47d6b6` because the subject
disliked them and they did not look much like her. `retouched/` and
`weights/` went with them, so the log naming the earlier Replicate run is
gone too. The destination model was `basicfeatures/ragnhild`; the version
hash survives here only as `6197a9e1…`, truncated. If that model is still on
the account it can be recovered with a token — but it was trained on the
photographs that were rejected, so it is the wrong LoRA of the right person.

**johann**: no images at all. `johann/` holds a launcher, `subject.env` and
`train.yaml`, and nothing to train on. Curate twelve to eighteen varied
photos — angles, light, expressions — into `johann/sources/`, caption them, then pick a lane.

The free Kaggle lane exists because the local lane needs hardware this Mac does
not have and Replicate needs money per attempt. A Replicate run of 1000 steps
took fourteen minutes of H100 time.

**Local training on this Mac is not a slow lane, it is a closed one.** The
machine is an M2 with 8 GB of unified memory, shared with the display. A
LoRA run over FLUX.1-dev needs the 12B transformer, T5-XXL at 4.7B, CLIP-L and
the VAE resident at once: about 15.8 GB of weights with the transformer already
quantised to 4-bit, before a single activation, gradient or optimizer state.
Caching the text embeddings once and dropping T5 takes it to roughly 6 GB of
weights on an 8 GB machine, which is why the attempt that was made died in the
Metal compiler rather than merely taking a long time. `LORA_DEVICE=mps` is kept
because the profile is correct for a Mac that has the memory; this one does not.

## Where the base model has moved (surveyed 2026-08-25)

This toolkit trains against **FLUX.1-dev**, via `ostris/flux-dev-lora-trainer`
on the Replicate lane. That is the previous generation. Read this before
finishing a dataset, because two of the three findings change what a dataset is
*for*.

**FLUX 2 trains LoRAs, and the base to train against is a specific one.**
`black-forest-labs/flux-2-klein-9b-base-lora` is the undistilled base, which
Replicate describes as preserving the complete training signal and being the one
intended for LoRA workflows. A LoRA trained on FLUX.1-dev is for FLUX.1-dev; it
is not a FLUX 2 adapter. So the lane choice here is now also a base-generation
choice, and it was not before.

**FLUX 2 does character consistency from reference images with no training at
all.** `flux-2-max` and `flux-2-pro` take up to 8 reference images,
`flux-2-flex` up to 10, `flux-2-klein-4b` up to 5, and hold a character across
a batch. That is the same problem a subject LoRA solves, by a different route,
and it is worth deciding deliberately rather than by inertia:

A subject LoRA costs a curated captioned set and a training run up front and is
then the cheapest per image; multi-reference costs nothing up front and sends
its references with every request. A LoRA gives the strongest control over one
subject across many generations; multi-reference gives strong control with
nothing to retrain when the base moves. A LoRA dataset stays on the machine that
trains it, and references are passed per request and kept nowhere.

The third row is the one that matters most here. The privacy problem this README
already states plainly — that committing a face publishes it, and deleting it
later does not remove it from history — is a property of the *training* route
and not of the *reference* route.

**A single photograph can bootstrap a set.** Replicate's `consistent-character`
takes one image of a person and produces many poses, expressions and lighting
setups, which is their documented answer to having too few real photographs.
That is directly the `johann` case above: three captioned images, needing
twelve to eighteen.

Nothing here is a recommendation to switch. Which base to train against, and
whether to train at all rather than reference, decide what the portraits look
like and what ends up permanently public — both operator calls. What this note
exists to prevent is making them by not noticing they were being made.

Sources: replicate.com/collections/flux, /docs/guides/extend/working-with-loras,
/docs/get-started/fine-tune-with-flux, /blog/fine-tune-flux-with-faces.

## Layout

A directory at this root is either a subject or starts with `_` and is shared
by all of them. `_toolkit/` is the pipeline, and every subject uses the one.
`curate.rb` decides which photographs earn a place and prepares them, and
`heal.rb` removes a mark from skin in the ungraded original before anything
grades it. `render_config.rb` writes the training YAML for the machine in use.
`run_generate.sh` is the dispatcher every `./lora` flag lands in, and
`toolkit.sh` holds the shell helpers it shares. `run_train.sh` trains locally or
on RunPod, which `setup_runpod.sh` provisions. `run_train_colab.rb` writes the
Colab notebook and `colab_session.rb` is what that notebook runs;
`run_train_kaggle.rb` and `kaggle_session.rb` are the same pair for Kaggle.
`run_train_replicate.rb` trains on Replicate and `run_generate_replicate.rb`
renders a prompt set on what it trained. `run_ai_toolkit.rb` is the one place
Python is invoked. `check_hf_flux_access.rb` asks whether the Hugging Face
token is good and the licence accepted. `shoots.rb` picks the sittings,
`judge.rb` refuses a frame worse than a real photograph of the subject against
the numbers in `judge_thresholds.yml`, `contact_sheet.rb` lays frames out as
one sheet, and `postpro_samples.rb` grades generated portraits.

The seed-media lane lives beside the subjects because it has none.
`seed_media.yml` is every photograph the three RAILS apps seed with, as a
prompt. `run_seed_media_colab.rb` generates `seed_media.ipynb`,
`run_seed_media_replicate.rb` is the paid lane that renders each frame once,
grades it and records it in `seed_media_manifest.yml`, and
`install_seed_media.rb` turns rendered frames into graded catalogue entries.

`ideas.yml` holds seventy-four written sittings: fifty in the shoots brief,
sequenced in eight sides, twenty-four in warp, and the best twenty-four named
by reference. `ideas/` keeps five of them rendered and graded. `guides/` holds
narrated walkthroughs that describe a dataset that no longer exists and two
lanes that are ruled out, kept as recordings and not trusted as instructions.

Inside a subject, `lora` is the entry point: a seven-line script that names the
subject and hands to `_toolkit`. `subject.env` says who, in three lines naming
the subject, the model and the trigger. `train.yaml` says how, with the rank,
learning rate, steps and twelve validation prompts; it is edited by hand, and
`render_config.rb` writes a per-machine version without touching it. `dataset/`
is what the model learns from, images with one caption file each under the same
stem. `colab.ipynb` and `contact_sheet.jpg` are generated, so edit their
generators rather than them. Runs leave checkpoints in `weights/`, portraits in
`out/`, scratch in `.cache/` and ai-toolkit's working files in
`dataset/_latent_cache/`, and git ignores all four.

`dataset/` and `out/` must never merge. A graded photograph of Ragnhild is not
the model saying her name back, and if both lived in one directory the first
real generate run would look like success before it was one. The same reason
keeps `train.yaml` authored and `colab.ipynb` generated: editing the notebook
feels faster and is thrown away the next time anything regenerates it.

**`dataset/` is ignored by git, and this repository is public.** A photograph
committed here is published to anyone, and removing it later leaves it in the
history, so no subject's photographs are tracked. The training lanes read the
set from the machine or from Drive instead.

Everything but the three `subject.env` values is shared. Environment knobs are
`LORA_*` for every subject, such as `LORA_DEVICE`, `LORA_LR`, `LORA_STEPS`,
`LORA_PROMPT` and `LORA_FLUX_MODEL`, because the directory already chose the
subject and a knob named after one is not a knob. A `_toolkit/` script run
directly refuses, since it cannot know which subject was meant.

## Commands

One entry point per subject, and `./lora --help` lists the rest. In order
below: the Hugging Face gate, toolkit and dataset check; local or RunPod
training; a sample from the newest checkpoint; check, generate and grade in one
pass; and two Replicate renders, the second a dry run.

```sh
STUDIO/lora/ragnhild/lora --check
STUDIO/lora/ragnhild/lora --train
STUDIO/lora/ragnhild/lora --generate
STUDIO/lora/ragnhild/lora --all
STUDIO/lora/ragnhild/lora --generate-replicate --set selfies
STUDIO/lora/ragnhild/lora --generate-replicate --set distance --dry-run
```

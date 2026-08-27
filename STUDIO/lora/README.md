# Person-LoRA

Dette er ikke et filter lagt over et tilfeldig ansikt. Det er et forsøk på å gi deg tilbake deg selv i lys som er snillere — norsk, voksen, varm, ekte — slik at et bilde kan kjennes som et bedre minne, ikke en fremmed versjon av deg. Målet er et lite sett portretter som tåler nær blikk: ansiktet ditt først, stemning og magi etterpå, aldri omvendt.

FLUX.1-dev er valgt fordi den treffer et sjeldent punkt mellom fotorealisme og kontroll: en stor rectified-flow-transformer som forstår lys, hud, perspektiv og fotografisk språk bedre enn eldre diffusjonsmodeller, og som faktisk lytter til prompten i stedet for å levere generisk AI-glatthet. Den er åpen nok til at vi kan trene en personspesifikk LoRA oppå, sterk nok til at finjustering gir ekte likhet i stedet for bare stil, og presis nok til at vi kan variere location, objektiv og filmstock uten at ansiktet faller fra hverandre — det er derfor den slår raske generalist-generatorer når målet er ett navn, ett ansikt, mange verdener.

Teknisk sett starter vi med kuraterte referansebilder med tekstcaptions, trener en lav-rang LoRA-adapter (rank 32) oppå diffusjonsmodellen `black-forest-labs/FLUX.1-dev` via flow-matching og ai-toolkit, slik at modellen lærer en personspesifikk representasjon i vektrommet i stedet for å gjette ansikt fra prompt alene; under trening caches latenter til disk, LoRA-vektene oppdateres over 1800 steg med AdamW 8-bit og EMA, validering skjer med 12 faste fotografiske prompts, og hele kjeden styres av Ruby — kun ai-toolkit sin `run.py` er Python-grensen. Det skiller seg fra generiske bildegeneratorer som Grok Imagine, GPT-image eller Google Imagen fordi de er generalistiske tekst-til-bilde-modeller uten persistent, personbundet finjustering: de kan lage plausible portretter fra beskrivelse, men holder sjelden stabil identitet på tvers av lys, vinkel, antrekk og stil, og de kan ikke trenes på godkjente kildebilder med en eksplisitt likeness-sløyfe. Her eies hele kjeden lokalt, kan reproduseres og forbedres iterativt. Spørsmålet er alltid det samme: er det Ragnhild? Er det Johann?

## Layout

```
_toolkit/       the pipeline, once, shared by every subject
<subject>/      lora  subject.env  train.yaml  dataset/  sources/  weights/  out/
guides/         narrated walkthroughs (m4a + transcript)
```

A directory at this root either starts with `_` or is a subject. Inside a
subject, `sources/` is raw material, `dataset/` is the curated captioned set
that is the only versioned training input, `weights/` holds checkpoints,
`retouched/` holds postpro passes over source photographs, and `out/` holds
generated portraits and nothing else. `.cache/` is scratch and is not versioned.

That last line is the distinction the whole project turns on: a photograph of
Ragnhild that has been graded is not the model saying her name back. Keeping
them in one directory would make the first real generate run look like it
appended to work the model never did.

**`dataset/` is versioned, and this repo's origin is public.** Twenty captioned
photographs of two named people — 17 of Ragnhild, 3 of Johann — are committed
and published, and that is deliberate rather than an oversight: it is what makes
the Colab lane work without a token, since the notebook clones the
origin. Checked 2026-08-12. The consequence is that adding a photograph here
publishes it, immediately and to anyone, and that removing it later leaves it in
the history. Curate `sources/` freely; treat a `git add` under `dataset/` as
consent to publish that face.

`subject.env` names the three things that differ between one subject and the
next:

```sh
SUBJECT=johann
MODEL=johann_v1
TRIGGER=johann
```

Everything else is shared. Environment knobs are `LORA_*` for every subject
(`LORA_DEVICE`, `LORA_LR`, `LORA_STEPS`, `LORA_PROMPT`, `LORA_FLUX_MODEL`, …):
a knob named after the subject is not a knob, since the subject is already
chosen by which directory you are in. Run a `_toolkit/` script directly and it
refuses, because it cannot know which subject you meant.

## Commands

One entry point per subject. `./lora --help` lists the rest.

```sh
STUDIO/lora/ragnhild/lora --check      # HF gate, toolkit, dataset
STUDIO/lora/ragnhild/lora --train      # local MPS or a RunPod pod
STUDIO/lora/ragnhild/lora --generate   # sample from the newest checkpoint
STUDIO/lora/ragnhild/lora --all        # check, generate, postpro
```

## Four train lanes

Same dataset and trigger; pick the lane that fits ops cost.

| Lane | Command | Hardware | Cost |
|------|---------|----------|------|
| **Kaggle** | `./lora --train-kaggle` | 16 GB T4, 12 h/session, ~30 h/week | free |
| **Colab** | `./lora --train-colab` | 16 GB T4, no phone verification | free |
| **Local / RunPod** | `./lora --train` | M2 MPS, or a 24 GB+ pod over SSH | pod hourly |
| **Replicate** | `./lora --train-replicate` | hosted H100, ~1000 steps | per run |

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
this repo for the toolkit and the captioned dataset, mounts Drive so a
disconnect costs the session rather than the training, and hands back to
`./lora --train`. `--no-drive` keeps everything in `/content`, which dies with
the runtime.

**The clone is the reason this lane needs no token and the reason to think
before using it:** `PUB4_REPO` defaults to the public pub4 origin, so the
dataset it pulls is whatever captioned photographs are committed there.

### Replicate (`run_train_replicate.rb`)

Zips `dataset/`, uploads via the Files API, trains
`ostris/flux-dev-lora-trainer` into a private destination model
(`$user/<subject>-flux`, override with `LORA_REPLICATE_DEST`), polls, and pulls
`output.weights` into `weights/$MODEL/`. Requires `REPLICATE_API_TOKEN`. Async
via `--async` plus `REPLICATE_WEBHOOK_URL`.

### RunPod

24 GB+ GPU (RTX 4090 / A5000 / L4 / A40), PyTorch 2.x + CUDA 12 template,
50 GB+ disk. `export HF_TOKEN=hf_... SUBJECT=<subject>`, then
`_toolkit/setup_runpod.sh --train`, then `tmux attach -t <subject>`.

## Devices

`LORA_DEVICE` picks a profile in `render_config.rb`, which rewrites the training
YAML rather than keeping a config per machine.

| Device | dtype | optimizer | quantize | buckets |
|--------|-------|-----------|----------|---------|
| `cuda` | bf16 | adamw8bit | no | 512/768/1024 |
| `cuda_t4` | fp16 | adamw8bit | yes | 512 |
| `mps` | fp16 | adamw | yes | 512 |
| `cpu` | bf16 | adamw | yes | 512 |

`cuda_t4` is a profile, not a device ai-toolkit knows — it emits `cuda`. Turing
has no bf16 at all, so inheriting the `cuda` dtype there is a hard failure
rather than a slow path, and 16 GB will not hold FLUX.1-dev unquantised.

`cpu` is an escape hatch, not a lane: it was an allowed value with no profile
at all until 2026-08-11, which meant it inherited `adamw8bit` — bitsandbytes,
CUDA-only — on the one device guaranteed not to have CUDA. It now gets `adamw`
and a single bucket, and warns, because 1800 CPU steps of a 12B model is not a
run anyone finishes.

## Status

- **ragnhild**: 8 images in `dataset_1024/`, 1024 on the short edge with every
  original aspect ratio kept, built by `curate.rb`. No `.safetensors`. The
  captions are STUBS — `ragnhild, woman, ` and nothing after it — and want
  editing by hand before any run; a guessed caption teaches the wrong word.

  The set is at the bottom of the 10-30 the guidance asks for, and two of the
  eight are arguable: `07` and `08` are the same moment seconds apart, which
  trains one example twice, and `11` has a filter already baked in that a LoRA
  would learn as part of her face.

  The 17-image set this section used to describe is gone, along with the 40
  source photographs it came from — removed at `b7d47d6b6` because the subject
  disliked them and they did not look much like her. `retouched/` and
  `weights/` went with them, so the log naming the earlier Replicate run is
  gone too. The destination model was `basicfeatures/ragnhild`; the version
  hash survives here only as `6197a9e1…`, truncated. If that model is still on
  the account it can be recovered with a token — but it was trained on the
  photographs that were rejected, so it is the wrong LoRA of the right person.
- **johann**: no images at all. `johann/` holds a launcher, `subject.env` and
  `train.yaml`, and nothing to train on. Curate 12-18 varied photos (angles,
  light, expressions) into `johann/sources/`, caption them, then pick a lane.

The free Kaggle lane exists because neither of the other two has produced FLUX
weights: one needs hardware this Mac does not have, the other needs money per
attempt.

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

| | subject LoRA | FLUX 2 multi-reference |
|---|---|---|
| up-front cost | a curated captioned set, then a training run | none |
| per-image cost | cheapest once trained | references sent every request |
| the dataset | committed, and permanent in git history | passed per request, committed nowhere |
| control | strongest for one subject, many generations | strong, and nothing to retrain when the base moves |

The third row is the one that matters most here. The privacy problem this README
already states plainly — that committing a face publishes it, and deleting it
later does not remove it from history — is a property of the *training* route
and not of the *reference* route.

**A single photograph can bootstrap a set.** Replicate's `consistent-character`
takes one image of a person and produces many poses, expressions and lighting
setups, which is their documented answer to having too few real photographs.
That is directly the `johann` case above: 3 captioned images, needing 12-18.

Nothing here is a recommendation to switch. Which base to train against, and
whether to train at all rather than reference, decide what the portraits look
like and what ends up permanently public — both operator calls. What this note
exists to prevent is making them by not noticing they were being made.

Sources: replicate.com/collections/flux, /docs/guides/extend/working-with-loras,
/docs/get-started/fine-tune-with-flux, /blog/fine-tune-flux-with-faces.

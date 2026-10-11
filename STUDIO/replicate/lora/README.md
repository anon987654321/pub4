# Person-LoRA

**This is not a filter laid over a stranger's face. It is an attempt to hand a person back
to themselves in kinder light, so that a photograph can feel like a better memory and not
like a foreign version of you.** The aim is a small set of portraits that survive a close
look: the face first, the mood and the magic after, never the other way round. The question
is always the same one. Is that Ragnhild? Is that Johann?

The tool trains a low-rank adapter on a few captioned photographs of one person, over
`black-forest-labs/FLUX.1-dev`, then renders that person in any light, place and film stock
the prompt names. FLUX.1-dev was chosen because it is open enough to take a subject adapter,
strong enough that the adapter learns a likeness and not only a style, and attentive to the
prompt. The whole chain is Ruby. The one Python call lives in `_toolkit/run_ai_toolkit.rb`,
which starts ostris's ai-toolkit and nothing else.

## Using the system

Start with `./lora.rb --status`. It reads files only, needs no credentials, and prints one
block per subject: how many images the dataset holds, whether a trained version exists, how
many billed seconds the ledger shows, and the one thing that blocks the next step. A subject
is any directory beside it that holds an executable named `lora`; today those are ragnhild
and johann. Run the status command first and again after every stage, because it is the
cheapest way to know where you are.

The order of work is fixed, because each stage spends more than the one before it. First
comes the dataset. Put twelve to eighteen varied photographs of one person into
`<subject>/sources/`, in different light, angles and expressions, and run `--prepare`. It
judges each photograph for resolution, sharpness and blown highlights, spreads the pick so
that ten frames of one moment count once, and prints a report without writing anything. Add
`--write` and it creates `<subject>/dataset/` with 1024-pixel copies, each paired with a stub
caption that holds only the trigger word. Completing the stubs is left to a person. A caption
names what varies, such as pose, clothing, light and setting, and never the face, the natural
hair colour, the eye colour or the age, which belong to the trigger word.

Second comes the dry run. `--train-replicate --dry-run` runs preflight, which checks the set
against those rules, zips the dataset and prints a cost estimate. It uploads nothing and
calls nothing. Preflight wants at least ten images, none under 512 pixels on the short edge,
no age in a caption, a trigger that is neither `TOK` nor an English word, and no frame that
is a near copy of another. A problem stops a real run, and `--force` overrides that when you
have judged the problem acceptable. The estimate gives two figures because the sources
disagree: Replicate's guide says a thousand steps takes about two minutes, and the one run
logged here took fourteen. The sidecar records the seconds Replicate actually billed.

Third comes training, the first paid step. `--train-replicate` uploads the zip, pins the
trainer version, trains `ostris/flux-dev-lora-trainer` into a private model, and writes
`weights/<model>/replicate_training.json` with the trained version, the dataset hash and the
exact trainer input. For a long run add `--async` and collect it later with `--resume ID`;
`--cancel ID` stops a run that is going wrong. Every training appends its seconds to
`<subject>/out/ledger.jsonl`.

Fourth comes rendering. Begin with `--generate-replicate --draft --set selfies`, which
renders cheaply into `out/selfies_draft/` and skips the grade, so you can choose seeds and
prompts without paying for finals. Then render the finals without `--draft`. Each frame is
pinned to the trained version and saved the moment it arrives, because Replicate deletes API
outputs after an hour. Postpro grades it into `out/<set>_postpro/` beside the ungraded
render, since a regrade needs the render and a render costs money where a grade costs
seconds. A different preset is drawn per sitting; `--grade portrait` fixes one look and
`--grade none` skips the grade. Set a spending ceiling with `--max-seconds N` or
`LORA_MAX_SECONDS`, and the run stops when the ledger reaches it. A frame already on disk is
skipped, so a stopped run resumes. Name a prompt set with `--set` and narrow it with `--only`.

Fifth comes the clip. `--video-replicate` takes one approved still as the first frame, so the
trained adapter keeps the face and the video model only moves it. Run `--dry-run` first to see
the model, its pinned version and the exact input. The preset `draft` is a cheap look at
motion from Wan 2.2, to settle the prompt and the seed. The preset `final` is Veo 3.1 Fast,
and `kling` is Kling 2.1 for a second opinion. Presets, versions and quirks live in
`_toolkit/video_models.yml`, and the input keys are checked against the model's live schema
before anything is spent. Each clip's billed seconds join the same ledger as the stills. A
clip with two people needs a first frame with both in it, because two adapters do not combine
in one render. Stills of a scene with no trained face go through
`STUDIO/replicate/replicate.rb`, which already carries the other image models.

## Four train lanes

The dataset and the trigger are the same on every lane; pick the one that fits the cost.
`--train-replicate` is the provider-billed hosted lane. `--train-kaggle` is a free GPU lane
that depends on Kaggle's current quota. `--train-colab` is a free accelerated runtime that
depends on Colab's limits. `--train` runs locally on Apple silicon or, through
`_toolkit/setup_runpod.sh`, on a rented pod with 24 GB or more of GPU memory. Neither free
lane is load-bearing: checkpoints are resumable, and a run may need another lane. Anything
after the lane flag goes to that lane.

Local training on the Mac is a closed lane, not a slow one. The machine has 8 GB of unified
memory shared with the display, and the FLUX.1-dev transformer, its T5 encoder, CLIP and the
VAE need about 16 GB of weights even with the transformer quantised. The profile stays
because it is correct for a Mac that has the memory.

Kaggle is driven from Ruby. `run_train_kaggle.rb` packages the dataset, writes a notebook that
only installs Ruby, clones the repository and hands back to `./lora --train`, then pushes,
polls and pulls the weights. A session is capped at twelve hours and the weekly quota is
around thirty, so an 1800-step run spans sessions; checkpoints ride inside the dataset and
the next run resumes from the newest. The account must be phone-verified, or the notebook has
no network and dies on a DNS error that the log buries eighty lines above its last line. The
Hugging Face token must be attached as a notebook secret, named by `--secret` or
`LORA_KAGGLE_SECRET`, and that account must have accepted the FLUX.1-dev licence.
`check_hf_flux_access.rb` asks whether the token and the licence are good.

Colab has no push API, so `run_train_colab.rb` writes `<subject>/colab.ipynb` and prints the
URL that opens it. The notebook takes the dataset from Drive, mounts Drive so a disconnect
costs the session and not the training, and hands back to `./lora --train`. The repository
clone carries no photographs, because every `dataset/` is ignored by git.

## Prompt sets

A prompt set is what a subject is rendered as. `ideas.yml` holds the written sittings: a
`sets` table, seventy-four `ideas` and twenty-four named under `best`. The `shoots` brief
is fifty of them, `warp` is the press shoot, and `best` names the strongest by reference.
The sets `scenarios`, `selfies` and `distance` are drawn by `replicate/craft.rb` from its
vocabularies, numbered so a sitting is the same on every run, and each fits CLIP's 77 tokens.

The selfies keep what makes a selfie read as one, which is the framing, the held gaze and
the arm, and refuse the geometry. The camera stands two or three metres back with the lens
that holds the crop from there, so the nose is not enlarged, and the bare word never reaches
the prompt. The `distance` set is one plain sitting at six stated distances, with the lens
widening as the camera closes in, and it measures what the model does with distance alone.

## Devices

`LORA_DEVICE` picks a profile in `_toolkit/render_config.rb`, which rewrites the training
YAML and keeps no config per machine. The allowed values are `mps`, `cuda`, `cuda_t4` and
`cpu`, and the default is `mps`. The `cuda_t4` profile is not a device ai-toolkit knows; it
emits `cuda` with fp16 and quantisation, because Turing has no bf16 and 16 GB does not hold
the model unquantised. The `cpu` profile is an escape hatch that warns, since nobody finishes
1800 CPU steps of a twelve-billion-parameter model.

## Where things stand

The two subjects are ragnhild and johann, and both hold only a few photographs. At the last
count ragnhild had nine sources and three prepared dataset images, and johann had eight
sources and five. The preflight minimum is ten, so neither set is ready for a paid run, and
the status command is the way to confirm it. Ragnhild keeps an earlier SDXL adapter under
`weights/ragnhild_legacy_sdxl/` and a record of a Kaggle run under `weights/ragnhild_v2/`.
Her `subject.env` explains why her age stays out of the prompt: the photographs already
carry it, and naming it doubles the ageing. Render her at full strength, because lowering
the scale drops the fringe first.

The base model has moved. FLUX.1-dev is the previous generation, and an adapter trained on
it is not a FLUX 2 adapter. The FLUX 2 models also hold a character from up to eight
reference images with no training at all. Which base to train against, and whether to train
rather than pass references, decide what the portraits look like and what stays permanently
on disk, so both stay operator decisions.

## Layout

A directory here is either a subject or starts with an underscore and is shared. `_toolkit/`
is the pipeline. `curate.rb` decides which photographs earn a place and prepares them, and
`heal.rb` removes a mark from skin in the ungraded original before anything grades it.
`preflight.rb` guards every paid run, `judge.rb` refuses a frame worse than a real photograph
of the subject against `judge_thresholds.yml`, and `shoots.rb` picks the sittings.
`contact_sheet.rb` lays frames out as one sheet, and `postpro_samples.rb` grades generated
portraits. The `run_generate.sh` script is the dispatcher every `./lora` flag lands in, and
`toolkit.sh` holds the shell helpers it shares. The `run_train_*.rb` and `run_generate_*.rb`
scripts hold the lanes, and the `*_session.rb` files are what the Kaggle and Colab notebooks
run. The `guides/` folder holds narrated walkthroughs and a prompting note, kept as
recordings and not trusted as instructions.

The seed-media lane lives beside the subjects because it has none. `seed_media.yml` is every
photograph the RAILS apps seed with, written as a prompt. `run_seed_media_colab.rb` makes
`seed_media.ipynb`, `run_seed_media_replicate.rb` renders each frame once, grades it and
records it in `seed_media_manifest.yml`, and `install_seed_media.rb` turns rendered frames
into catalogue entries. The `ideas/` folder keeps five sittings rendered and graded, and has
its own note.

Inside a subject, `lora` is a short shell script that names the subject and hands to
`_toolkit/run_generate.sh`. The file `subject.env` holds the subject, the model name and the
trigger. The file `train.yaml` is the hand-edited recipe, and `colab.ipynb` is generated, so
edit its generator and not the notebook. Runs leave checkpoints in `weights/`, portraits in
`out/` and scratch in `.cache/`. The `dataset/` and `out/` directories never merge, because
a graded photograph of a person is not the model saying that person's name back.

**The `dataset/` directory is ignored by git, and this repository is public.** A photograph
committed here is published, and removing it later leaves it in the history, so no subject's
photographs are tracked. Everything but the three `subject.env` values is shared, and the
environment knobs are `LORA_*` for every subject. A `_toolkit/` script run directly refuses,
since it cannot know which subject was meant.

## Trust and MASTER

Every image, prompt, archive, model identifier, provider response and remote URL is untrusted
data. Tokens never enter prompts, metadata, tracked files or logged command lines. Downloads
are bounded and checked, provider calls carry timeouts, and each artifact is recorded with
its model version, dataset hash, seed and resolved settings. Provider drift and missing
credentials are explicit failures, never inferred passes.

MASTER speaks to this tool in plain language. Saying "generate me a selfie", "train a lora of
ragnhild" or "lora status" to `MASTER/bin/master` reaches `lora.rb` through
`MASTER/lib/io/lora_intent.rb`. The phrases, the people and the spending rule are data in
`MASTER/data/lora.yml`. Anything that spends money runs as a dry run until the same sentence
also says "confirm" or "go ahead", and a sentence that names two people for a video is
refused.

## Commands

Run these from `STUDIO/replicate/lora`. The `--help` flag lists the rest.

```sh
./lora.rb --status
ragnhild/lora --prepare
ragnhild/lora --prepare --write
ragnhild/lora --train-replicate --dry-run
ragnhild/lora --train-replicate --async
ragnhild/lora --train-replicate --resume TRAINING_ID
ragnhild/lora --generate-replicate --set selfies --draft
ragnhild/lora --generate-replicate --set selfies --max-seconds 600
ragnhild/lora --video-replicate --image out/selfies/07.jpg --prompt "she turns" --dry-run
```

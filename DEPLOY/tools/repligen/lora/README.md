# Character & style LoRA datasets (repligen)

One folder per subject under `lora/<name>/`.

## Layout

```
lora/<name>/
  meta.json       trigger word, counts, relative source paths
  sources/        immutable originals (photos, videos)
  train/          canonical 12–18 images + .txt captions (all trainers use this)
  exports/        replicate.zip — upload bundle for ostris/flux-dev-lora-trainer
  config/         ai_toolkit.yaml, run_local.sh
  weights/        output .safetensors after training
  .cache/         regeneratable (frame splits) — safe to delete
```

## Commands

```sh
# MASTER — refresh train/ from sources/
cd MASTER
bundle exec ruby bin/video lora-train --name ragnhild --local \
  ../DEPLOY/tools/repligen/lora/ragnhild/sources/*

# Replicate
ruby DEPLOY/tools/repligen.rb lora_chaos \
  DEPLOY/tools/repligen/lora/ragnhild/train YOUR_USER/ragnhild ragnhild

# Local ai-toolkit
sh DEPLOY/tools/repligen/lora/ragnhild/config/run_local.sh

# Ragnhild v2 realism workflow
make -C DEPLOY/tools/repligen/lora/ragnhild v2-prepare
make -C DEPLOY/tools/repligen/lora/ragnhild v2-local
make -C DEPLOY/tools/repligen/lora/ragnhild v2-video V2_VERSION=<replicate-version>
make -C DEPLOY/tools/repligen/lora/ragnhild v2-commercial V2_VERSION=<replicate-version> SECONDS=36
make -C DEPLOY/tools/repligen/lora/ragnhild v2-infomercial V2_VERSION=<replicate-version> SECONDS=40
```

## v2 realism defaults

The current `bin/video lora-train` path defaults to ranked curation, descriptive
caption sidecars, low-motion video-friendly prompts, and warnings for weak
captioning, low-resolution frames, and oversized synthetic frame sets. For
character likeness, start with `--max-images 35..70`, `--rank 32`, `--steps
1500..2500`, `--max-per-source`, and `--min-frame-gap` rather than feeding every
video frame into the trainer.

## 30-40 second generated commercials

`MASTER/bin/video` can now generate exact-duration multi-scene ads:

```sh
cd MASTER
bundle exec ruby bin/video \
  --backend kling \
  --seconds 36 \
  --chunk-seconds 8 \
  --format commercial \
  --grade commercial \
  --aspect 16:9 \
  --fps 24 \
  --lora basicfeatures/ragnhild:<V2_VERSION> \
  "ragnhild, woman, premium analog beauty commercial, natural confidence, soft daylight, realistic skin texture"
```

Formats: `commercial`, `infomercial`, `editorial`, `cinematic`.
Grades: `commercial`, `infomercial`, `beauty`, `analog`, `cinematic`.
Each final render writes a matching `.json` manifest with scene prompts, chunk
paths, duration, aspect ratio, format, and grade settings.

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
  ../DEPLOY/repligen/lora/ragnhild/sources/*

# Replicate
ruby DEPLOY/repligen.rb lora_chaos \
  DEPLOY/repligen/lora/ragnhild/train YOUR_USER/ragnhild ragnhild

# Local ai-toolkit
sh DEPLOY/repligen/lora/ragnhild/config/run_local.sh
```
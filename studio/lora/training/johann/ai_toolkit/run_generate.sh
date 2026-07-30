#!/bin/sh
set -eu

. "$(dirname -- "$0")/lib.sh"

mode="all"
skip_postpro=0

usage() {
  cat <<'EOF'
Usage: run_generate.sh [--check | --train | --train-replicate | --generate | --postpro | --all]

  --check            HF FLUX gate, toolkit, dataset
  --train            Train LoRA locally / RunPod via ai-toolkit
  --train-replicate  Zip dataset, train on Replicate (ostris/flux-dev-lora-trainer),
                     pull weights into weights/johann_v1/
  --generate         Sample from latest checkpoint, sync, optional postpro
  --postpro          Portrait postpro on generated samples in lora/
  --all              check, generate, postpro (default)

Deliverables: lora/
Weights:       training/johann/ai_toolkit/weights/johann_v1/

Environment:
  HF_TOKEN, HUGGINGFACE_HUB_TOKEN, AI_TOOLKIT_ROOT
  JOHANN_DEVICE=mps|cuda|cpu   (default mps; use cuda on GPU VPS)
  JOHANN_LOW_VRAM=0|1          (optional; cuda defaults to 0)
  JOHANN_FLUX_MODEL_PATH, JOHANN_SKIP_POSTPRO=1
  REPLICATE_API_TOKEN            (for --train-replicate)
  JOHANN_REPLICATE_DEST=owner/name   (default: $user/johann-flux)
  JOHANN_TRIGGER=johann
  JOHANN_REPLICATE_STEPS=1000
  JOHANN_REPLICATE_LORA_RANK=16
  REPLICATE_WEBHOOK_URL          (optional async notify)

Dual-track train:
  A) RunPod/local:  ./run_generate.sh --train
  B) Replicate API: ./run_generate.sh --train-replicate
     dry-run:       ./run_train_replicate.sh --dry-run

RunPod (24GB+ GPU — RTX 4090 / A5000 / L4):
  1. Create pod: PyTorch 2.x CUDA 12 template, 50GB+ disk
  2. SSH in, export HF_TOKEN=hf_...
  3. ./setup_runpod.sh --train   (or see setup_runpod.sh --help)
  4. tmux attach -t johann
  5. scp weights/johann_v1/*.safetensors back to Mac when done

Exit: 0 ok | 1 setup | 2 HF gate | 3 no weights
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode="check" ;;
    --train) mode="train" ;;
    --train-replicate) mode="train-replicate" ;;
    --generate) mode="generate" ;;
    --postpro) mode="postpro" ;;
    --all) mode="all" ;;
    --skip-postpro) skip_postpro=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "warn: unknown option $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [ "${JOHANN_SKIP_POSTPRO:-0}" = "1" ]; then
  skip_postpro=1
fi

run_gate_check() {
  ruby "$CHECK_SCRIPT"
}

check_dataset() {
  if [ ! -d "$DATASET_DIR" ]; then
    echo "warn: dataset missing at $DATASET_DIR" >&2
    exit 1
  fi
  count="$(count_dataset_images)"
  if [ "$count" -eq 0 ]; then
    echo "warn: dataset has no images" >&2
    exit 1
  fi
  echo "ok: dataset images $count"
}

require_lora_weights() {
  weights="$(latest_lora_weights || true)"
  if [ -z "${weights:-}" ]; then
    echo "warn: no weights in $WEIGHTS_DIR" >&2
    echo "fix: $SCRIPT_DIR/run_generate.sh --train" >&2
    exit 3
  fi
  echo "ok: weights $weights"
}

run_generate_samples() {
  require_lora_weights
  config="$(mktemp "${TMPDIR:-/tmp}/johann_generate_XXXXXX").yaml"
  trap 'rm -f "$config"' EXIT INT TERM
  render_config generate "$config"
  echo "ok: generating samples"
  run_ai_toolkit "$config"
  sync_samples_to_lora_root
}

maybe_postpro() {
  if [ "$skip_postpro" -eq 0 ]; then
    run_postpro
  fi
}

case "$mode" in
  check)
    run_gate_check
    check_dataset
    weights="$(latest_lora_weights || true)"
    if [ -n "${weights:-}" ]; then
      echo "ok: weights $weights"
    else
      echo "ok: weights not trained yet"
    fi
    echo "ok: images $LORA_ROOT"
    ;;
  train)
    run_gate_check
    check_dataset
    sh "$SCRIPT_DIR/run_train.sh"
    sync_samples_to_lora_root
    maybe_postpro
    ;;
  train-replicate)
    check_dataset
    ruby "$SCRIPT_DIR/run_train_replicate.rb"
    weights="$(latest_lora_weights || true)"
    if [ -n "${weights:-}" ]; then
      echo "ok: local weights ready for generate: $weights"
    else
      echo "ok: train finished; generate via Replicate destination model if no .safetensors yet"
    fi
    ;;
  generate)
    run_gate_check
    run_generate_samples
    maybe_postpro
    ;;
  postpro)
    run_postpro
    ;;
  all)
    run_gate_check
    require_lora_weights
    run_generate_samples
    maybe_postpro
    ;;
esac

echo "ok: done mode=$mode"
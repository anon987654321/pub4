#!/bin/sh
# Orchestrate Ragnhild FLUX LoRA train/generate with an early HF gate check.
# Deliverable images land flat in pub4/lora/ — not under output/ragnhild_v2/.
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LORA_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"
AI_TOOLKIT_ROOT="${AI_TOOLKIT_ROOT:-/Users/mac/ai-toolkit}"
TRAIN_CONFIG="${RAGNHILD_TRAIN_CONFIG:-$SCRIPT_DIR/train_ragnhild.yaml}"
GENERATE_CONFIG="${RAGNHILD_GENERATE_CONFIG:-$SCRIPT_DIR/generate_ragnhild.yaml}"
CHECK_SCRIPT="$SCRIPT_DIR/check_hf_flux_access.py"
POSTPRO_SCRIPT="$SCRIPT_DIR/postpro_samples.rb"
WEIGHTS_ROOT="$SCRIPT_DIR/weights/ragnhild_v2"
TOOLKIT_SAMPLES_DIR="$WEIGHTS_ROOT/samples"
DATASET_DIR="$SCRIPT_DIR/dataset"

MODE="all"
SKIP_POSTPRO=0

usage() {
  cat <<'EOF'
Usage: run_generate.sh [--check | --train | --generate | --postpro]

Default (--all): preflight -> generate samples from latest LoRA -> portrait postpro

Deliverable images: flat in pub4/lora/
Toolkit internals:  training/ragnhild/ai_toolkit/weights/ragnhild_v2/

  --check     Only verify HF FLUX access, auth, toolkit, and dataset
  --train     Train LoRA (run_train.sh), sync samples to lora root, postpro
  --generate  Sample-only pass from latest checkpoint, sync, postpro
  --postpro   Run portrait postpro on ragnhild_hf_* images in lora root

Environment:
  HF_TOKEN / HUGGINGFACE_HUB_TOKEN   Hugging Face auth
  AI_TOOLKIT_ROOT                    Path to ai-toolkit checkout
  RAGNHILD_FLUX_MODEL_PATH           Optional local FLUX.1-dev folder bypass
  RAGNHILD_SKIP_POSTPRO=1            Skip postpro step

Exit codes:
  0  success
  1  setup/auth failure
  2  HF FLUX gate blocked
  3  missing LoRA weights
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --train) MODE="train" ;;
    --generate) MODE="generate" ;;
    --postpro) MODE="postpro" ;;
    --all) MODE="all" ;;
    --skip-postpro) SKIP_POSTPRO=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [ "${RAGNHILD_SKIP_POSTPRO:-0}" = "1" ]; then
  SKIP_POSTPRO=1
fi

activate_toolkit() {
  if [ ! -d "$AI_TOOLKIT_ROOT" ]; then
    echo "ai-toolkit not found at $AI_TOOLKIT_ROOT" >&2
    echo "clone: git clone https://github.com/ostris/ai-toolkit.git $AI_TOOLKIT_ROOT" >&2
    exit 1
  fi
  cd "$AI_TOOLKIT_ROOT"
  if [ -f venv/bin/activate ]; then
    . venv/bin/activate
  elif [ -f .venv/bin/activate ]; then
    . .venv/bin/activate
  fi
  if [ ! -f run.py ]; then
    echo "run.py missing in $AI_TOOLKIT_ROOT" >&2
    exit 1
  fi
  if [ -n "${HF_TOKEN:-}" ]; then
    export HUGGINGFACE_HUB_TOKEN="${HF_TOKEN}"
  fi
}

run_gate_check() {
  if [ ! -f "$CHECK_SCRIPT" ]; then
    echo "missing gate check script: $CHECK_SCRIPT" >&2
    exit 1
  fi
  activate_toolkit
  python "$CHECK_SCRIPT"
}

check_dataset() {
  if [ ! -d "$DATASET_DIR" ]; then
    echo "dataset missing: $DATASET_DIR" >&2
    exit 1
  fi
  image_count="$(find "$DATASET_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | wc -l | tr -d ' ')"
  if [ "$image_count" -eq 0 ]; then
    echo "dataset has no training images: $DATASET_DIR" >&2
    exit 1
  fi
  echo "dataset images: $image_count"
}

latest_lora_weights() {
  if [ ! -d "$WEIGHTS_ROOT" ]; then
    return 1
  fi
  find "$WEIGHTS_ROOT" -maxdepth 1 -type f -name '*.safetensors' 2>/dev/null | sort | tail -n 1
}

require_lora_weights() {
  weights="$(latest_lora_weights || true)"
  if [ -z "${weights:-}" ]; then
    cat >&2 <<EOF
No ragnhild_v2 LoRA weights found in $WEIGHTS_ROOT

Train first:
  $SCRIPT_DIR/run_generate.sh --train

Or run training directly:
  $SCRIPT_DIR/run_train.sh
EOF
    exit 3
  fi
  echo "latest LoRA weights: $weights"
}

sync_samples_to_lora_root() {
  if [ ! -d "$TOOLKIT_SAMPLES_DIR" ]; then
    return 0
  fi
  find "$TOOLKIT_SAMPLES_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 |
    while IFS= read -r -d '' file; do
      base="$(basename "$file")"
      mv -f "$file" "$LORA_ROOT/$base"
      echo "synced $base -> $LORA_ROOT/"
    done
  rmdir "$TOOLKIT_SAMPLES_DIR" 2>/dev/null || true
}

run_generate_samples() {
  require_lora_weights
  activate_toolkit
  echo "generating LoRA samples with $GENERATE_CONFIG"
  python run.py "$GENERATE_CONFIG"
  sync_samples_to_lora_root
}

run_postpro() {
  hf_count="$(find "$LORA_ROOT" -maxdepth 1 -type f -name 'ragnhild_hf_*.jpg' ! -name '*_portrait.jpg' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$hf_count" -eq 0 ]; then
    echo "no ragnhild_hf_* samples found in $LORA_ROOT" >&2
    exit 1
  fi
  echo "postpro on $hf_count sample(s) in $LORA_ROOT"
  ruby "$POSTPRO_SCRIPT" --input-dir "$LORA_ROOT" --output-dir "$LORA_ROOT" --presets portrait --limit 12
}

case "$MODE" in
  check)
    run_gate_check
    check_dataset
    weights="$(latest_lora_weights || true)"
    if [ -n "${weights:-}" ]; then
      echo "latest LoRA weights: $weights"
    else
      echo "LoRA weights: not trained yet (run --train after HF gate clears)"
    fi
    echo "image root: $LORA_ROOT"
    ;;
  train)
    run_gate_check
    check_dataset
    echo "starting training via $SCRIPT_DIR/run_train.sh"
    sh "$SCRIPT_DIR/run_train.sh" "$TRAIN_CONFIG"
    sync_samples_to_lora_root
    if [ "$SKIP_POSTPRO" -eq 0 ]; then
      run_postpro
    fi
    ;;
  generate)
    run_gate_check
    run_generate_samples
    if [ "$SKIP_POSTPRO" -eq 0 ]; then
      run_postpro
    fi
    ;;
  postpro)
    run_postpro
    ;;
  all)
    run_gate_check
    require_lora_weights
    run_generate_samples
    if [ "$SKIP_POSTPRO" -eq 0 ]; then
      run_postpro
    fi
    ;;
esac

echo "done: mode=$MODE images=$LORA_ROOT"
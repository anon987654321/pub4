#!/bin/sh
set -eu

. "$(dirname -- "$0")/lib.sh"

mode="all"
skip_postpro=0

usage() {
  cat <<'EOF'
Usage: run_generate.sh [--check | --train | --generate | --postpro | --all]

  --check     HF FLUX gate, toolkit, dataset
  --train     Train LoRA, sync samples, optional postpro
  --generate  Sample from latest checkpoint, sync, optional postpro
  --postpro   Portrait postpro on generated samples in lora/
  --all       check, generate, postpro (default)

Deliverables: lora/
Weights:       training/ragnhild/ai_toolkit/weights/ragnhild_v2/

Environment:
  HF_TOKEN, HUGGINGFACE_HUB_TOKEN, AI_TOOLKIT_ROOT
  RAGNHILD_FLUX_MODEL_PATH, RAGNHILD_SKIP_POSTPRO=1

Exit: 0 ok | 1 setup | 2 HF gate | 3 no weights
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode="check" ;;
    --train) mode="train" ;;
    --generate) mode="generate" ;;
    --postpro) mode="postpro" ;;
    --all) mode="all" ;;
    --skip-postpro) skip_postpro=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "warn: unknown option $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [ "${RAGNHILD_SKIP_POSTPRO:-0}" = "1" ]; then
  skip_postpro=1
fi

run_gate_check() {
  activate_toolkit
  python "$CHECK_SCRIPT"
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
  config="$(mktemp "${TMPDIR:-/tmp}/ragnhild_generate.XXXXXX.yaml")"
  trap 'rm -f "$config"' EXIT INT TERM
  render_config generate "$config"
  echo "ok: generating samples"
  python run.py "$config"
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
#!/bin/sh
set -eu

. "$(dirname -- "$0")/toolkit.sh"

mode="all"
skip_postpro=0

usage() {
  cat <<EOF
Usage: lora [--check | --train | --train-kaggle | --train-colab | --train-replicate
             | --generate | --postpro | --all]

  --check            HF FLUX gate, toolkit, dataset
  --train            Train LoRA locally / RunPod via ai-toolkit
  --train-kaggle     Train on a free Kaggle T4: push notebook, poll, pull weights
  --train-colab      Write a Colab notebook for a free T4 (no phone verification)
  --train-replicate  Zip dataset, train on Replicate (ostris/flux-dev-lora-trainer)
  --generate         Sample from latest checkpoint, then optional postpro
  --postpro          Portrait postpro on generated samples in out/
  --all              check, generate, postpro (default)

Anything after a lane flag (--train-kaggle, --train-colab, --train-replicate)
is passed to that lane, e.g.
  ./lora --train-kaggle --dry-run --steps 600
  ./lora --train-replicate --dry-run

Deliverables: $SUBJECT_DIR/out/
Weights:      $SUBJECT_DIR/weights/$MODEL/

Environment:
  HF_TOKEN, HUGGINGFACE_HUB_TOKEN, AI_TOOLKIT_ROOT
  LORA_DEVICE=mps|cuda|cuda_t4|cpu   (default mps; cuda on a 24GB+ GPU,
                                      cuda_t4 on 16GB Turing — fp16, quantised)
  LORA_LOW_VRAM=0|1          (optional; cuda defaults to 0)
  LORA_LR, LORA_STEPS, LORA_RESOLUTIONS=512,768
  LORA_FLUX_MODEL_PATH, LORA_SKIP_POSTPRO=1

Four train lanes:
  A) local/RunPod:  ./lora --train
  B) Colab:         ./lora --train-colab        (free T4, no phone verification)
  C) Kaggle:        ./lora --train-kaggle       (free, but GPU+internet need
                                                 phone verification)
     needs KAGGLE_USERNAME + KAGGLE_KEY (or ~/.kaggle/kaggle.json), a
     phone-verified account for internet, and an HF_TOKEN notebook secret
  D) Replicate:     ./lora --train-replicate    (paid, hosted H100)
     needs REPLICATE_API_TOKEN

RunPod (24GB+ GPU — RTX 4090 / A5000 / L4):
  1. Create pod: PyTorch 2.x CUDA 12 template, 50GB+ disk
  2. SSH in, export HF_TOKEN=hf_yourtoken
  3. ./setup_runpod.sh --train   (or see setup_runpod.sh --help)
  4. tmux attach -t $SUBJECT
  5. scp weights/$MODEL/*.safetensors back to Mac when done

Exit: 0 ok | 1 setup | 2 HF gate | 3 no weights
EOF
}

# A lane flag ends this parse: the remainder is that lane's own argv.
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode="check"; shift ;;
    --train) mode="train"; shift ;;
    --generate) mode="generate"; shift ;;
    --postpro) mode="postpro"; shift ;;
    --all) mode="all"; shift ;;
    --skip-postpro) skip_postpro=1; shift ;;
    --train-kaggle) mode="train-kaggle"; shift; break ;;
    --train-colab) mode="train-colab"; shift; break ;;
    --train-replicate) mode="train-replicate"; shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "warn: unknown option $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ "${LORA_SKIP_POSTPRO:-0}" = "1" ]; then
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
    echo "fix: $SUBJECT_DIR/lora --train   (or --train-kaggle)" >&2
    exit 3
  fi
  echo "ok: weights $weights"
}

run_generate_samples() {
  require_lora_weights
  config="$(mktemp "${TMPDIR:-/tmp}/${SUBJECT}_generate_XXXXXX").yaml"
  trap 'rm -f "$config"' EXIT INT TERM
  render_config generate "$config"
  echo "ok: generating samples"
  run_ai_toolkit "$config"
  sync_samples_to_out
}

maybe_postpro() {
  if [ "$skip_postpro" -eq 0 ]; then
    run_postpro
  fi
}

report_weights() {
  weights="$(latest_lora_weights || true)"
  if [ -n "${weights:-}" ]; then
    echo "ok: weights $weights"
  else
    echo "ok: weights not trained yet"
  fi
}

case "$mode" in
  check)
    run_gate_check
    check_dataset
    report_weights
    echo "ok: images $OUT_DIR"
    ;;
  train)
    run_gate_check
    check_dataset
    sh "$SCRIPT_DIR/run_train.sh"
    sync_samples_to_out
    maybe_postpro
    ;;
  train-kaggle)
    check_dataset
    ruby "$SCRIPT_DIR/run_train_kaggle.rb" "$@"
    report_weights
    ;;
  train-colab)
    check_dataset
    ruby "$SCRIPT_DIR/run_train_colab.rb" "$@"
    ;;
  train-replicate)
    check_dataset
    ruby "$SCRIPT_DIR/run_train_replicate.rb" "$@"
    report_weights
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

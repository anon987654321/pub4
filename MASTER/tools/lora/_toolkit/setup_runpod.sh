#!/bin/sh
# Bootstrap a FLUX LoRA training run on a RunPod GPU pod (Linux + CUDA).
# Run via SSH after creating a 24GB+ GPU pod (RTX 4090 / A5000 / L4).
#
# For a free 16GB T4 instead, the Kaggle lane needs no pod and no SSH:
#   STUDIO/lora/<subject>/lora --train-kaggle
set -eu

: "${SUBJECT:?export SUBJECT=<subject> (the directory name under STUDIO/lora/)}"

PUB4_REPO="${PUB4_REPO:-https://github.com/anon987654321/pub4.git}"
PUB4_BRANCH="${PUB4_BRANCH:-main}"
AI_TOOLKIT_ROOT="${AI_TOOLKIT_ROOT:-$HOME/ai-toolkit}"
WORK_ROOT="${WORK_ROOT:-$HOME/pub4}"
SUBJECT_DIR="$WORK_ROOT/STUDIO/lora/$SUBJECT"
START_TRAIN=0

usage() {
  cat <<EOF
Usage: setup_runpod.sh [--train]

Run on a RunPod GPU pod (SSH). Requires HF_TOKEN with FLUX.1-dev access.

RunPod pod settings:
  GPU:     24GB+ VRAM (RTX 4090, A5000, L4, A40)
  Template: PyTorch 2.x + CUDA 12 (Ubuntu 22.04)
  Disk:    50GB+ container (80GB safer for HF cache)

Before SSH:
  export HF_TOKEN=hf_... SUBJECT=$SUBJECT

On pod:
  curl -fsSL https://raw.githubusercontent.com/anon987654321/pub4/main/STUDIO/lora/_toolkit/setup_runpod.sh | sh
  # or git clone pub4 and: ./STUDIO/lora/_toolkit/setup_runpod.sh --train
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --train) START_TRAIN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "warn: unknown option $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [ -z "${HF_TOKEN:-}" ] && [ -z "${HUGGINGFACE_HUB_TOKEN:-}" ]; then
  echo "fix: export HF_TOKEN=hf_... (Hugging Face, FLUX.1-dev accepted)" >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ruby tmux git curl ca-certificates
fi

if [ ! -d "$WORK_ROOT/.git" ]; then
  git clone --branch "$PUB4_BRANCH" --depth 1 "$PUB4_REPO" "$WORK_ROOT"
else
  git -C "$WORK_ROOT" pull --ff-only
fi

if [ ! -d "$AI_TOOLKIT_ROOT/.git" ]; then
  git clone --depth 1 https://github.com/ostris/ai-toolkit.git "$AI_TOOLKIT_ROOT"
fi

if [ ! -x "$AI_TOOLKIT_ROOT/.venv/bin/python" ]; then
  python3 -m venv "$AI_TOOLKIT_ROOT/.venv"
  "$AI_TOOLKIT_ROOT/.venv/bin/pip" install --upgrade pip wheel
  "$AI_TOOLKIT_ROOT/.venv/bin/pip" install -r "$AI_TOOLKIT_ROOT/requirements.txt"
fi

export LORA_DEVICE=cuda
export LORA_SKIP_POSTPRO=1
export AI_TOOLKIT_ROOT
export HF_TOKEN="${HF_TOKEN:-$HUGGINGFACE_HUB_TOKEN}"
export HUGGINGFACE_HUB_TOKEN="${HUGGINGFACE_HUB_TOKEN:-$HF_TOKEN}"

if [ ! -d "$SUBJECT_DIR" ]; then
  echo "warn: no subject at $SUBJECT_DIR" >&2
  exit 1
fi

chmod +x "$WORK_ROOT/STUDIO/lora/_toolkit"/*.sh "$SUBJECT_DIR/lora"
"$SUBJECT_DIR/lora" --check

if [ "$START_TRAIN" -eq 1 ]; then
  echo "ok: starting training in tmux session $SUBJECT"
  tmux kill-session -t "$SUBJECT" 2>/dev/null || true
  tmux new-session -d -s "$SUBJECT" \
    "'$SUBJECT_DIR/lora' --train 2>&1 | tee '$SUBJECT_DIR/train_run.log'"
  echo "ok: attach with: tmux attach -t $SUBJECT"
else
  echo "ok: bootstrap done"
  echo "fix: tmux new -s $SUBJECT"
  echo "fix: $SUBJECT_DIR/lora --train 2>&1 | tee $SUBJECT_DIR/train_run.log"
fi

#!/bin/sh
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${AI_TOOLKIT_ROOT:-/Users/mac/ai-toolkit}"
CONFIG="$HERE/config/ai_toolkit.yaml"
LOG="$HERE/weights/train.log"
if [ ! -d "$ROOT" ]; then
  echo "ai-toolkit not found at $ROOT" >&2
  echo "clone: git clone https://github.com/ostris/ai-toolkit.git $ROOT" >&2
  exit 1
fi
cd "$ROOT"
if [ -f .venv/bin/activate ]; then
  . .venv/bin/activate
elif [ -f venv/bin/activate ]; then
  . venv/bin/activate
fi
TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
if [ -n "$TOKEN" ]; then
  export HF_TOKEN="$TOKEN"
  export HUGGING_FACE_HUB_TOKEN="$TOKEN"
  hf auth login --token "$TOKEN" >/dev/null 2>&1 || true
fi
if ! hf auth whoami >/dev/null 2>&1; then
  echo "Hugging Face auth required for black-forest-labs/FLUX.1-dev (gated model)." >&2
  echo "1. Accept license: https://huggingface.co/black-forest-labs/FLUX.1-dev" >&2
  echo "2. Create token: https://huggingface.co/settings/tokens (Read access)" >&2
  echo "3. export HF_TOKEN=hf_... && sh $0" >&2
  exit 1
fi
mkdir -p "$(dirname "$LOG")"
exec python run.py "$CONFIG" 2>&1 | tee "$LOG"

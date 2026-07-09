#!/bin/sh
set -e
ROOT="${AI_TOOLKIT_ROOT:-/Users/mac/ai-toolkit}"
CONFIG="${1:-${RAGNHILD_LORA_CONFIG:-/Users/mac/Documents/GitHub/pub4/lora/training/ragnhild/ai_toolkit/train_ragnhild.yaml}}"
if [ ! -d "$ROOT" ]; then
  echo "ai-toolkit not found at $ROOT" >&2
  echo "clone: git clone https://github.com/ostris/ai-toolkit.git $ROOT" >&2
  echo "or set AI_TOOLKIT_ROOT=/path/to/ai-toolkit" >&2
  exit 1
fi
cd "$ROOT"
if [ -f venv/bin/activate ]; then
  . venv/bin/activate
elif [ -f .venv/bin/activate ]; then
  . .venv/bin/activate
fi
if [ ! -f run.py ]; then
  echo "run.py missing in $ROOT — is ai-toolkit installed?" >&2
  exit 1
fi
if [ -n "${HF_TOKEN:-}" ]; then
  export HUGGINGFACE_HUB_TOKEN="${HF_TOKEN}"
fi
if [ ! -s "$HOME/.cache/huggingface/token" ] && [ ! -s "$HOME/.huggingface/token" ] && [ -z "${HUGGINGFACE_HUB_TOKEN:-}" ]; then
  cat >&2 <<'EOF'
Hugging Face auth not found.
For the best-quality Ragnhild LoRA, log in and accept access to black-forest-labs/FLUX.1-dev, then rerun.
  hf auth login
or:
  huggingface-cli login
EOF
  exit 1
fi
echo "training ragnhild LoRA with $CONFIG"
python run.py "$CONFIG"
if [ "${RAGNHILD_POSTPRO_SAMPLES:-0}" = "1" ]; then
  ruby /Users/mac/Documents/GitHub/pub4/lora/training/ragnhild/ai_toolkit/postpro_samples.rb
fi

#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LORA_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../../.." && pwd)"

AI_TOOLKIT_ROOT="${AI_TOOLKIT_ROOT:-$HOME/ai-toolkit}"
DATASET_DIR="$SCRIPT_DIR/dataset"
WEIGHTS_DIR="$SCRIPT_DIR/weights/ragnhild_v2"
SAMPLES_DIR="$WEIGHTS_DIR/samples"

CHECK_SCRIPT="$SCRIPT_DIR/check_hf_flux_access.py"
POSTPRO_SCRIPT="$SCRIPT_DIR/postpro_samples.rb"
RENDER_CONFIG="$SCRIPT_DIR/render_config.py"

export_hf_token() {
  if [ -n "${HF_TOKEN:-}" ]; then
    export HUGGINGFACE_HUB_TOKEN="${HF_TOKEN}"
  fi
}

hf_auth_missing() {
  [ ! -s "$HOME/.cache/huggingface/token" ] \
    && [ ! -s "$HOME/.huggingface/token" ] \
    && [ -z "${HUGGINGFACE_HUB_TOKEN:-}" ]
}

activate_toolkit() {
  if [ ! -d "$AI_TOOLKIT_ROOT" ]; then
    echo "warn: ai-toolkit missing at $AI_TOOLKIT_ROOT" >&2
    echo "fix: git clone https://github.com/ostris/ai-toolkit.git $AI_TOOLKIT_ROOT" >&2
    exit 1
  fi
  cd "$AI_TOOLKIT_ROOT"
  if [ -f venv/bin/activate ]; then
    . venv/bin/activate
  elif [ -f .venv/bin/activate ]; then
    . .venv/bin/activate
  fi
  if [ ! -f run.py ]; then
    echo "warn: run.py missing in $AI_TOOLKIT_ROOT" >&2
    exit 1
  fi
  export_hf_token
}

render_config() {
  mode="$1"
  output="$2"
  activate_toolkit
  python "$RENDER_CONFIG" --mode "$mode" --output "$output"
}

count_dataset_images() {
  find "$DATASET_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    | wc -l | tr -d ' '
}

latest_lora_weights() {
  if [ ! -d "$WEIGHTS_DIR" ]; then
    return 1
  fi
  find "$WEIGHTS_DIR" -maxdepth 1 -type f -name '*.safetensors' 2>/dev/null | sort | tail -n 1
}

sync_samples_to_lora_root() {
  if [ ! -d "$SAMPLES_DIR" ]; then
    return 0
  fi
  find "$SAMPLES_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 |
    while IFS= read -r -d '' file; do
      name="$(basename "$file")"
      mv -f "$file" "$LORA_ROOT/$name"
      echo "ok: synced $name"
    done
  rmdir "$SAMPLES_DIR" 2>/dev/null || true
}

run_postpro() {
  ruby "$POSTPRO_SCRIPT" \
    --input-dir "$LORA_ROOT" \
    --output-dir "$LORA_ROOT" \
    --presets portrait \
    --limit 12
}
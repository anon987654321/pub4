#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LORA_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../../../.." && pwd)"

AI_TOOLKIT_ROOT="${AI_TOOLKIT_ROOT:-$HOME/ai-toolkit}"
DATASET_DIR="$SCRIPT_DIR/dataset"
WEIGHTS_DIR="$SCRIPT_DIR/weights/johann_v1"
SAMPLES_DIR="$WEIGHTS_DIR/samples"

CHECK_SCRIPT="$SCRIPT_DIR/check_hf_flux_access.rb"
POSTPRO_SCRIPT="$SCRIPT_DIR/postpro_samples.rb"
RENDER_CONFIG="$SCRIPT_DIR/render_config.rb"
AI_TOOLKIT_RUNNER="$SCRIPT_DIR/run_ai_toolkit.rb"

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
  export_hf_token
}

render_config() {
  mode="$1"
  output="$2"
  ruby "$RENDER_CONFIG" --mode "$mode" --output "$output"
}

run_ai_toolkit() {
  config="$1"
  export AI_TOOLKIT_ROOT
  ruby "$AI_TOOLKIT_RUNNER" "$config"
}

count_dataset_images() {
  count=0
  for file in "$DATASET_DIR"/*; do
    case "$file" in
      *.jpg|*.jpeg|*.png|*.webp) count=$((count + 1)) ;;
    esac
  done
  echo "$count"
}

latest_lora_weights() {
  ruby -e '
    require "pathname"
    dir = Pathname.new(ARGV[0])
    exit 1 unless dir.directory?
    files = dir.children.select { |path| path.file? && path.extname == ".safetensors" }
    exit 1 if files.empty?
    puts files.max_by { |path| path.mtime }
  ' "$WEIGHTS_DIR"
}

sync_samples_to_lora_root() {
  if [ ! -d "$SAMPLES_DIR" ]; then
    return 0
  fi
  for file in "$SAMPLES_DIR"/*; do
    case "$file" in
      *.jpg|*.jpeg|*.png|*.webp)
        name="$(basename "$file")"
        mv -f "$file" "$LORA_ROOT/$name"
        echo "ok: synced $name"
        ;;
    esac
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
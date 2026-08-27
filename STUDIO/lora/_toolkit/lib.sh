#!/bin/sh
set -eu

# One toolkit, any subject.
#
# One copy, not one per subject: johann/ai_toolkit was ~980 lines identical
# to ragnhild/ai_toolkit apart from the name, verified by diffing the two with the
# subject token normalised -- every file matched exactly. The cost was not the
# disk, it was that a fix had to be made twice: moving lora/ to STUDIO/lora/ broke
# REPO_ROOT here, TOOLKIT_DIR and two curl URLs in setup_runpod.sh, and an
# absolute path in watch_step250.sh, and each had to be repaired in both trees
# with nothing to catch a missed copy.
#
# The subject now arrives as SUBJECT_DIR, set by the wrapper in each subject's
# directory, and subject.env there names the three things that actually differ:
# SUBJECT, MODEL, TRIGGER. Everything else is shared.
#
# The wrappers were a smaller instance of the same mistake: six three-line
# scripts per subject, one per mode, when run_generate.sh already dispatches on
# a flag. There is now one wrapper, `lora`, per subject. The ai_toolkit/ nesting
# went with them — it mirrored upstream's layout back when the tree was a fork
# of it, and a subject directory is already the subject.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LORA_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"

if [ -z "${SUBJECT_DIR:-}" ]; then
  echo "error: SUBJECT_DIR is not set — run a subject's wrapper, e.g." >&2
  echo "       STUDIO/lora/subjects/ragnhild/lora --all" >&2
  exit 1
fi
SUBJECT_DIR="$(CDPATH= cd -- "$SUBJECT_DIR" && pwd)"
if [ ! -f "$SUBJECT_DIR/subject.env" ]; then
  echo "error: no subject.env in $SUBJECT_DIR" >&2
  exit 1
fi
# shellcheck disable=SC1091
. "$SUBJECT_DIR/subject.env"
: "${SUBJECT:?subject.env must set SUBJECT}"
: "${MODEL:?subject.env must set MODEL}"
TRIGGER="${TRIGGER:-$SUBJECT}"
export SUBJECT MODEL TRIGGER SUBJECT_DIR

# Turn off xet before anything can download a model.
#
# xet is Hugging Face's deduplicating transfer path. When it works it is
# faster; when it does not, it hangs at zero bytes with the process asleep at
# 0.1% CPU and no error, which is indistinguishable from a slow network. A
# local SDXL pull sat like that for eight minutes on 2026-08-27 and moved at
# 36 MB/s the moment these were set.
#
# colab_session.rb has disabled it since the first Colab run. The local lane
# never did, so the same stall was waiting here for the first person to render
# on their own machine.
#
# Set rather than exported conditionally: there is no case in this toolkit
# where the dedup saving beats the risk of a silent hang, and both variables
# are read by huggingface_hub at import time.
export HF_HUB_DISABLE_XET=1
export HF_HUB_ENABLE_HF_TRANSFER=0

AI_TOOLKIT_ROOT="${AI_TOOLKIT_ROOT:-$HOME/ai-toolkit}"
DATASET_DIR="$SUBJECT_DIR/dataset"
WEIGHTS_DIR="$SUBJECT_DIR/weights/$MODEL"
SAMPLES_DIR="$WEIGHTS_DIR/samples"
# Finished portraits belong to the subject. They used to land flat in
# STUDIO/lora/, which the next subject would also have written into.
OUT_DIR="$SUBJECT_DIR/out"

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

sync_samples_to_out() {
  if [ ! -d "$SAMPLES_DIR" ]; then
    return 0
  fi
  mkdir -p "$OUT_DIR"
  for file in "$SAMPLES_DIR"/*; do
    case "$file" in
      *.jpg|*.jpeg|*.png|*.webp)
        name="$(basename "$file")"
        mv -f "$file" "$OUT_DIR/$name"
        echo "ok: synced $name"
        ;;
    esac
  done
  rmdir "$SAMPLES_DIR" 2>/dev/null || true
}

run_postpro() {
  mkdir -p "$OUT_DIR"
  ruby "$POSTPRO_SCRIPT" \
    --input-dir "$OUT_DIR" \
    --output-dir "$OUT_DIR" \
    --presets portrait \
    --limit 12
}

#!/bin/sh
set -eu

. "$(dirname -- "$0")/toolkit.sh"

config="$(mktemp "${TMPDIR:-/tmp}/${SUBJECT}_train_XXXXXX").yaml"
trap 'rm -f "$config"' EXIT INT TERM

if hf_auth_missing; then
  echo "warn: Hugging Face auth missing" >&2
  echo "fix: hf auth login, accept black-forest-labs/FLUX.1-dev" >&2
  exit 1
fi

render_config train "$config"
echo "ok: training $MODEL"
run_ai_toolkit "$config"

if [ "${LORA_POSTPRO_SAMPLES:-0}" = "1" ]; then
  run_postpro
fi

#!/bin/sh
# Dual-track: train Johann FLUX LoRA on Replicate (no RunPod SSH).
set -eu

. "$(dirname -- "$0")/lib.sh"

exec ruby "$SCRIPT_DIR/run_train_replicate.rb" "$@"

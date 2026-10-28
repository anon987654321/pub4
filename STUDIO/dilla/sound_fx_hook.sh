#!/usr/bin/env sh
# Optional Claude Code / OpenCode lifecycle adapter for Dilla's synthetic cue renderer.
# Usage: sound_fx_hook.sh start|submit|complete|error|notification|precompact|session_end
set -eu

event=${1:-}
case "$event" in
  start|submit|complete|error|notification|precompact|session_end) ;;
  *) exit 0 ;;
esac

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec ruby "$script_dir/dilla.rb" sound-fx "$event" --play

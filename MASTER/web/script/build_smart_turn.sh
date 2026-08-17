#!/bin/sh
# Vendor the Smart Turn endpointing assets into public/.
#
# Both are committed, the same way three.face.module.js is: a deploy that has to
# reach npm and Hugging Face is a deploy that fails when they are down, and this
# tree is served under a CSP that forbids loading them from anywhere else at
# runtime anyway. This script exists so the bytes in git can be reproduced and
# their provenance is a command rather than a memory.
#
#   sh script/build_smart_turn.sh
#
# ~21MB total. onnxruntime-web ships only a threaded WASM build from 1.27; it
# runs single-threaded when SharedArrayBuffer is absent, so no cross-origin
# isolation headers are required.

set -eu

ORT_VERSION=1.27.0
MODEL=smart-turn-v3.2-cpu.onnx
MODEL_REPO=pipecat-ai/smart-turn-v3

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vendor="$root/public/vendor/onnxruntime"
models="$root/public/models"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$vendor" "$models"

printf 'smart_turn: onnxruntime-web %s\n' "$ORT_VERSION"
curl -sSL --fail -o "$work/ort.tgz" \
  "https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-${ORT_VERSION}.tgz"
tar xzf "$work/ort.tgz" -C "$work" \
  package/dist/ort.wasm.min.mjs \
  package/dist/ort-wasm-simd-threaded.mjs \
  package/dist/ort-wasm-simd-threaded.wasm
cp "$work/package/dist/ort.wasm.min.mjs" \
   "$work/package/dist/ort-wasm-simd-threaded.mjs" \
   "$work/package/dist/ort-wasm-simd-threaded.wasm" "$vendor/"

printf 'smart_turn: %s from %s\n' "$MODEL" "$MODEL_REPO"
curl -sSL --fail -o "$models/$MODEL" \
  "https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL}"

# An HTML error page saved under a .onnx name is the failure mode worth
# catching: it is small, and it would 404-as-200 all the way to the browser.
size=$(wc -c < "$models/$MODEL")
if [ "$size" -lt 4000000 ]; then
  printf 'smart_turn: %s is only %s bytes — fetch failed\n' "$MODEL" "$size" >&2
  exit 1
fi

printf 'smart_turn: vendored\n'
ls -l "$vendor" "$models"

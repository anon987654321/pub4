#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/script/bundle_size.sh"
OUT="$ROOT/public/face.modules.bundle.js"
ENTRY="$ROOT/script/face_modules_entry.js"
npx --yes esbuild@0.25.9 "$ENTRY" \
  --bundle \
  --format=esm \
  --platform=browser \
  --target=es2020 \
  --outfile="$OUT"
report_bundle_size "$OUT"

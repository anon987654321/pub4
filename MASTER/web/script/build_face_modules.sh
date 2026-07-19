#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/public/face.modules.bundle.js"
ENTRY="$ROOT/script/face_modules_entry.js"
npx --yes esbuild@0.25.9 "$ENTRY" \
  --bundle \
  --format=esm \
  --platform=browser \
  --target=es2020 \
  --outfile="$OUT"
RAW=$(wc -c < "$OUT" | tr -d ' ')
GZ=$(gzip -c "$OUT" | wc -c | tr -d ' ')
echo "face.modules.bundle.js raw=${RAW} gzip=${GZ}"

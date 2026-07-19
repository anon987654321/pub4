#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/public/three.face.module.js"
ENTRY="$ROOT/script/three_face_entry.js"
WORKDIR="$ROOT/script/three_build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
if [ ! -f package.json ]; then npm init -y >/dev/null; fi
npm install three --no-fund --no-audit
cp "$ENTRY" "$WORKDIR/entry.js"
npx --yes esbuild@0.25.9 entry.js --bundle --minify --format=esm --platform=browser --outfile="$OUT"
RAW=$(wc -c < "$OUT" | tr -d ' ')
GZ=$(gzip -c "$OUT" | wc -c | tr -d ' ')
echo "three.face.module.js raw=${RAW} gzip=${GZ}"

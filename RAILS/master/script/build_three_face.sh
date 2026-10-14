#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/script/bundle_size.sh"
OUT="$ROOT/public/three.face.module.js"
ENTRY="$ROOT/script/three_face_entry.js"
WORKDIR="$ROOT/script/three_build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
if [ ! -f package.json ]; then npm init -y >/dev/null; fi
npm install three --no-fund --no-audit
cp "$ENTRY" "$WORKDIR/entry.js"
npx --yes esbuild@0.25.9 entry.js --bundle --minify --format=esm --platform=browser --outfile="$OUT"
report_bundle_size "$OUT"

#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/script/bundle_size.sh"
OUT="$ROOT/public/face.modules.bundle.js"
ENTRY="$ROOT/script/face_modules_entry.js"
SOURCE_DIGEST="$(ruby -rdigest -e 'paths = ARGV.sort; puts Digest::SHA256.hexdigest(paths.map { |p| File.binread(p) }.join("\0"))' \
  "$ENTRY" "$ROOT/public/face_blendshape_bridge.js" "$ROOT/public/face_particles.js" "$ROOT/public/face_sparse_field.js" "$ROOT/public/face_audio_bridge.js" "$ROOT/public/face_tts_bridge.js" "$ROOT/public/face_expression_bridge.js" "$ROOT/public/face_council_multi.js" "$ROOT/public/face_phosphor_trail.js" "$ROOT/public/face_micro_interactions.js" "$ROOT/public/face_perf_guards.js" "$ROOT/public/face_brutalist.js")"
npx --yes esbuild@0.25.9 "$ENTRY" \
  --bundle \
  --format=esm \
  --platform=browser \
  --target=es2020 \
  --outfile="$OUT"
ruby -e 'p, digest = ARGV; body = File.read(p); marker = "// SOURCE-SET-SHA256: #{digest}\\n"; body = body.sub(/\\A/, marker); File.write(p, body)' "$OUT" "$SOURCE_DIGEST"
report_bundle_size "$OUT"

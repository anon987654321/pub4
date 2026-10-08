#!/bin/sh
# Builds shared/vendor/javascript/tiptap.js — one self-contained ESM module
# exporting Editor and StarterKit.
#
# Why vendored rather than pinned to a CDN: STIMULUS_COMPONENTS_BASELINE.md
# states the rule for this tree ("Packages are vendored, not fetched") and
# StimulusComponentsGate enforces it for the 19 @stimulus-components packages.
# Tiptap was the exception, pinned to esm.sh, so every compose box on the site
# depended on a third party being reachable at the moment someone started
# writing. The pattern here is MASTER/web/script/build_three_face.sh: npm-install
# a pinned version, esbuild only what the entry point re-exports, commit the
# artifact so the 1GB VPS never runs npm.
#
# To change the Tiptap version, edit tiptap_build/package.json and re-run this.
# Do not patch the output.
set -e
cd "$(dirname "$0")/tiptap_build"
npm install --no-audit --no-fund --silent
npx --no-install esbuild entry.js \
  --bundle \
  --format=esm \
  --target=es2022 \
  --minify \
  --legal-comments=none \
  --outfile=../../vendor/javascript/tiptap.js
cd ../..
ruby -e 'p = "vendor/javascript/tiptap.js"; b = File.size(p); puts "tiptap.js #{(b / 1024.0).round(1)} KB"'

#!/usr/bin/env sh
# Remove propshaft recursion artifacts (public/assets/assets/...) that wedge Falcon boot.
set -eu
WEB_PUBLIC="${1:-$(cd "$(dirname "$0")/../web/public" && pwd)}"
nested="${WEB_PUBLIC}/assets/assets"
if [ -d "$nested" ]; then
  rm -rf "$nested"
  echo "clean_nested_assets: removed $nested"
fi
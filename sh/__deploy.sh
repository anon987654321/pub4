#!/usr/bin/env zsh
set -euo pipefail

for file in *.sh; do
  destination="/usr/local/bin/${file:r}"

  cp "$file" "$destination"
  chmod +x "$destination"

done

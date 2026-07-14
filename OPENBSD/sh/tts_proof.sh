#!/usr/bin/env sh
# Verify MASTER TTS host backend (espeak or edge-tts) on vm23.
set -eu

for bin in /usr/local/bin/espeak /usr/local/bin/edge-tts; do
  if [ -x "$bin" ]; then
    echo "tts: ok ($bin)"
    exit 0
  fi
done

echo "tts: fail — install espeak (pkg_add espeak) or edge-tts" >&2
exit 1
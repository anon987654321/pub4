#!/bin/sh
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LOG="$SCRIPT_DIR/train_run.log"
WEIGHTS="$SCRIPT_DIR/weights/$MODEL"
MARKER="$SCRIPT_DIR/step250_reached"
[ -f "$MARKER" ] && exit 0

checkpoint_found() {
  for f in "$WEIGHTS"/*.safetensors "$WEIGHTS"/*250*; do
    [ -f "$f" ] || continue
    echo "STEP250_REACHED: checkpoint $f"
    touch "$MARKER"
    ls -la "$WEIGHTS"
    exit 0
  done
}

while true; do
  checkpoint_found

  if [ -f "$LOG" ]; then
    if grep -qE 'step[: ]+250(/1800)?|global[_ ]step[: ]+250|Training step 250' "$LOG" 2>/dev/null; then
      echo "STEP250_REACHED: training step 250 in log"
      touch "$MARKER"
      grep -E 'step[: ]+250|global[_ ]step[: ]+250|Training step 250' "$LOG" | tail -3
      exit 0
    fi
  fi

  sleep 120
done
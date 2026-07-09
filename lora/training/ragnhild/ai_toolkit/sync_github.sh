#!/bin/sh
# Poll for new Ragnhild deliverables and push to GitHub while training runs.
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../../.." && pwd)"
LORA_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"
INTERVAL="${SYNC_INTERVAL_SEC:-300}"
BRANCH="${SYNC_BRANCH:-main}"
SYNC_WEIGHTS="${SYNC_WEIGHTS:-0}"

cd "$REPO_ROOT"

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "no git remote origin" >&2
  exit 1
fi

stage_changes() {
  git add "$LORA_ROOT"/*.jpg "$LORA_ROOT"/*.json 2>/dev/null || true
  if [ "$SYNC_WEIGHTS" = "1" ]; then
    git add "$SCRIPT_DIR/weights/ragnhild_v2/"*.safetensors 2>/dev/null || true
  fi
}

commit_and_push() {
  if git diff --cached --quiet; then
    return 0
  fi
  git commit -m "Training sync: update Ragnhild lora deliverables."
  git push origin "$BRANCH"
  echo "pushed $(date '+%Y-%m-%d %H:%M:%S')"
}

echo "sync_github: watching $LORA_ROOT every ${INTERVAL}s (branch $BRANCH)"
while true; do
  stage_changes
  if ! git diff --cached --quiet; then
    commit_and_push || echo "push failed $(date '+%Y-%m-%d %H:%M:%S')" >&2
  fi
  sleep "$INTERVAL"
done
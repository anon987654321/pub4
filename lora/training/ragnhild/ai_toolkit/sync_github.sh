#!/bin/sh
set -eu

. "$(dirname -- "$0")/lib.sh"

interval="${SYNC_INTERVAL_SEC:-300}"
branch="${SYNC_BRANCH:-main}"
sync_weights="${SYNC_WEIGHTS:-0}"

cd "$REPO_ROOT"

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "warn: git remote origin missing" >&2
  exit 1
fi

stage_changes() {
  git add "$LORA_ROOT"/*.jpg "$LORA_ROOT"/*.json 2>/dev/null || true
  if [ "$sync_weights" = "1" ]; then
    git add "$WEIGHTS_DIR"/*.safetensors 2>/dev/null || true
  fi
}

commit_and_push() {
  if git diff --cached --quiet; then
    return 0
  fi
  git commit -m "Sync Ragnhild lora deliverables."
  git push origin "$branch"
  echo "ok: pushed $(date '+%Y-%m-%d %H:%M:%S')"
}

echo "ok: watching $LORA_ROOT every ${interval}s on $branch"
while true; do
  stage_changes
  if ! git diff --cached --quiet; then
    commit_and_push || echo "warn: push failed $(date '+%Y-%m-%d %H:%M:%S')" >&2
  fi
  sleep "$interval"
done
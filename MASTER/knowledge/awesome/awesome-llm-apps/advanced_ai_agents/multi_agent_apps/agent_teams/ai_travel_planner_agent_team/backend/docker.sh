#!/usr/bin/env bash
# Robust Docker build & push for the travel‑planner backend.
# Fails fast on errors, missing commands, or pipeline breaks.
set -euo pipefail
IFS=$'\n\t'

#--- Configuration -----------------------------------------------------------
readonly IMAGE_NAME="${IMAGE_NAME:-decipher-backend}"
readonly REGISTRY="${REGISTRY:-mtwn105}"
readonly FULL_NAME="${REGISTRY}/${IMAGE_NAME}"
SKIP_PUSH=${SKIP_PUSH:-0}
DRY_RUN=${DRY_RUN:-0}

usage() {
  cat <<EOF
Usage: ${0##*/} [options]

Options:
  -h,--help        Show this help message.
  --skip-push      Do not push the image (overrides SKIP_PUSH env).
  --dry-run        Echo commands without executing them.
EOF
  exit 0
}

#--- Argument parsing ---------------------------------------------------------
while (( $# )); do
  case "$1" in
    -h|--help) usage ;;
    --skip-push) SKIP_PUSH=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
  shift
done

run() {
  if (( DRY_RUN )); then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

#--- Prerequisite checks ------------------------------------------------------
for cmd in git docker; do
  command -v "$cmd" >/dev/null || { printf 'Error: %s not installed\n' "$cmd" >&2; exit 127; }
done

#--- Version derivation -------------------------------------------------------
VERSION=$(git describe --tags --always --dirty --fallback="$(git rev-parse --short HEAD 2>/dev/null || echo 0)")

#--- Build --------------------------------------------------------------------
build_image() {
  local local_tag="${IMAGE_NAME}:${VERSION}"
  local remote_tag="${FULL_NAME}:${VERSION}"
  printf 'Building Docker image %s (local) and %s (remote)\n' "$local_tag" "$remote_tag"
  run docker build -t "$local_tag" .
  run docker tag "$local_tag" "$remote_tag"
  printf '%s\n' "$remote_tag"
}

#--- Push ---------------------------------------------------------------------
push_image() {
  local remote_tag=$1
  local latest_tag="${FULL_NAME}:latest"
  printf 'Tagging %s as %s and %s\n' "$remote_tag" "$latest_tag" "$remote_tag"
  run docker tag "$remote_tag" "$latest_tag"

  printf 'Pushing %s\n' "$latest_tag"
  run docker push "$latest_tag"
  printf 'Pushing %s\n' "$remote_tag"
  run docker push "$remote_tag"
}

#--- Entrypoint ---------------------------------------------------------------
main() {
  local built_tag
  built_tag=$(build_image)
  if (( SKIP_PUSH )); then
    printf 'Skipping push as requested (built tag: %s)\n' "$built_tag"
  else
    push_image "$built_tag"
  fi
  printf 'Successfully built%s version %s\n' "$(( SKIP_PUSH ))" "$VERSION"
}

main "$@"
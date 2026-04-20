#!/usr/bin/env bash
# Exit on error, undefined variable, or pipe failure
set -euo pipefail
IFS=$'\n\t'

# Constants
IMAGE_NAME="decipher-backend"
REGISTRY="mtwn105"

# Determine version; fail visibly if git unavailable
VERSION=$(git describe --tags --always --dirty --fallback=0)

# Build the Docker image and return its tag
build_image() {
  local tag="${IMAGE_NAME}:${VERSION}"
  printf 'Building Docker image: %s\n' "$tag"
  docker build -t "$tag" .
  printf '%s\n' "$tag"
}

# Tag and push the image
push_image() {
  local tag=$1
  printf 'Tagging and pushing: %s/%s:%s and %s/%s:%s\n' \
    "$REGISTRY" "$IMAGE_NAME" "latest" "$REGISTRY" "$IMAGE_NAME" "$VERSION"
  docker tag "$tag" "${REGISTRY}/${IMAGE_NAME}:latest"
  docker tag "$tag" "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
  docker push "${REGISTRY}/${IMAGE_NAME}:latest"
  docker push "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
}

# Main orchestration
main() {
  local image_tag
  image_tag=$(build_image)
  push_image "$image_tag"
  printf 'Successfully built and pushed version %s\n' "$VERSION"
}

# Execute
main "$@"
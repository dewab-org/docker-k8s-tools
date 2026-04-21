#!/bin/bash

set -euo pipefail

# ────────────────────────────────────────────────
# Parse arguments
# ────────────────────────────────────────────────
PUSH_IMAGE=false
for arg in "$@"; do
  case "$arg" in
    -p|--push)
      PUSH_IMAGE=true
      ;;
    *)
      echo "Usage: $0 [-p|--push]"
      exit 1
      ;;
  esac
done

# ────────────────────────────────────────────────
# Generate .env.docker using generate-env.sh
# ────────────────────────────────────────────────
GITHUB_ENV="$(mktemp)"
export GITHUB_ENV
export GITHUB_SHA="local"
./generate-env.sh

# ────────────────────────────────────────────────
# Build args from generated GITHUB_ENV (expecting 'VAR=value' lines)
# ────────────────────────────────────────────────
BUILD_ARGS=()
while IFS= read -r line; do
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*) ]]; then
    var="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    BUILD_ARGS+=("--build-arg" "${var}=${val}")
  fi
done < "$GITHUB_ENV"

# ────────────────────────────────────────────────
# Extract image version
# ────────────────────────────────────────────────
IMAGE_VERSION=$(awk -F= '/^IMAGE_VERSION=/{print $2}' "$GITHUB_ENV" | tr -d '"')
IMAGE_NAME="dewab-org/k8s-cli-toolkit"

# ────────────────────────────────────────────────
# Output info
# ────────────────────────────────────────────────
echo "🔨 Building image: ${IMAGE_NAME}:latest"
[[ -n "$IMAGE_VERSION" ]] && echo "🧭 Also tagging: ${IMAGE_NAME}:${IMAGE_VERSION}"
echo "💡 Build args:"
for arg in "${BUILD_ARGS[@]}"; do
  echo "  - ${arg#--build-arg }"
done
echo

# ────────────────────────────────────────────────
# Construct build command
# ────────────────────────────────────────────────
BUILD_CMD=(
#   --platform linux/amd64,linux/arm64
  docker buildx build
  --platform linux/amd64
  "${BUILD_ARGS[@]}"
  -t "${IMAGE_NAME}:latest"
)

if [[ -n "$IMAGE_VERSION" ]]; then
  BUILD_CMD+=(-t "${IMAGE_NAME}:${IMAGE_VERSION}")
fi

if [[ "$PUSH_IMAGE" == true ]]; then
  echo "📤 Push enabled: image will be uploaded"
  BUILD_CMD+=(--push)
else
  echo "📦 Push disabled: local-only build"
  BUILD_CMD+=(--load)
fi

# Add build context
BUILD_CMD+=(.)

# ────────────────────────────────────────────────
# Execute build
# ────────────────────────────────────────────────
"${BUILD_CMD[@]}"

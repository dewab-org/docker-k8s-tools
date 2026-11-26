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
trap 'rm -f "$GITHUB_ENV"' EXIT
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

# VARIANT picks the Dockerfile target: standard, tanzu, azure, openshift or
# all (default). Tags follow CI: `all` is :latest, the others are :<variant>.
VARIANT="${VARIANT:-all}"
case "$VARIANT" in
  all) PRIMARY_TAG=latest; TAG_SUFFIX="" ;;
  standard|tanzu|azure|openshift) PRIMARY_TAG="$VARIANT"; TAG_SUFFIX="-$VARIANT" ;;
  *) echo "Unknown VARIANT: $VARIANT" >&2; exit 1 ;;
esac

# ────────────────────────────────────────────────
# Output info
# ────────────────────────────────────────────────
echo "🔨 Building image: ${IMAGE_NAME}:${PRIMARY_TAG} (variant: ${VARIANT})"
[[ -n "$IMAGE_VERSION" ]] && echo "🧭 Also tagging: ${IMAGE_NAME}:${IMAGE_VERSION}${TAG_SUFFIX}"
echo "💡 Build args:"
for arg in "${BUILD_ARGS[@]}"; do
  echo "  - ${arg#--build-arg }"
done
echo

# ────────────────────────────────────────────────
# Construct build command
# ────────────────────────────────────────────────
# PLATFORMS=linux/amd64,linux/arm64 builds both (needs --push, or Docker's
# containerd image store for --load).
BUILD_CMD=(
  docker buildx build
  --platform "${PLATFORMS:-linux/amd64}"
  --target "$VARIANT"
  "${BUILD_ARGS[@]}"
  -t "${IMAGE_NAME}:${PRIMARY_TAG}"
)

if [[ -n "$IMAGE_VERSION" ]]; then
  BUILD_CMD+=(-t "${IMAGE_NAME}:${IMAGE_VERSION}${TAG_SUFFIX}")
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

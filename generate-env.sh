#!/bin/bash
# generate-env.sh

set -euo pipefail

# For GitHub Actions: output for use in later steps
append_to_github_env() {
  local var="$1"
  local val="$2"
  if [[ -n "$val" ]]; then
    echo "${var}=${val}" >> "$GITHUB_ENV"
  else
    echo "# Skipping unset ${var}" >&2
  fi
}

get_latest_github_release() {
  local repo="$1"
  local attempt=1
  local max_attempts=3
  local delay=10
  local response

  while (( attempt <= max_attempts )); do
    response=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null)
    if [[ $? -eq 0 && ! "$response" =~ "API rate limit exceeded" && ! "$response" =~ "403 Forbidden" ]]; then
      echo "$response" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/'
      return 0
    fi
    if (( attempt < max_attempts )); then
      echo "[WARN] GitHub API returned 403 or error for $repo, attempt $attempt/$max_attempts. Retrying in $delay seconds..." >&2
      sleep $delay
    fi
    ((attempt++))
  done

  echo "[ERROR] Failed to fetch latest release for $repo after $max_attempts attempts." >&2
  return 1
}

# Fetch versions
YQ_VERSION=$(get_latest_github_release "mikefarah/yq")
HELM_VERSION=$(get_latest_github_release "helm/helm")
YTT_VERSION=$(get_latest_github_release "carvel-dev/ytt")
KAPP_VERSION=$(get_latest_github_release "carvel-dev/kapp")
KCTRL_VERSION=$(get_latest_github_release "carvel-dev/kapp-controller")
KBLD_VERSION=$(get_latest_github_release "carvel-dev/kbld")
IMGPKG_VERSION=$(get_latest_github_release "carvel-dev/imgpkg")
VENDIR_VERSION=$(get_latest_github_release "carvel-dev/vendir")
K9S_VERSION=$(get_latest_github_release "derailed/k9s")
TANZU_CLI_VERSION=$(get_latest_github_release "vmware-tanzu/tanzu-cli")
VELERO_VERSION=$(get_latest_github_release "vmware-tanzu/velero")
KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt | sed 's/^v//')
KUBECTX_VERSION=$(get_latest_github_release "ahmetb/kubectx")
KUBECOLOR_VERSION=$(get_latest_github_release "kubecolor/kubecolor")
EZA_VERSION=$(get_latest_github_release "eza-community/eza")

# Export and append to GitHub Actions environment
for var in YQ_VERSION HELM_VERSION YTT_VERSION KAPP_VERSION KCTRL_VERSION \
           KBLD_VERSION IMGPKG_VERSION VENDIR_VERSION K9S_VERSION \
           TANZU_CLI_VERSION VELERO_VERSION KUBECTL_VERSION KUBECTX_VERSION \
           KUBECOLOR_VERSION EZA_VERSION; do
  append_to_github_env "$var" "${!var:-}"
done

# Add the image version (e.g. Git commit hash)
echo "IMAGE_VERSION=${GITHUB_SHA:-unknown}" >> "$GITHUB_ENV"

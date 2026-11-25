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

# Authenticate to api.github.com when a token is available. Unauthenticated
# release lookups are limited to 60/hour per source IP, which a shared CI
# egress address exhausts quickly - and this script makes 16 of them per run.
GH_API_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

get_latest_github_release() {
  local repo="$1"
  local attempt=1
  local max_attempts=3
  local delay=10
  local response rc
  local url="https://api.github.com/repos/${repo}/releases/latest"

  while (( attempt <= max_attempts )); do
    # `rc=0; ... || rc=$?` is required: under `set -e` a bare
    # `response=$(curl ...)` aborts the whole script the moment curl fails,
    # so the retry loop below would never get a chance to run.
    rc=0
    if [[ -n "$GH_API_TOKEN" ]]; then
      response=$(curl -fsSL \
        -H "Authorization: Bearer ${GH_API_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "$url") || rc=$?
    else
      response=$(curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        "$url") || rc=$?
    fi

    if (( rc == 0 )) && [[ -n "$response" ]]; then
      echo "$response" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/'
      return 0
    fi

    if (( attempt < max_attempts )); then
      echo "[WARN] GitHub API lookup for $repo failed (curl rc=$rc), attempt $attempt/$max_attempts. Retrying in $delay seconds..." >&2
      sleep "$delay"
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
FZF_VERSION=$(get_latest_github_release "junegunn/fzf")
DIRENV_VERSION=$(get_latest_github_release "direnv/direnv")

# Export and append to GitHub Actions environment
for var in YQ_VERSION HELM_VERSION YTT_VERSION KAPP_VERSION KCTRL_VERSION \
           KBLD_VERSION IMGPKG_VERSION VENDIR_VERSION K9S_VERSION \
           TANZU_CLI_VERSION VELERO_VERSION KUBECTL_VERSION KUBECTX_VERSION \
           KUBECOLOR_VERSION EZA_VERSION FZF_VERSION DIRENV_VERSION; do
  append_to_github_env "$var" "${!var:-}"
done

# Add the image version (e.g. Git commit hash)
echo "IMAGE_VERSION=${GITHUB_SHA:-unknown}" >> "$GITHUB_ENV"

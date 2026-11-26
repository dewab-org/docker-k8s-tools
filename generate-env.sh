#!/bin/bash
# generate-env.sh
#
# Resolves every bundled tool to its latest upstream release and appends
# KEY=VALUE build args to $GITHUB_ENV, for every variant's tool group. For
# eza, direnv, zoxide, clusterctl and azd, which publish no checksum file, it
# also emits the per-arch SHA-256 digests GitHub records for each release
# asset, so the Dockerfile can verify those downloads too.

set -euo pipefail

: "${GITHUB_ENV:?GITHUB_ENV must point at the file to append build args to}"
command -v jq >/dev/null || { echo "[ERROR] jq is required" >&2; exit 1; }

append_to_github_env() {
  local var="$1"
  local val="$2"
  if [[ -n "$val" ]]; then
    echo "${var}=${val}" >> "$GITHUB_ENV"
  else
    echo "[ERROR] Could not resolve ${var}" >&2
    exit 1
  fi
}

# Authenticate to api.github.com when a token is available. Unauthenticated
# release lookups are limited to 60/hour per source IP, which a shared CI
# egress address exhausts quickly - and this script makes ~20 of them per run.
GH_API_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

# github_api <path>: GET https://api.github.com/<path>, with retries.
github_api() {
  local path="$1"
  local attempt=1
  local max_attempts=3
  local delay=10
  local response rc
  local url="https://api.github.com/${path}"
  local -a auth=()
  [[ -n "$GH_API_TOKEN" ]] && auth=(-H "Authorization: Bearer ${GH_API_TOKEN}")

  while (( attempt <= max_attempts )); do
    # `rc=0; ... || rc=$?` is required: under `set -e` a bare
    # `response=$(curl ...)` aborts the whole script the moment curl fails,
    # so the retry loop below would never get a chance to run.
    rc=0
    # ${auth[@]+...} keeps macOS's bash 3.2 happy with an empty array under -u.
    response=$(curl -fsSL ${auth[@]+"${auth[@]}"} \
      -H "Accept: application/vnd.github+json" \
      "$url") || rc=$?

    if (( rc == 0 )) && [[ -n "$response" ]]; then
      printf '%s\n' "$response"
      return 0
    fi

    if (( attempt < max_attempts )); then
      echo "[WARN] GitHub API lookup for $path failed (curl rc=$rc), attempt $attempt/$max_attempts. Retrying in $delay seconds..." >&2
      sleep "$delay"
    fi
    ((attempt++))
  done

  echo "[ERROR] Failed to fetch $path after $max_attempts attempts." >&2
  return 1
}

# get_latest_github_release_json <owner/repo>: the releases/latest JSON.
get_latest_github_release_json() { github_api "repos/$1/releases/latest"; }

# get_latest_prefixed_release_json <owner/repo> <tag prefix>: the newest
# stable release whose tag starts with <prefix>, for monorepos whose
# "latest" release may belong to a different component.
get_latest_prefixed_release_json() {
  github_api "repos/$1/releases?per_page=50" |
    jq --arg p "$2" 'map(select(.draft | not) | select(.prerelease | not) | select(.tag_name | startswith($p))) | first'
}

# release_version <json> [tag prefix]: tag_name without the prefix (default "v").
release_version() { jq -r --arg p "${2:-v}" '.tag_name | ltrimstr($p) | ltrimstr("v")' <<<"$1"; }

# asset_digest <json> <asset name>: the asset's SHA-256, without "sha256:".
asset_digest() {
  jq -r --arg n "$2" '.assets[] | select(.name == $n) | .digest // "" | ltrimstr("sha256:")' <<<"$1"
}

latest() { release_version "$(get_latest_github_release_json "$1")"; }

# ----- standard
YQ_VERSION=$(latest "mikefarah/yq")
HELM_VERSION=$(latest "helm/helm")
KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt | sed 's/^v//')
HELMFILE_VERSION=$(latest "helmfile/helmfile")
KUSTOMIZE_VERSION=$(release_version "$(get_latest_prefixed_release_json "kubernetes-sigs/kustomize" "kustomize/")" "kustomize/")
K9S_VERSION=$(latest "derailed/k9s")
STERN_VERSION=$(latest "stern/stern")
KUBECONFORM_VERSION=$(latest "yannh/kubeconform")
KREW_VERSION=$(latest "kubernetes-sigs/krew")
KUBECTX_VERSION=$(latest "ahmetb/kubectx")
KUBECOLOR_VERSION=$(latest "kubecolor/kubecolor")
FZF_VERSION=$(latest "junegunn/fzf")
FZF_TAB_VERSION=$(latest "Aloxaf/fzf-tab")
STARSHIP_VERSION=$(latest "starship/starship")

eza_json=$(get_latest_github_release_json "eza-community/eza")
EZA_VERSION=$(release_version "$eza_json")
EZA_SHA256_AMD64=$(asset_digest "$eza_json" "eza_x86_64-unknown-linux-gnu.tar.gz")
EZA_SHA256_ARM64=$(asset_digest "$eza_json" "eza_aarch64-unknown-linux-gnu.tar.gz")

direnv_json=$(get_latest_github_release_json "direnv/direnv")
DIRENV_VERSION=$(release_version "$direnv_json")
DIRENV_SHA256_AMD64=$(asset_digest "$direnv_json" "direnv.linux-amd64")
DIRENV_SHA256_ARM64=$(asset_digest "$direnv_json" "direnv.linux-arm64")

zoxide_json=$(get_latest_github_release_json "ajeetdsouza/zoxide")
ZOXIDE_VERSION=$(release_version "$zoxide_json")
ZOXIDE_SHA256_AMD64=$(asset_digest "$zoxide_json" "zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz")
ZOXIDE_SHA256_ARM64=$(asset_digest "$zoxide_json" "zoxide-${ZOXIDE_VERSION}-aarch64-unknown-linux-musl.tar.gz")

# ----- tanzu
TANZU_CLI_VERSION=$(latest "vmware-tanzu/tanzu-cli")
VELERO_VERSION=$(latest "vmware-tanzu/velero")
YTT_VERSION=$(latest "carvel-dev/ytt")
KAPP_VERSION=$(latest "carvel-dev/kapp")
KCTRL_VERSION=$(latest "carvel-dev/kapp-controller")
KBLD_VERSION=$(latest "carvel-dev/kbld")
IMGPKG_VERSION=$(latest "carvel-dev/imgpkg")
VENDIR_VERSION=$(latest "carvel-dev/vendir")

clusterctl_json=$(get_latest_github_release_json "kubernetes-sigs/cluster-api")
CLUSTERCTL_VERSION=$(release_version "$clusterctl_json")
CLUSTERCTL_SHA256_AMD64=$(asset_digest "$clusterctl_json" "clusterctl-linux-amd64")
CLUSTERCTL_SHA256_ARM64=$(asset_digest "$clusterctl_json" "clusterctl-linux-arm64")

# ----- azure
KUBELOGIN_VERSION=$(latest "Azure/kubelogin")
# az is a Python application, installed from PyPI at this exact version.
AZURE_CLI_VERSION=$(curl -fsSL https://pypi.org/pypi/azure-cli/json | jq -r '.info.version')

azd_json=$(get_latest_prefixed_release_json "Azure/azure-dev" "azure-dev-cli_")
AZD_VERSION=$(release_version "$azd_json" "azure-dev-cli_")
AZD_SHA256_AMD64=$(asset_digest "$azd_json" "azd-linux-amd64.tar.gz")
AZD_SHA256_ARM64=$(asset_digest "$azd_json" "azd-linux-arm64.tar.gz")

# ----- openshift
# oc follows Red Hat's stable channel on the client mirror, not GitHub.
OC_VERSION=$(curl -fsSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/release.txt | awk '/^Name:/ { print $2 }')
ODO_VERSION=$(latest "redhat-developer/odo")
TKN_VERSION=$(latest "tektoncd/cli")

# Export and append to GitHub Actions environment
for var in KUBECTL_VERSION HELM_VERSION HELMFILE_VERSION KUSTOMIZE_VERSION \
           K9S_VERSION STERN_VERSION KUBECONFORM_VERSION KREW_VERSION \
           KUBECTX_VERSION KUBECOLOR_VERSION YQ_VERSION FZF_VERSION \
           FZF_TAB_VERSION STARSHIP_VERSION \
           EZA_VERSION EZA_SHA256_AMD64 EZA_SHA256_ARM64 \
           DIRENV_VERSION DIRENV_SHA256_AMD64 DIRENV_SHA256_ARM64 \
           ZOXIDE_VERSION ZOXIDE_SHA256_AMD64 ZOXIDE_SHA256_ARM64 \
           TANZU_CLI_VERSION VELERO_VERSION YTT_VERSION KAPP_VERSION \
           KCTRL_VERSION KBLD_VERSION IMGPKG_VERSION VENDIR_VERSION \
           CLUSTERCTL_VERSION CLUSTERCTL_SHA256_AMD64 CLUSTERCTL_SHA256_ARM64 \
           KUBELOGIN_VERSION AZURE_CLI_VERSION \
           AZD_VERSION AZD_SHA256_AMD64 AZD_SHA256_ARM64 \
           OC_VERSION ODO_VERSION TKN_VERSION; do
  append_to_github_env "$var" "${!var:-}"
done

# Add the image version (e.g. Git commit hash)
echo "IMAGE_VERSION=${GITHUB_SHA:-unknown}" >> "$GITHUB_ENV"

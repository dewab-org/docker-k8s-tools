#!/usr/bin/env bash
# Writes /etc/k8s-cli-toolkit/manifest.json for one k8s-cli-toolkit variant.
#
# Versions are read from the installed tools themselves, not from the build
# args, so the manifest describes exactly what this image ships. A tool that
# is installed but whose version cannot be read fails the build.
set -euo pipefail

: "${TOOLKIT_VARIANT:?}"
OUT=/etc/k8s-cli-toolkit/manifest.json

first_version() { grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1; }

# <name>|<version command, run only when <name> is on PATH>
probes=(
  # standard
  'kubectl|kubectl version --client -o json | jq -r .clientVersion.gitVersion'
  'helm|helm version --short'
  'helmfile|helmfile --version'
  'kustomize|kustomize version'
  'k9s|k9s version -s'
  'stern|stern --version'
  'kubeconform|kubeconform -v'
  'kubectl-krew|kubectl-krew version | grep GitTag'
  'kubectx|kubectx -V'
  'kubens|kubens -V'
  'kubecolor|kubecolor --kubecolor-version'
  'yq|yq --version'
  'jq|jq --version'
  'fzf|fzf --version'
  'eza|eza --version | sed -n 2p'
  'direnv|direnv version'
  'starship|starship --version'
  'zoxide|zoxide --version'
  'zsh|zsh --version'
  'git|git --version'
  'vim|vim --version | head -n1'
  'curl|curl --version | head -n1'
  # tanzu
  'tanzu|tanzu version | grep "^version"'
  'velero|velero version --client-only'
  'clusterctl|clusterctl version -o short'
  'ytt|ytt version'
  'kapp|kapp version'
  'kctrl|kctrl version'
  'kbld|kbld version'
  'imgpkg|imgpkg version'
  'vendir|vendir version'
  'kubectl-vsphere|kubectl-vsphere version'
  # azure
  'az|az version -o json | jq -r ".\"azure-cli\""'
  'azd|azd version'
  'kubelogin|kubelogin --version | grep -i "git hash"'
  # openshift
  'oc|oc version --client | grep "^Client Version"'
  'odo|odo version --client'
  'tkn|tkn version --component client'
)

tools='{}'
for probe in "${probes[@]}"; do
  name=${probe%%|*}
  cmd=${probe#*|}
  command -v "${name}" >/dev/null || continue
  # Run with no kubeconfig and no stdin, so nothing tries to reach a cluster.
  version=$(KUBECONFIG=/dev/null bash -c "${cmd}" </dev/null 2>/dev/null | first_version || true)
  if [[ -z ${version} ]]; then
    echo "could not read the version of ${name} (${cmd})" >&2
    exit 1
  fi
  tools=$(jq --arg n "${name}" --arg v "${version}" '. + {($n): $v}' <<<"${tools}")
done

mkdir -p "$(dirname "${OUT}")"
jq -n \
  --arg image "k8s-cli-toolkit" \
  --arg variant "${TOOLKIT_VARIANT}" \
  --arg version "${K8S_TOOLKIT_VERSION:-unknown}" \
  --arg platform "linux/$(dpkg --print-architecture)" \
  --arg base "debian $(cat /etc/debian_version)" \
  --argjson tools "${tools}" \
  '{image: $image, variant: $variant, version: $version, platform: $platform, base: $base, tools: $tools}' \
  > "${OUT}"
cat "${OUT}"

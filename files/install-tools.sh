#!/usr/bin/env bash
# Builder-stage installer for the k8s-cli-toolkit images (run by the Dockerfile).
#
#   install-tools.sh <group> <prefix>
#
# Installs one tool group (standard, tanzu, azure, openshift) into
# <prefix>/bin and <prefix>/share, which the Dockerfile copies onto
# /usr/local of each image variant that includes the group.
#
# Every download is verified against the SHA-256 its upstream publishes.
# Versions arrive as <TOOL>_VERSION build args resolved by generate-env.sh.
# Upstreams that publish no checksum file get their asset digest from the
# GitHub release API instead, passed in as <TOOL>_SHA256_<ARCH>. A missing or
# malformed checksum fails the build: nothing is installed unverified.
set -euo pipefail

GROUP=${1:?usage: install-tools.sh <group> <prefix>}
PREFIX=${2:?usage: install-tools.sh <group> <prefix>}
: "${TARGET_OS:?}" "${TARGET_ARCH:?}"

BIN=${PREFIX}/bin
SHARE=${PREFIX}/share
COMPLETIONS=${SHARE}/zsh/site-functions
GH=https://github.com
SRC=$(cd "$(dirname "$0")" && pwd)
mkdir -p "${BIN}" "${COMPLETIONS}"
export PATH="${BIN}:${PATH}"

case "${TARGET_ARCH}" in
  amd64) UNAME_ARCH=x86_64 ;;
  arm64) UNAME_ARCH=aarch64 ;;
  *) echo "unsupported TARGET_ARCH=${TARGET_ARCH}" >&2; exit 1 ;;
esac
ARCH_UPPER=${TARGET_ARCH^^}

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
cd "${WORK}"

curl_() { curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors "$@"; }

# sum_from_list <url> <asset>: the SHA-256 for <asset> from a
# "<sha256>  <name>" list, tolerating "*name" and "./path/name" forms.
sum_from_list() {
  curl_ "$1" | awk -v f="$2" '
    { n = $2; sub(/^\*/, "", n); sub(/^.*\//, "", n) }
    n == f && !found { print $1; found = 1 }'
}

# sum_file <url>: a file holding just the SHA-256 (optionally with a name).
sum_file() { curl_ "$1" | awk 'NR == 1 { print $1 }'; }

# digest_arg <TOOL>: the per-arch SHA-256 passed in as a build arg.
digest_arg() { local v="${1}_SHA256_${ARCH_UPPER}"; printf '%s' "${!v:-}"; }

# get <url> <local-file> <sha256>: download, then verify or fail the build.
get() {
  local url=$1 file=$2 want=$3
  if [[ ! ${want} =~ ^[0-9a-f]{64}$ ]]; then
    echo "no valid SHA-256 for ${url} (got '${want}')" >&2
    exit 1
  fi
  curl_ -o "${file}" "${url}"
  echo "${want}  ${file}" | sha256sum --check --strict --quiet -
  echo "verified ${url##*/}"
}

# completion <name> <generator...>: queue a zsh completion to generate once
# the group is installed and stripped. Running a binary before strip can leave
# a forked helper (azd's telemetry uploader) holding it open, and strip then
# fails with "Text file busy".
PENDING_COMPLETIONS=()
completion() {
  local queued
  printf -v queued '%q ' "$@"
  PENDING_COMPLETIONS+=("${queued}")
}

# generate_completion <name> <generator...>. Missing completions only warn:
# not every tool ships a generator.
generate_completion() {
  local name=$1; shift
  # Carvel tools append a "Succeeded" status line to their output.
  if "$@" 2>/dev/null | grep -v '^Succeeded' > "${COMPLETIONS}/_${name}" && [[ -s ${COMPLETIONS}/_${name} ]]; then
    return 0
  fi
  rm -f "${COMPLETIONS}/_${name}"
  echo "warning: no zsh completion generated for ${name}" >&2
}

# ================================================================
# standard: Kubernetes essentials and the interactive shell
# ================================================================
install_standard() {
  local base asset tool

  # kubectl
  base="https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/${TARGET_OS}/${TARGET_ARCH}"
  get "${base}/kubectl" kubectl "$(sum_file "${base}/kubectl.sha256")"
  install -m 755 kubectl "${BIN}/kubectl"

  # helm
  asset="helm-v${HELM_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
  get "https://get.helm.sh/${asset}" helm.tgz "$(sum_from_list "https://get.helm.sh/${asset}.sha256sum" "${asset}")"
  tar -xzf helm.tgz --strip-components=1 "${TARGET_OS}-${TARGET_ARCH}/helm"
  install -m 755 helm "${BIN}/helm"

  # helmfile
  base="${GH}/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}"
  asset="helmfile_${HELMFILE_VERSION}_${TARGET_OS}_${TARGET_ARCH}.tar.gz"
  get "${base}/${asset}" helmfile.tgz "$(sum_from_list "${base}/helmfile_${HELMFILE_VERSION}_checksums.txt" "${asset}")"
  tar -xzf helmfile.tgz helmfile
  install -m 755 helmfile "${BIN}/helmfile"

  # kustomize (standalone: newer than the copy built into kubectl)
  base="${GH}/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}"
  asset="kustomize_v${KUSTOMIZE_VERSION}_${TARGET_OS}_${TARGET_ARCH}.tar.gz"
  get "${base}/${asset}" kustomize.tgz "$(sum_from_list "${base}/checksums.txt" "${asset}")"
  tar -xzf kustomize.tgz kustomize
  install -m 755 kustomize "${BIN}/kustomize"

  # k9s
  base="${GH}/derailed/k9s/releases/download/v${K9S_VERSION}"
  asset="k9s_${TARGET_OS^}_${TARGET_ARCH}.tar.gz"
  get "${base}/${asset}" k9s.tgz "$(sum_from_list "${base}/checksums.sha256" "${asset}")"
  tar -xzf k9s.tgz k9s
  install -m 755 k9s "${BIN}/k9s"

  # stern: multi-pod log tailing
  base="${GH}/stern/stern/releases/download/v${STERN_VERSION}"
  asset="stern_${STERN_VERSION}_${TARGET_OS}_${TARGET_ARCH}.tar.gz"
  get "${base}/${asset}" stern.tgz "$(sum_from_list "${base}/checksums.txt" "${asset}")"
  tar -xzf stern.tgz stern
  install -m 755 stern "${BIN}/stern"

  # kubeconform: offline manifest validation
  base="${GH}/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}"
  asset="kubeconform-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
  get "${base}/${asset}" kubeconform.tgz "$(sum_from_list "${base}/CHECKSUMS" "${asset}")"
  tar -xzf kubeconform.tgz kubeconform
  install -m 755 kubeconform "${BIN}/kubeconform"

  # krew: kubectl plugin manager (plugins land in the persistent ~/.krew)
  base="${GH}/kubernetes-sigs/krew/releases/download/v${KREW_VERSION}"
  asset="krew-${TARGET_OS}_${TARGET_ARCH}.tar.gz"
  get "${base}/${asset}" krew.tgz "$(sum_file "${base}/${asset}.sha256")"
  tar -xzf krew.tgz "./krew-${TARGET_OS}_${TARGET_ARCH}"
  install -m 755 "krew-${TARGET_OS}_${TARGET_ARCH}" "${BIN}/kubectl-krew"

  # kubectx / kubens
  base="${GH}/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}"
  for tool in kubectx kubens; do
    asset="${tool}_v${KUBECTX_VERSION}_${TARGET_OS}_${TARGET_ARCH/amd64/x86_64}.tar.gz"
    get "${base}/${asset}" "${tool}.tgz" "$(sum_from_list "${base}/checksums.txt" "${asset}")"
    tar -xzf "${tool}.tgz" "${tool}"
    install -m 755 "${tool}" "${BIN}/${tool}"
  done

  # kubecolor
  base="${GH}/kubecolor/kubecolor/releases/download/v${KUBECOLOR_VERSION}"
  asset="kubecolor_${KUBECOLOR_VERSION}_${TARGET_OS}_${TARGET_ARCH}.tar.gz"
  get "${base}/${asset}" kubecolor.tgz "$(sum_from_list "${base}/checksums.txt" "${asset}")"
  tar -xzf kubecolor.tgz kubecolor
  install -m 755 kubecolor "${BIN}/kubecolor"

  # yq: one checksum file with many hash columns, named by checksums_hashes_order
  local col
  base="${GH}/mikefarah/yq/releases/download/v${YQ_VERSION}"
  asset="yq_${TARGET_OS}_${TARGET_ARCH}"
  col=$(curl_ "${base}/checksums_hashes_order" | grep -nx 'SHA-256' | cut -d: -f1)
  get "${base}/${asset}" yq "$(curl_ "${base}/checksums" | awk -v f="${asset}" -v c="$((col + 1))" '$1 == f { print $c }')"
  install -m 755 yq "${BIN}/yq"

  # fzf
  base="${GH}/junegunn/fzf/releases/download/v${FZF_VERSION}"
  asset="fzf-${FZF_VERSION}-${TARGET_OS}_${TARGET_ARCH}.tar.gz"
  get "${base}/${asset}" fzf.tgz "$(sum_from_list "${base}/fzf_${FZF_VERSION}_checksums.txt" "${asset}")"
  tar -xzf fzf.tgz fzf
  install -m 755 fzf "${BIN}/fzf"

  # starship
  base="${GH}/starship/starship/releases/download/v${STARSHIP_VERSION}"
  asset="starship-${UNAME_ARCH}-unknown-linux-musl.tar.gz"
  get "${base}/${asset}" starship.tgz "$(sum_file "${base}/${asset}.sha256")"
  tar -xzf starship.tgz starship
  install -m 755 starship "${BIN}/starship"

  # eza, direnv, zoxide: no checksum files upstream; digests from generate-env.sh
  asset="eza_${UNAME_ARCH}-unknown-linux-gnu.tar.gz"
  get "${GH}/eza-community/eza/releases/download/v${EZA_VERSION}/${asset}" eza.tgz "$(digest_arg EZA)"
  tar -xzf eza.tgz ./eza
  install -m 755 eza "${BIN}/eza"

  get "${GH}/direnv/direnv/releases/download/v${DIRENV_VERSION}/direnv.${TARGET_OS}-${TARGET_ARCH}" direnv "$(digest_arg DIRENV)"
  install -m 755 direnv "${BIN}/direnv"

  asset="zoxide-${ZOXIDE_VERSION}-${UNAME_ARCH}-unknown-linux-musl.tar.gz"
  get "${GH}/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/${asset}" zoxide.tgz "$(digest_arg ZOXIDE)"
  mkdir zoxide && tar -xzf zoxide.tgz -C zoxide
  install -m 755 zoxide/zoxide "${BIN}/zoxide"
  install -m 644 zoxide/completions/_zoxide "${COMPLETIONS}/_zoxide"

  # fzf-tab, pinned to its latest release rather than the default branch
  git -c advice.detachedHead=false clone --quiet --depth=1 --branch "v${FZF_TAB_VERSION}" \
    https://github.com/Aloxaf/fzf-tab.git "${SHARE}/fzf-tab"
  rm -rf "${SHARE}/fzf-tab/.git"

  completion kubectl   kubectl completion zsh
  completion helm      helm completion zsh
  completion helmfile  helmfile completion zsh
  completion kustomize kustomize completion zsh
  completion k9s       k9s completion zsh
  completion stern     stern --completion zsh
  completion yq        yq shell-completion zsh
  completion starship  starship completions zsh
  # fzf key bindings (Ctrl-T, Ctrl-R, Alt-C) and ** completion.
  mkdir -p "${SHARE}/fzf"
  fzf --zsh > "${SHARE}/fzf/fzf.zsh"
}

# ================================================================
# tanzu: VMware Tanzu, vSphere Supervisor, Carvel, Cluster API, Velero
# ================================================================
install_tanzu() {
  local base asset spec repo tool var version_var

  # tanzu (upstream labels the linux/arm64 build "unstable")
  base="${GH}/vmware-tanzu/tanzu-cli/releases/download/v${TANZU_CLI_VERSION}"
  asset="tanzu-cli-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
  [[ ${TARGET_OS}/${TARGET_ARCH} == linux/arm64 ]] && asset="tanzu-cli-${TARGET_OS}-${TARGET_ARCH}-unstable.tar.gz"
  get "${base}/${asset}" tanzu.tgz "$(sum_from_list "${base}/tanzu-cli-binaries-checksums.txt" "${asset}")"
  mkdir tanzu && tar -xzf tanzu.tgz -C tanzu
  install -m 755 tanzu/"v${TANZU_CLI_VERSION}"/tanzu-cli-* "${BIN}/tanzu"

  # Carvel: <repo>:<binary>:<version var prefix>
  for spec in ytt:ytt:YTT kapp:kapp:KAPP kapp-controller:kctrl:KCTRL \
              kbld:kbld:KBLD imgpkg:imgpkg:IMGPKG vendir:vendir:VENDIR; do
    IFS=: read -r repo tool var <<<"${spec}"
    version_var="${var}_VERSION"
    base="${GH}/carvel-dev/${repo}/releases/download/v${!version_var}"
    asset="${tool}-${TARGET_OS}-${TARGET_ARCH}"
    get "${base}/${asset}" "${tool}" "$(sum_from_list "${base}/checksums.txt" "${asset}")"
    install -m 755 "${tool}" "${BIN}/${tool}"
  done

  # velero
  base="${GH}/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}"
  asset="velero-v${VELERO_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
  get "${base}/${asset}" velero.tgz "$(sum_from_list "${base}/CHECKSUM" "${asset}")"
  tar -xzf velero.tgz --strip-components=1 "velero-v${VELERO_VERSION}-${TARGET_OS}-${TARGET_ARCH}/velero"
  install -m 755 velero "${BIN}/velero"

  # clusterctl (Cluster API, which TKG and vSphere Supervisor are built on)
  get "${GH}/kubernetes-sigs/cluster-api/releases/download/v${CLUSTERCTL_VERSION}/clusterctl-${TARGET_OS}-${TARGET_ARCH}" \
    clusterctl "$(digest_arg CLUSTERCTL)"
  install -m 755 clusterctl "${BIN}/clusterctl"

  # kubectl-vsphere: vendored, and only published for linux/amd64
  if [[ ${TARGET_ARCH} == amd64 ]]; then
    install -m 755 "${SRC}/kubectl-vsphere" "${BIN}/kubectl-vsphere"
  fi

  completion tanzu      tanzu completion zsh
  completion velero     velero completion zsh
  completion clusterctl clusterctl completion zsh
  for tool in ytt kapp kctrl kbld imgpkg vendir; do
    completion "${tool}" "${tool}" completion zsh
  done
}

# ================================================================
# azure: AKS auth and the Azure Developer CLI (az itself is installed
# in the image, because it is a Python application, not one binary)
# ================================================================
install_azure() {
  local base asset
  # Keep azd from forking its telemetry uploader during the build.
  export AZD_COLLECT_TELEMETRY=no

  # kubelogin: Entra ID credential plugin for AKS kubeconfigs
  base="${GH}/Azure/kubelogin/releases/download/v${KUBELOGIN_VERSION}"
  asset="kubelogin-${TARGET_OS}-${TARGET_ARCH}.zip"
  get "${base}/${asset}" kubelogin.zip "$(sum_file "${base}/${asset}.sha256")"
  unzip -q -j kubelogin.zip "bin/${TARGET_OS}_${TARGET_ARCH}/kubelogin"
  install -m 755 kubelogin "${BIN}/kubelogin"

  # azd
  asset="azd-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
  get "${GH}/Azure/azure-dev/releases/download/azure-dev-cli_${AZD_VERSION}/${asset}" azd.tgz "$(digest_arg AZD)"
  mkdir azd && tar -xzf azd.tgz -C azd
  install -m 755 "azd/azd-${TARGET_OS}-${TARGET_ARCH}" "${BIN}/azd"

  completion kubelogin kubelogin completion zsh
  completion azd       azd completion zsh
}

# ================================================================
# openshift: oc, odo, and the Tekton (OpenShift Pipelines) CLI
# ================================================================
install_openshift() {
  local base asset

  # oc, from Red Hat's client mirror (rhel9 builds are glibc 2.34+, which Debian 13 satisfies)
  base="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_VERSION}"
  asset="openshift-client-${TARGET_OS}-${TARGET_ARCH}-rhel9-${OC_VERSION}.tar.gz"
  get "${base}/${asset}" oc.tgz "$(sum_from_list "${base}/sha256sum.txt" "${asset}")"
  tar -xzf oc.tgz oc
  install -m 755 oc "${BIN}/oc"

  # odo
  base="https://mirror.openshift.com/pub/openshift-v4/clients/odo/v${ODO_VERSION}"
  get "${base}/odo-${TARGET_OS}-${TARGET_ARCH}" odo "$(sum_file "${base}/odo-${TARGET_OS}-${TARGET_ARCH}.sha256")"
  install -m 755 odo "${BIN}/odo"

  # tkn
  base="${GH}/tektoncd/cli/releases/download/v${TKN_VERSION}"
  asset="tkn_${TKN_VERSION}_${TARGET_OS^}_${UNAME_ARCH}.tar.gz"
  get "${base}/${asset}" tkn.tgz "$(sum_from_list "${base}/checksums.txt" "${asset}")"
  tar -xzf tkn.tgz tkn
  install -m 755 tkn "${BIN}/tkn"

  completion oc  oc completion zsh
  completion odo odo completion zsh
  completion tkn tkn completion zsh
}

case "${GROUP}" in
  standard|tanzu|azure|openshift) "install_${GROUP}" ;;
  *) echo "unknown tool group: ${GROUP}" >&2; exit 1 ;;
esac

# Strip symbols (Go buildinfo survives, so scanners still see versions).
strip --strip-unneeded "${BIN}"/*

for queued in "${PENDING_COMPLETIONS[@]}"; do
  eval "generate_completion ${queued}"
done
ls -l "${BIN}"

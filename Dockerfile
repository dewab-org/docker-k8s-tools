# k8s-cli-toolkit, in five variants (build one with --target):
#
#   standard   Kubernetes essentials and the interactive shell
#   tanzu      standard + Tanzu, vSphere Supervisor, Carvel, Cluster API, Velero
#   azure      standard + az, azd, kubelogin
#   openshift  standard + oc, odo, tkn
#   all        everything above (the default target)
#
# Each tool group is downloaded and verified once in its own builder stage;
# the variants then copy the groups they include onto /usr/local.

# ================================
# Builder base
# ================================
FROM debian:trixie-slim AS fetch
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends binutils ca-certificates curl git jq unzip && \
    rm -rf /var/lib/apt/lists/*

# TARGETOS/TARGETARCH are populated by BuildKit from --platform. Deriving
# TARGET_OS/TARGET_ARCH from them is what makes a multi-platform build fetch
# the right binaries: without it, every platform downloads amd64 artifacts and
# the arm64 image publishes successfully, then fails the moment it is run.
# An explicit --build-arg TARGET_ARCH=... still overrides the derived value.
ARG TARGETOS
ARG TARGETARCH
ARG TARGET_OS=${TARGETOS:-linux}
ARG TARGET_ARCH=${TARGETARCH:-amd64}

COPY files/install-tools.sh files/kubectl-vsphere /build/

# Tool versions (and digests for upstreams without checksum files) are
# resolved by generate-env.sh. ARGs reach RUN as environment variables, which
# is how install-tools.sh reads them; each group declares only its own, so a
# version bump rebuilds only that group.

# ================================
# Tool groups
# ================================
FROM fetch AS tools-standard
ARG KUBECTL_VERSION HELM_VERSION HELMFILE_VERSION KUSTOMIZE_VERSION \
    K9S_VERSION STERN_VERSION KUBECONFORM_VERSION KREW_VERSION \
    KUBECTX_VERSION KUBECOLOR_VERSION YQ_VERSION FZF_VERSION FZF_TAB_VERSION \
    STARSHIP_VERSION \
    EZA_VERSION EZA_SHA256_AMD64 EZA_SHA256_ARM64 \
    DIRENV_VERSION DIRENV_SHA256_AMD64 DIRENV_SHA256_ARM64 \
    ZOXIDE_VERSION ZOXIDE_SHA256_AMD64 ZOXIDE_SHA256_ARM64
RUN /build/install-tools.sh standard /out

FROM fetch AS tools-tanzu
ARG TANZU_CLI_VERSION VELERO_VERSION YTT_VERSION KAPP_VERSION KCTRL_VERSION \
    KBLD_VERSION IMGPKG_VERSION VENDIR_VERSION \
    CLUSTERCTL_VERSION CLUSTERCTL_SHA256_AMD64 CLUSTERCTL_SHA256_ARM64
RUN /build/install-tools.sh tanzu /out

FROM fetch AS tools-azure
ARG KUBELOGIN_VERSION AZD_VERSION AZD_SHA256_AMD64 AZD_SHA256_ARM64
RUN /build/install-tools.sh azure /out

FROM fetch AS tools-openshift
ARG OC_VERSION ODO_VERSION TKN_VERSION
RUN /build/install-tools.sh openshift /out

# ================================
# Runtime base: Debian, the shell, and the standard tools
# ================================
FROM debian:trixie-slim AS runtime
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

ARG IMAGE_VERSION

LABEL org.opencontainers.image.title="k8s-cli-toolkit" \
      org.opencontainers.image.description="Kubernetes CLI tools in an interactive zsh environment" \
      org.opencontainers.image.source="https://github.com/dewab-org/docker-k8s-tools" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.authors="dwhicker@bifrost.cc"

# `apt-get upgrade` picks up Debian security fixes published since the base
# image was cut; the weekly no-cache rebuild depends on it.
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl git jq less locales vim \
      zsh zsh-autosuggestions zsh-syntax-highlighting && \
    sed -i '/^# en_US.UTF-8/s/^# //' /etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/*

COPY --from=tools-standard /out/ /usr/local/

COPY --chmod=755 files/entrypoint.sh /entrypoint.sh
COPY --chmod=755 files/write-manifest.sh /usr/local/libexec/k8s-cli-toolkit/write-manifest.sh
COPY files/banner.txt /banner.txt
# Default tool configs (Starship, kubecolor, k9s). A file of the same name
# under the user's ~/.config takes precedence; see zshrc and entrypoint.sh.
COPY files/config/ /usr/local/share/k8s-cli-toolkit/config/
COPY files/zshrc /usr/local/share/k8s-cli-toolkit/zshrc

RUN cat /usr/local/share/k8s-cli-toolkit/zshrc >> /etc/zsh/zshrc && \
    mkdir -p /k8s /work

# LANG must be in the environment: locale-gen alone leaves the shell on the
# POSIX locale, which garbles the prompt's UTF-8 glyphs.
ENV LANG=en_US.UTF-8 \
    HOME=/k8s \
    K8S_TOOLKIT_VERSION=${IMAGE_VERSION}
WORKDIR /work

# Runs as root on purpose: entrypoint.sh installs CAs from /ca into the system
# trust store, and dropping to a non-root USER broke rootless Podman (bbd08cb).

# Not a listening service: the pinniped / kubectl-vsphere login flow needs a
# local callback port, which the documented `docker run -p 80:80` maps.
EXPOSE 80

CMD ["/entrypoint.sh"]

# Azure CLI layer, shared by the azure and all variants. Microsoft's apt repo
# has no Debian 13 suite and its newest arm64 package is years old, so az is
# installed from PyPI into a venv, pinned to the release generate-env.sh
# resolved, the same way on both architectures.
FROM runtime AS runtime-az
ARG AZURE_CLI_VERSION
# Telemetry off by default (the Tanzu CEIP prompt is declined the same way);
# set either back to yes/true in the container to opt in.
ENV AZURE_CORE_COLLECT_TELEMETRY=false \
    AZD_COLLECT_TELEMETRY=no
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-venv && \
    rm -rf /var/lib/apt/lists/* && \
    python3 -m venv /opt/az && \
    /opt/az/bin/pip install --no-cache-dir --disable-pip-version-check "azure-cli==${AZURE_CLI_VERSION:?}" && \
    ln -s /opt/az/bin/az /opt/az/bin/register-python-argcomplete /usr/local/bin/ && \
    find /opt/az -name __pycache__ -type d -prune -exec rm -rf {} +

# ================================
# Variants
# ================================
FROM runtime AS standard
ENV TOOLKIT_VARIANT=standard
RUN /usr/local/libexec/k8s-cli-toolkit/write-manifest.sh

FROM runtime AS tanzu
COPY --from=tools-tanzu /out/ /usr/local/
COPY --chmod=755 files/tkgs-login files/tmc-get-kubeconfigs /usr/local/bin/
ENV TOOLKIT_VARIANT=tanzu
RUN /usr/local/libexec/k8s-cli-toolkit/write-manifest.sh

FROM runtime-az AS azure
COPY --from=tools-azure /out/ /usr/local/
ENV TOOLKIT_VARIANT=azure
RUN /usr/local/libexec/k8s-cli-toolkit/write-manifest.sh

FROM runtime AS openshift
COPY --from=tools-openshift /out/ /usr/local/
ENV TOOLKIT_VARIANT=openshift
RUN /usr/local/libexec/k8s-cli-toolkit/write-manifest.sh

# Last stage, so a plain `docker build .` produces the full image.
FROM runtime-az AS all
COPY --from=tools-tanzu /out/ /usr/local/
COPY --from=tools-azure /out/ /usr/local/
COPY --from=tools-openshift /out/ /usr/local/
COPY --chmod=755 files/tkgs-login files/tmc-get-kubeconfigs /usr/local/bin/
ENV TOOLKIT_VARIANT=all
RUN /usr/local/libexec/k8s-cli-toolkit/write-manifest.sh

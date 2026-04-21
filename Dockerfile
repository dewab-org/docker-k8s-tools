# ================================
# Builder Stage: Install Tools
# ================================
ARG TARGET_OS=${TARGET_OS:-linux}
ARG TARGET_ARCH=${TARGET_ARCH:-amd64}

FROM debian:bookworm-slim AS builder
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

ARG TARGET_OS
ARG TARGET_ARCH
ARG IMAGE_VERSION

ARG YQ_VERSION
ARG HELM_VERSION
ARG YTT_VERSION
ARG KAPP_VERSION
ARG KCTRL_VERSION
ARG KBLD_VERSION
ARG IMGPKG_VERSION
ARG VENDIR_VERSION
ARG K9S_VERSION
ARG TANZU_CLI_VERSION
ARG VELERO_VERSION
ARG KUBECTL_VERSION
ARG KUBECTX_VERSION
ARG KUBECOLOR_VERSION
ARG EZA_VERSION
ARG FZF_VERSION
ARG DIRENV_VERSION

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      curl git ca-certificates tar jq binutils locales && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# Download binaries separately using ADD to benefit from Docker layer caching
ADD https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_${TARGET_OS}_${TARGET_ARCH} /tmp/yq
ADD https://get.helm.sh/helm-v${HELM_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz /tmp/helm.tar.gz
ADD https://github.com/carvel-dev/ytt/releases/download/v${YTT_VERSION}/ytt-${TARGET_OS}-${TARGET_ARCH} /tmp/ytt
ADD https://github.com/carvel-dev/kapp/releases/download/v${KAPP_VERSION}/kapp-${TARGET_OS}-${TARGET_ARCH} /tmp/kapp
ADD https://github.com/carvel-dev/kapp-controller/releases/download/v${KCTRL_VERSION}/kctrl-${TARGET_OS}-${TARGET_ARCH} /tmp/kctrl
ADD https://github.com/carvel-dev/kbld/releases/download/v${KBLD_VERSION}/kbld-${TARGET_OS}-${TARGET_ARCH} /tmp/kbld
ADD https://github.com/carvel-dev/imgpkg/releases/download/v${IMGPKG_VERSION}/imgpkg-${TARGET_OS}-${TARGET_ARCH} /tmp/imgpkg
ADD https://github.com/carvel-dev/vendir/releases/download/v${VENDIR_VERSION}/vendir-${TARGET_OS}-${TARGET_ARCH} /tmp/vendir
ADD https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}/velero-v${VELERO_VERSION}-${TARGET_OS}-${TARGET_ARCH}.tar.gz /tmp/velero.tar.gz
ADD https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/${TARGET_OS}/${TARGET_ARCH}/kubectl /tmp/kubectl
ADD https://github.com/kubecolor/kubecolor/releases/download/v${KUBECOLOR_VERSION}/kubecolor_${KUBECOLOR_VERSION}_${TARGET_OS}_${TARGET_ARCH}.tar.gz /tmp/kubecolor.tar.gz
ADD https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-${TARGET_OS}_${TARGET_ARCH}.tar.gz /tmp/fzf.tar.gz
ADD https://github.com/direnv/direnv/releases/download/v${DIRENV_VERSION}/direnv.${TARGET_OS}-${TARGET_ARCH} /tmp/direnv

RUN curl -fSL -o /tmp/k9s.tar.gz "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_${TARGET_OS^}_${TARGET_ARCH}.tar.gz"
RUN EZA_ARCH=$(echo "$TARGET_ARCH" | sed 's/amd64/x86_64/;s/arm64/aarch64/') && \
    curl -fsSL -o /tmp/eza.tar.gz "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz"
RUN curl -fsSL -o /tmp/kubectx.tar.gz "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_${TARGET_OS}_${TARGET_ARCH/amd64/x86_64}.tar.gz"
RUN curl -fsSL -o /tmp/kubens.tar.gz "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_${TARGET_OS}_${TARGET_ARCH/amd64/x86_64}.tar.gz"
RUN TANZU_FILENAME="tanzu-cli-${TARGET_OS}-${TARGET_ARCH}.tar.gz" && \
    if [ "${TARGET_OS}" = "linux" ] && [ "${TARGET_ARCH}" = "arm64" ]; then \
      TANZU_FILENAME="tanzu-cli-${TARGET_OS}-${TARGET_ARCH}-unstable.tar.gz"; fi && \
    curl -fsSL -o /tmp/tanzu-cli.tar.gz "https://github.com/vmware-tanzu/tanzu-cli/releases/download/v${TANZU_CLI_VERSION}/${TANZU_FILENAME}"


# Extract and install tools
RUN install -m 755 /tmp/yq /usr/local/bin/yq && \
    install -m 755 /tmp/ytt /usr/local/bin/ytt && \
    install -m 755 /tmp/kapp /usr/local/bin/kapp && \
    install -m 755 /tmp/kctrl /usr/local/bin/kctrl && \
    install -m 755 /tmp/kbld /usr/local/bin/kbld && \
    install -m 755 /tmp/imgpkg /usr/local/bin/imgpkg && \
    install -m 755 /tmp/vendir /usr/local/bin/vendir && \
    install -m 755 /tmp/kubectl /usr/local/bin/kubectl && \
    tar -xzf /tmp/helm.tar.gz --strip-components=1 -C /usr/local/bin "${TARGET_OS}-${TARGET_ARCH}/helm" && \
    tar -xzf /tmp/k9s.tar.gz && install -m 755 k9s /usr/local/bin/k9s && \
    tar -xzf /tmp/velero.tar.gz --strip-components=1 -C /usr/local/bin "velero-v${VELERO_VERSION}-${TARGET_OS}-${TARGET_ARCH}/velero" && \
    tar -xzf /tmp/kubectx.tar.gz -C /usr/local/bin kubectx && chmod +x /usr/local/bin/kubectx && \
    tar -xzf /tmp/kubens.tar.gz -C /usr/local/bin kubens && chmod +x /usr/local/bin/kubens && \
    tar -xzf /tmp/kubecolor.tar.gz -C /tmp && install -m 755 /tmp/kubecolor /usr/local/bin/kubecolor && \
    tar -xzf /tmp/eza.tar.gz -C /tmp && install -m 755 /tmp/eza /usr/local/bin/eza && \
    tar -xzf /tmp/fzf.tar.gz -C /tmp && install -m 755 /tmp/fzf /usr/local/bin/fzf && \
    install -m 755 /tmp/direnv /usr/local/bin/direnv && \
    mkdir tanzu-extract && \
    tar -xzf /tmp/tanzu-cli.tar.gz -C tanzu-extract && \
    mv tanzu-extract/v${TANZU_CLI_VERSION}/tanzu-cli-* /usr/local/bin/tanzu && chmod +x /usr/local/bin/tanzu && \
    rm -rf /tmp/* tanzu-extract

# Powerlevel10k and zsh completions
RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /usr/local/share/powerlevel10k && \
    rm -rf /usr/local/share/powerlevel10k/.git && \
    git clone --depth=1 https://github.com/Aloxaf/fzf-tab.git /usr/local/share/fzf-tab && \
    rm -rf /usr/local/share/fzf-tab/.git && \
    mkdir -p /usr/local/share/zsh/site-functions && \
    kubectl completion zsh > /usr/local/share/zsh/site-functions/_kubectl && \
    helm completion zsh > /usr/local/share/zsh/site-functions/_helm && \
    ytt completion zsh > /usr/local/share/zsh/site-functions/_ytt 2>/dev/null || true && \
    imgpkg completion zsh | grep -v ^Succeeded > /usr/local/share/zsh/site-functions/_imgpkg 2>/dev/null || true && \
    kapp completion zsh | grep -v ^Succeeded > /usr/local/share/zsh/site-functions/_kapp 2>/dev/null || true && \
    kctrl completion zsh | grep -v ^Succeeded > /usr/local/share/zsh/site-functions/_kctrl 2>/dev/null || true && \
    vendir completion zsh | grep -v ^Succeeded > /usr/local/share/zsh/site-functions/_vendir 2>/dev/null || true && \
    k9s completion zsh > /usr/local/share/zsh/site-functions/_k9s 2>/dev/null || true && \
    tanzu completion zsh > /usr/local/share/zsh/site-functions/_tanzu 2>/dev/null || true && \
    velero completion zsh > /usr/local/share/zsh/site-functions/_velero 2>/dev/null || true && \
    yq completion zsh > /usr/local/share/zsh/site-functions/_yq 2>/dev/null || true

# Collect tool versions to display in the banner
RUN jq -n \
  --arg kubectl "$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')" \
  --arg helm "$(helm version --short)" \
  --arg ytt "$(ytt version 2>/dev/null | grep -Eo '[0-9.]+' | head -n1)" \
  --arg kapp "$(kapp version 2>/dev/null | grep -Eo '[0-9.]+' | head -n1)" \
  --arg kctrl "$(kctrl version 2>/dev/null | grep -Eo '[0-9.]+' | head -n1)" \
  --arg kbld "$(kbld version 2>/dev/null | grep -Eo '[0-9.]+' | head -n1)" \
  --arg imgpkg "$(imgpkg version 2>/dev/null | grep -Eo '[0-9.]+' | head -n1)" \
  --arg vendir "$(vendir version 2>/dev/null | grep -Eo '[0-9.]+' | head -n1)" \
  --arg k9s "$(k9s version -s 2>/dev/null | grep -Eo '[0-9.]+' | head -n1)" \
  --arg tanzu "$(tanzu version | grep ^version | grep -Eo '[0-9.]+' | head -n1)" \
  --arg velero "$(velero version 2>/dev/null | grep -Eo 'v[0-9.]+' | head -n1)" \
  --arg yq "$(yq --version 2>/dev/null | grep -Eo '[0-9.]+$')" \
  --arg kubectx "$(kubectx -V 2>/dev/null | awk '{print $2}')" \
  --arg eza "$(eza --version 2>/dev/null | grep -Eo '[0-9.]+' | head -n1)" \
  --arg fzf "$(fzf --version 2>/dev/null | grep -Eo '[0-9.]+' | head -n1)" \
  --arg direnv "$(direnv version 2>/dev/null)" \
  '{kubectl: $kubectl, helm: $helm, ytt: $ytt, kapp: $kapp, kctrl: $kctrl, kbld: $kbld, imgpkg: $imgpkg, vendir: $vendir, k9s: $k9s, tanzu: $tanzu, velero: $velero, yq: $yq, kubectx: $kubectx, eza: $eza, fzf: $fzf, direnv: $direnv}' \
  > /versions.json

RUN strip --strip-unneeded /usr/local/bin/*

# ================================
# Final Image
# ================================
FROM debian:bookworm-slim
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

ARG IMAGE_VERSION
ARG TARGET_ARCH

LABEL org.opencontainers.image.title="k8s-cli-toolkit" \
      org.opencontainers.image.description="Multi-arch container with Kubernetes CLI tools" \
      org.opencontainers.image.source="https://github.com/dewab-org/docker-k8s-tools" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.authors="dwhicker@bifrost.cc"

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends zsh git jq vim curl ca-certificates zsh-common zsh-autosuggestions locales zsh-syntax-highlighting && \
    rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8

# RUN groupadd -r k8s && useradd -m -d /k8s -s /bin/zsh -g k8s k8suser && chown -R k8suser:k8s /k8s

COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/share/zsh /usr/local/share/zsh
COPY --from=builder /usr/local/share/powerlevel10k /usr/local/share/powerlevel10k
COPY --from=builder /usr/local/share/fzf-tab /usr/local/share/fzf-tab
COPY --from=builder /versions.json /versions.json

COPY files/zshrc \
    files/banner.txt \
    files/entrypoint.sh \
    files/kubectl-vsphere \
    files/tkgs-login \
    files/tmc-get-kubeconfigs \
    files/p10k.zsh \
    /tmp/

RUN cat /tmp/zshrc >> /etc/zsh/zshrc && \
    mv /tmp/banner.txt /banner.txt && \
    mv /tmp/entrypoint.sh /entrypoint.sh && \
    mv /tmp/tkgs-login /usr/local/bin/tkgs-login && chmod +x /usr/local/bin/tkgs-login && \
    mv /tmp/tmc-get-kubeconfigs /usr/local/bin/tmc-get-kubeconfigs && chmod +x /usr/local/bin/tmc-get-kubeconfigs && \
    mv /tmp/p10k.zsh /usr/local/share/powerlevel10k/p10k.zsh && \
    chmod +x /entrypoint.sh && \
    # mkdir -p /work && chown k8suser:k8s /work && \
    mkdir -p /k8s /work && \
    if [ "$TARGET_ARCH" = "amd64" ]; then \
        mv /tmp/kubectl-vsphere /usr/local/bin/kubectl-vsphere && chmod +x /usr/local/bin/kubectl-vsphere; \
    else \
        rm -f /tmp/kubectl-vsphere; \
    fi 
    # && \
    # chown -R k8suser:k8s /k8s

ENV PATH="/usr/local/bin:$PATH"
ENV HOME=/k8s
WORKDIR /work

# RUN chown -R k8suser:k8s /usr/local/share/ca-certificates /etc/ssl/certs

EXPOSE 80

# USER k8suser

CMD ["/entrypoint.sh"]

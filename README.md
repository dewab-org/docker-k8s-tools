# 🧰 Kubernetes CLI Toolkit

[![CI](https://github.com/dewab-org/docker-k8s-tools/actions/workflows/ci.yml/badge.svg)](https://github.com/dewab-org/docker-k8s-tools/actions/workflows/ci.yml)
[![Docker](https://github.com/dewab-org/docker-k8s-tools/actions/workflows/docker.yml/badge.svg)](https://github.com/dewab-org/docker-k8s-tools/actions/workflows/docker.yml)

---

## 📝 Description

This container provides an opinionated, comprehensive CLI environment for deploying, administering, and maintaining VMware Tanzu–based environments, including TKGS and Tanzu Mission Control.

It is designed to simplify tool setup for administrators—especially those working on Windows systems—by providing a ready-to-use interactive ZSH shell with command-line completion enabled for all included tools.

---

## 🧩 Variants

One Dockerfile builds five images. Pick the smallest one that covers your platform:

| Variant | Tag | Adds to `standard` |
|---------|-----|--------------------|
| `standard` | `:standard` | — |
| `tanzu` | `:tanzu` | VMware Tanzu, vSphere Supervisor, Carvel, Cluster API, Velero |
| `azure` | `:azure` | Azure CLI, Azure Developer CLI, kubelogin |
| `openshift` | `:openshift` | OpenShift CLI, odo, Tekton CLI |
| `all` | `:latest` | everything above |

`:latest` stays the full image, so existing `docker run ...:latest` commands keep working.

---

## 📦 Included Tools

**standard** (in every variant)

| Tool | Description |
|------|-------------|
| `kubectl` | Kubernetes CLI |
| `helm` / `helmfile` | Package manager / declarative Helm releases |
| `kustomize` | Standalone kustomize (newer than the copy built into kubectl) |
| `k9s` | Terminal UI for clusters |
| `stern` | Tail logs across many pods |
| `kubeconform` | Offline manifest validation |
| `kubectl krew` | kubectl plugin manager (plugins persist in `/k8s/.krew`) |
| `kubectx` / `kubens` | Switch contexts and namespaces |
| `kubecolor` | Colorized kubectl output |
| `yq` / `jq` | YAML and JSON processors |
| `fzf`, `eza`, `zoxide`, `direnv`, `starship` | Shell: fuzzy finder, `ls`, smarter `cd`, per-directory env, prompt |

**tanzu**: `tanzu`, `kubectl-vsphere`, `tkgs-login`, `tmc-get-kubeconfigs`, `velero`, `clusterctl`, and the Carvel tools `ytt`, `kapp`, `kctrl`, `kbld`, `imgpkg`, `vendir`.

> **Note:** `kubectl-vsphere` is included only on `amd64`. There is currently no official Linux `arm64` build available.

**azure**: `az` (installed from PyPI, since Microsoft's apt repo has no Debian 13 suite), `azd`, `kubelogin`.

**openshift**: `oc` (Red Hat's stable channel), `odo`, `tkn`. Upstream `odo` has had no release since v3.16.1 (June 2024).

### Version manifest

Every image records exactly what it ships in `/etc/k8s-cli-toolkit/manifest.json`: variant, image version, platform, base OS, and each tool's version as read from the installed binary at build time. Inside the container, run `versions`. From outside:

```bash
docker run --rm --entrypoint cat ghcr.io/dewab-org/k8s-cli-toolkit:standard /etc/k8s-cli-toolkit/manifest.json
```

### Supply chain

Every downloaded binary is checked against the SHA-256 its upstream publishes, and the build fails on a mismatch or a missing checksum. For the few projects that publish no checksum file (eza, direnv, zoxide, clusterctl, azd), `generate-env.sh` uses the digest GitHub records for the release asset. Tool versions are resolved to the latest upstream release on every build.

---

## 📍 Where the image is published

Every build publishes the same image to both registries from a single build:

| Registry | Reference |
|----------|-----------|
| Harbor (homelab) | `harbor.lab.local/homelab/k8s-cli-toolkit` |
| GHCR | `ghcr.io/dewab-org/k8s-cli-toolkit` |

Tags are `latest` plus `sha-<commit>` on `main`, `pr-<N>` for pull requests,
and the semver tags for `v*` releases, all for the `all` variant. The other
variants use the same tags with a `-<variant>` suffix (`sha-<commit>-tanzu`,
`pr-<N>-azure`), and their `latest` is the bare variant name (`:standard`).

Builds run on the in-cluster `arc-runners` scale set through the estate's
shared pipeline (`dewab-org/homelab.actions-runner` `build-image.yml`); the
Harbor robot credential comes from Vault via the runner's ServiceAccount, so
no registry secret is stored in this repository.

The scheduled Monday rebuild runs with the BuildKit cache disabled on purpose.
The runtime stage runs `apt-get upgrade` and `generate-env.sh` re-resolves
every tool to its latest upstream release, so a cache hit would silently keep
serving stale layers.

---

## 🚀 Quick Start

```bash
docker run --rm -it \
  -v <homevolume>:/k8s \
  -v <cavolume>:/ca \
  -v <manifestdir>:/work \
  -v ${HOME}/.kube/config:/kubeconfig \
  -p 80:80 \
  ghcr.io/dewab-org/k8s-cli-toolkit:latest
```

example:

```bash
docker run --rm -it -v k8s-home:/k8s -v ${HOME}/ca:/ca -p 80:80 ghcr.io/dewab-org/k8s-cli-toolkit:latest
```

example for Windows:

```bash
docker run --rm -it -v k8s-home:/k8s -v C:\kuberenetes\ca:/ca -v C:\kubernetes:/work -p 80:80 ghcr.io/dewab-org/k8s-cli-toolkit:latest
```

---

## 📂 Volume Mounts

When running the container, you can mount the following volumes to persist configuration or provide input files:

- 🏠 `/k8s`
  Persistent home directory for shell history, Tanzu plugins, and other user configs.
  ✅ **Recommended** for saving your environment between runs.

- 🔒 `/ca` *(optional)*
  Mount a directory containing custom CA certificates (`.crt` or `.pem` files).
  These are copied into `/k8s/.ca` and added to the system trust store.
  💡 Only needed when custom CAs are introduced or updated.

- 📁 `/work` *(optional)*
  Mount your Kubernetes manifests or working directory.
  Best used as a bind mount for editing or applying manifests from your local system.

- 📄 `/kubeconfig` *(optional)*
  Mount a kubeconfig file to copy it into the container.
  Useful for one-time setup of cluster access from your local environment.

---

### 💡 Tip

If you already have a `.kube` directory with multiple contexts, you can mount it directly to:

```bash
-v ${HOME}/.kube:/k8s/.kube
```

---

## 🛡️ Using Pinniped OIDC Authentication with TMC Self-Managed

When using Pinniped OIDC to authenticate with TMC Self-Managed, the login process includes a callback URL that is used by the browser to send the authentication code back to the CLI.

By default, the callback URL is:

`http://127.0.0.1/callback`

This means the CLI expects to be listening on **port 80**.

---

### If You Can Use Port 80

If your environment allows it, publish port 80 directly from your container:

`docker run -p 80:80 your-container`

This allows the default callback URL to work without any changes.

---

### If You Cannot Use Port 80

If you can't bind to port 80 (for example, because you're not running as root), you can redirect a different port to port 80 inside the container:

`docker run -p 8080:80 your-container`

In this case, the default callback URL will still be:

`http://127.0.0.1/callback`

But since the container is actually listening on port 8080, you will need to:

> Manually change the browser URL from
> `http://127.0.0.1/callback`
> to
> `http://127.0.0.1:8080/callback`
> before pressing enter.

This ensures the browser sends the response to the correct port.

---

### Summary

- Use `-p 80:80` if you can — no changes needed
- Use `-p <port>:80` if you must — and manually update the callback port in your browser

---

## 🛠️ Features & Behavior

- The shell follows [dewab-org/profile](https://github.com/dewab-org/profile): a Starship prompt, Catppuccin Mocha colors (k9s, kubecolor, fzf, eza, jq), fzf and fzf-tab completion menus, and zoxide (`cd` jumps to frequently used directories; `zf` picks one with fzf). Your terminal needs a Nerd Font for the prompt icons.
- The Kubernetes context (and, in the Tanzu variants, the Tanzu context) shows at the right of the prompt only while you are typing a Kubernetes command.
- Default Starship, kubecolor and k9s configs ship in the image. To customize, put your own file at the same path under `/k8s/.config` (e.g. `/k8s/.config/starship.toml`). k9s's config is copied into `/k8s/.config/k9s` on first start, and that copy is never overwritten.
- In the Tanzu variants, the Tanzu CLI is initialized and its essential plugins are installed on first startup with an empty home directory (requires internet access; may take a few minutes).
- Every included tool has tab completion, generated at build time.

---

## 🦭 Podman

If you're using Podman, there may be some specific changes needed to allow for pinniped OIDC authentication to work correctly, or for access to resources on the other side of a VPN.  Podman, by default, runs in rootless mode, which can cause issues with port binding and network access.  To work around this you will need to run Podman in rootful mode.  To resolve the VPN connection issues, you will also need to enable user-mode networking.

```bash
podman machine stop
podman machine set --rootful=true --user-mode-networking=true
podman machine start
```

The command to run the container in podman on Windows might look like this:

```bash
podman run --rm -it -v k8s-home:/k8s -v c:\Kubernetes\ca:/ca -v c:\kubernetes:/work -p 80:80 ghcr.io/dewab-org/k8s-cli-toolkit:latest
```

---

## 📝 Notes

- If you mount a `/ca` volume, all `.crt` and `.pem` files are persisted in `/k8s/.ca` and added to the trusted certificate store. This only needs to be done when CAs are updated.
- `./build.sh` builds the `all` variant locally. Set `VARIANT=standard` (or `tanzu`, `azure`, `openshift`) for another, and `PLATFORMS=linux/amd64,linux/arm64` for a multi-arch build.
- For best experience, use a persistent `/k8s` volume to retain history, plugins, and configuration between runs.

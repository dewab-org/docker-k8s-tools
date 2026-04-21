# 🧰 Kubernetes CLI Toolkit

[![Build and Push to GHCR](https://github.com/dewab-org/docker-k8s-tools/actions/workflows/build.yaml/badge.svg)](https://github.com/dewab-org/docker-k8s-tools/actions/workflows/build.yaml)

---

## 📝 Description

This container provides an opinionated, comprehensive CLI environment for deploying, administering, and maintaining VMware Tanzu–based environments, including TKGS and Tanzu Mission Control.

It is designed to simplify tool setup for administrators—especially those working on Windows systems—by providing a ready-to-use interactive ZSH shell with command-line completion enabled for all included tools.

---

## 📦 Included Tools

| Tool        | Description                              |
|-------------|------------------------------------------|
| `kubectl`   | Kubernetes CLI                           |
| `helm`      | Kubernetes package manager               |
| `k9s`       | Terminal UI for managing K8s clusters    |
| `kubectx`   | Switch between kube contexts             |
| `kubecolor` | Colorizes kubectl output                 |
| `yq`        | YAML processor                           |
| `ytt`       | YAML templating tool (Carvel)            |
| `kapp`      | App deployment tool (Carvel)             |
| `kctrl`     | App CR control CLI (Carvel)              |
| `kbld`      | Build and image reference tool (Carvel)  |
| `imgpkg`    | OCI image packaging tool (Carvel)        |
| `vendir`    | Vendor directory manager (Carvel)        |
| `tanzu`     | VMware Tanzu CLI                         |
| `velero`    | Backup and restore CLI                   |
| `eza`       | Modern replacement for `ls`             |

> **Note:** The `kubectl-vsphere` plugin is included only on the `amd64` platform. There is currently no official Linux `arm64` build available.

---

## 🚀 Quick Start

```bash
docker run --rm -it \
  -v <homevolume>:/k8s \
  -v <cavolume>:/ca \
  -v <manifestdir>:/work \
  -v ${HOME}/.kube/config:/kubeconfig \
  -p 80:80 \
  ghcr.io/dewab-org/docker-k8s-tools:latest
```

example:

```bash
docker run --rm -it -v k8s-home:/k8s -v ${HOME}/ca:/ca -p 80:80 ghcr.io/dewab-org/docker-k8s-tools:latest
```

example for Windows:

```bash
docker run --rm -it -v k8s-home:/k8s -v C:\kuberenetes\ca:/ca -v C:\kubernetes:/work -p 80:80 ghcr.io/dewab-org/docker-k8s-tools:latest
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

- On first startup with an empty home directory, Tanzu CLI is initialized and essential plugins are installed (requires internet access; may take a few minutes).
- The status bar with kube contexts appears once a kubeconfig exists.
- Velero version is shown only if a kubeconfig is present.
- All included tools have tab completion enabled.

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
podman run --rm -it -v k8s-home:/k8s -v c:\Kubernetes\ca:/ca -v c:\kubernetes:/work -p 80:80 ghcr.io/dewab-org/docker-k8s-tools:latest
```

---

## 📝 Notes

- If you mount a `/ca` volume, all `.crt` and `.pem` files are persisted in `/k8s/.ca` and added to the trusted certificate store. This only needs to be done when CAs are updated.
- For multi-arch builds, use Docker Buildx or the provided build scripts.
- For best experience, use a persistent `/k8s` volume to retain history, plugins, and configuration between runs.

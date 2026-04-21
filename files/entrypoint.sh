#!/bin/sh

set -eu

# Copy new CA certs from /ca to /k8s/.ca
if [ -d /ca ]; then
  mkdir -p /k8s/.ca
  echo "📦 Scanning /ca for CA certificates..."
  for cert in /ca/*.crt /ca/*.pem; do
    if [ -f "$cert" ]; then
      dest_name="/k8s/.ca/$(basename "${cert%.*}").crt"
      echo "🔐 Copying $cert to $dest_name"
      cp "$cert" "$dest_name"
    fi
  done
fi

# Trust additional CA certs
set -- /k8s/.ca/*.crt
if [ -e "$1" ]; then
  echo "🔐 Updating CA certificates from /k8s/.ca"
  cp /k8s/.ca/*.crt /usr/local/share/ca-certificates/
  output=$(update-ca-certificates 2>&1)
  summary=$(echo "$output" | grep -Eo '[0-9]+ added, [0-9]+ removed; done.')
  if [ -n "$summary" ]; then
    if ! echo "$summary" | grep -q '^0 added, 0 removed'; then
      echo "🔐 $summary"
    fi
  fi
else
  echo "⚠️ No CA certificates found in /k8s/.ca"
fi

# Copy /kubeconfig to /k8s/.kube/config if it exists
if [ -f /kubeconfig ]; then
  echo "📄 Copying /kubeconfig to /k8s/.kube/config"
  mkdir -p /k8s/.kube
  cp /kubeconfig /k8s/.kube/config
fi

# Copy /tanzu to /k8s/.config/tanzu/ if it exists
if [ -d /tanzu ]; then
  echo "📁 Copying /tanzu to /k8s/.config/tanzu/"
  mkdir -p /k8s/.config/tanzu
  cp -r /tanzu/* /k8s/.config/tanzu/
fi

# echo "🔑 Fixing ownership of /k8s"
# chown -R k8suser:k8s /k8s 2>/dev/null || true

# Touch /k8s/.zshrc to ensure it exists
touch /k8s/.zshrc

# Drop to k8suser for the shell
# exec su - k8suser -c zsh
# su - k8suser -c zsh

zsh

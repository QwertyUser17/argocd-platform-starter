#!/bin/sh
# Installs Argo CD into the management cluster and applies the root app.
# usage: bootstrap/install.sh <kube-context>
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <kube-context>" >&2
  exit 2
fi

context=$1
dir=$(cd "$(dirname "$0")" && pwd)

helm upgrade --install argocd argo-cd \
  --kube-context "$context" \
  --repo https://argoproj.github.io/argo-helm \
  --version 10.10.3 \
  --namespace argocd --create-namespace \
  --values "$dir/argocd-values.yaml" \
  --wait

kubectl --context "$context" apply -f "$dir/root-app.yaml"

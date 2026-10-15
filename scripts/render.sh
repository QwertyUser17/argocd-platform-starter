#!/bin/sh
# Renders everything Argo CD would apply into <out-dir>, one file per Application:
# the bootstrap objects, every environments/<env>/<app> overlay and every platform
# component for every env with the same value files the ApplicationSets use.
# usage: scripts/render.sh <out-dir>
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <out-dir>" >&2
  exit 2
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$1"
out=$(cd "$1" && pwd)
charts=$(mktemp -d)
trap 'rm -rf "$charts"' EXIT

kube_version=1.37.0
envs="dev stage prod"

# component.yaml has a fixed layout: two-space indented keys under "component:".
field() {
  sed -n "s/^  $2: *//p" "$1"
}

cat "$repo/bootstrap/root-app.yaml" > "$out/bootstrap.yaml"
kubectl kustomize "$repo/bootstrap/root" > "$out/root.yaml"

# Charts are pulled into a temp dir: helm template <name> --repo prefers ./<name> when it exists.
helm pull argo-cd --repo https://argoproj.github.io/argo-helm \
  --version "$(sed -n 's/^ *--version \([^ ]*\) .*/\1/p' "$repo/bootstrap/install.sh")" \
  --untar --untardir "$charts/argo-cd"
helm template argocd "$charts/argo-cd/argo-cd" \
  --namespace argocd --kube-version "$kube_version" \
  --values "$repo/bootstrap/argocd-values.yaml" > "$out/argo-cd.yaml"

for overlay in "$repo"/environments/*/*/; do
  env=$(basename "$(dirname "$overlay")")
  app=$(basename "$overlay")
  kubectl kustomize "$overlay" > "$out/app-$app-$env.yaml"
done

for component in "$repo"/platform/*/*/component.yaml; do
  dir=$(dirname "$component")
  name=$(field "$component" name)
  helm pull "$(field "$component" chart)" --repo "$(field "$component" repoURL)" \
    --version "$(field "$component" version)" --untar --untardir "$charts/$name"
  for env in $envs; do
    set --
    for file in values.yaml alerts.yaml dashboards.yaml "values-$env.yaml"; do
      case "$dir/$file" in
        */platform/controllers/*/alerts.yaml | */platform/controllers/*/dashboards.yaml) continue ;;
      esac
      if [ -f "$dir/$file" ]; then
        set -- "$@" --values "$dir/$file"
      fi
    done
    # --include-crds: Argo CD applies crds/ directories too (skipCrds is false by default).
    # --api-versions: the Prometheus Operator CRDs come from wave 0, so on a real cluster this API exists.
    helm template "$name" "$charts/$name/$(field "$component" chart)" \
      --namespace "$(field "$component" namespace)" \
      --kube-version "$kube_version" \
      --include-crds \
      --api-versions monitoring.coreos.com/v1 \
      "$@" > "$out/$name-$env.yaml"
  done
done

ls "$out"

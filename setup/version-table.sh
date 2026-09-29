#!/usr/bin/env bash
# Versions are asserted by the flake's checks.<system>.versions; this only reports them.
set -euo pipefail
printf '### Deploy toolchain\n\n```text\n'
nix --version
for tool in gcloud gke-gcloud-auth-plugin helm kubectl skaffold cue gh sops jq; do
  printf '\n%s: %s\n' "$tool" "$(command -v "$tool")"
  case "$tool" in
    helm) helm version --short; helm plugin list ;;
    kubectl) kubectl version --client ;;
    skaffold|cue) "$tool" version ;;
    sops) sops --disable-version-check --version ;;
    *) "$tool" --version ;;
  esac
done
printf '\nRunner dependencies:\n'
docker --version
docker buildx version
printf '```\n'

#!/usr/bin/env bash
# Called with a five-minute timeout by setup/action.yaml.
set -euo pipefail

src="$(cd "${1:?Expected toolchain source directory}" && pwd)"
: "${RUNNER_TEMP:?}" "${GITHUB_PATH:?}" "${GITHUB_ENV:?}" "${GITHUB_STEP_SUMMARY:?}"
fail() { echo "::error::$*" >&2; exit 1; }
case "${RUNNER_OS:-}/${RUNNER_ARCH:-}" in
  Linux/X64) system=x86_64-linux ;;
  Linux/ARM64) system=aarch64-linux ;;
  *) fail 'Supported runners: Linux X64 and ARM64' ;;
esac
for file in nix/flake.nix nix/flake.lock nix/store-paths.json; do
  [[ -f "$src/$file" ]] || fail "Missing required file: $file"
done
python3 -m json.tool "$src/nix/flake.lock" >/dev/null 2>&1 || fail 'Invalid JSON: nix/flake.lock'
pinned="$(python3 -c '
import json, sys
p = json.load(open(sys.argv[1]))[sys.argv[2]]
print(p["tools"], p["check"])
' "$src/nix/store-paths.json" "$system" 2>/dev/null)" || fail 'Invalid nix/store-paths.json'
read -r tools check <<< "$pinned"
[[ "$tools" == /nix/store/* && "$check" == /nix/store/* ]] || fail 'Invalid nix/store-paths.json'

phase=bootstrap
trap 'echo "::error::Toolchain setup failed during $phase; no environment was exported." >&2' ERR
[[ "$(nix --version)" == 'nix (Nix) 2.35.2' ]] || fail 'Expected upstream Nix 2.35.2; use a fresh supported runner'

phase=installation
# CI publishes these paths after building them from the flake, so fetching them
# skips the nixpkgs download and evaluation. The check path only exists if its
# version checks passed.
if ! nix build --no-link "$tools" "$check"; then
  echo '::warning::Pinned toolchain is not cached; building it from the flake' >&2
  # path: copies only the flake directory, so the action checkout need not be a
  # Git repository and is never written to. A lock that needs changes is an error.
  flake="path:$src/nix"
  tools="$(nix build --no-link --print-out-paths --no-update-lock-file "$flake#default")"
  phase="version-verification"
  nix build --no-link --no-update-lock-file "$flake#checks.$system.versions"
fi
phase="tool-verification"

# Helm runs without plugins; nothing is inherited from a container or the host.
unset HELM_PLUGINS CLOUDSDK_PYTHON
for tool in gcloud gke-gcloud-auth-plugin helm kubectl skaffold cue gh jq; do
  [[ -x "$tools/bin/$tool" ]] || fail "Missing tool: $tool"
done
versions="$(PATH="$tools/bin:$PATH" bash "$src/setup/version-table.sh")"

# Runtime credentials live outside the flake source and Nix store.
auth="$(mktemp -d "$RUNNER_TEMP/mlr-auth.XXXXXXXX")"
chmod 700 "$auth"
mkdir "$auth/gcloud" "$auth/docker"
printf 'mlr-toolchain\n' > "$auth/.owner"

# Publish only after installation, version checks and tools have all passed.
printf '%s\n' "$tools/bin" >> "$GITHUB_PATH"
{
  echo 'GOOGLE_APPLICATION_CREDENTIALS=/tmp/key.json'
  echo 'USE_GKE_GCLOUD_AUTH_PLUGIN=True'
  echo "MLR_TOOLCHAIN_AUTH_DIR=$auth"
  echo "CLOUDSDK_CONFIG=$auth/gcloud"
  echo "DOCKER_CONFIG=$auth/docker"
  echo "KUBECONFIG=$auth/kubeconfig"
  echo "HELM_REGISTRY_CONFIG=$auth/helm-registry.json"
  echo 'HELM_PLUGINS='
  echo 'CLOUDSDK_PYTHON='
} >> "$GITHUB_ENV"
{
  printf 'Action configuration SHA256:\n'
  sha256sum "$src/nix/flake.nix" "$src/nix/flake.lock"
  printf '%s\n' "$versions"
} | tee -a "$GITHUB_STEP_SUMMARY"

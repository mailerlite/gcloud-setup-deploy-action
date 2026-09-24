#!/usr/bin/env bash
# Called with a five-minute timeout by setup/action.yaml.
set -euo pipefail

src="$(cd "${1:?Expected toolchain source directory}" && pwd)"
: "${RUNNER_TEMP:?}" "${GITHUB_PATH:?}" "${GITHUB_ENV:?}" "${GITHUB_STEP_SUMMARY:?}"
fail() { echo "::error::$*" >&2; exit 1; }
case "${RUNNER_OS:-}/${RUNNER_ARCH:-}" in
  Linux/X64|Linux/ARM64) ;;
  *) fail 'Supported runners: Linux X64 and ARM64' ;;
esac
for file in devbox.json devbox.lock nix/flake.nix nix/flake.lock nix/gcloud-components.json; do
  [[ -f "$src/$file" ]] || fail "Missing required file: $file"
done

for file in devbox.json devbox.lock nix/flake.lock nix/gcloud-components.json; do
  python3 -m json.tool "$src/$file" >/dev/null 2>&1 || fail "Invalid JSON: $file"
done

# Each invocation gets an isolated directory. A failed attempt cannot be reused.
work="$(mktemp -d "$RUNNER_TEMP/mlr-toolchain.XXXXXXXX")"
phase=bootstrap
trap 'echo "::error::Toolchain setup failed during $phase; no environment was exported. See $work" >&2' ERR
mkdir "$work/nix"
cp "$src/devbox.json" "$src/devbox.lock" "$work/"
cp "$src/nix/flake.nix" "$src/nix/flake.lock" "$src/nix/gcloud-components.json" "$work/nix/"

export DEVBOX_NO_TELEMETRY=1
export DEVBOX_NO_PROMPT=1
# Nix authenticates through the installer-configured job token. Prevent Devbox
# from discovering a separate token through the environment or GitHub CLI.
unset GH_TOKEN GITHUB_TOKEN
export GH_CONFIG_DIR="$work/gh"
mkdir "$GH_CONFIG_DIR"

# A full revision avoids dependence on channels or the Nix registry.
bootstrap="$(nix build --no-link --print-out-paths \
  github:NixOS/nixpkgs/00455b0a3690d3f5dc61e9aef4277dc86235b73f#devbox)"
export PATH="$bootstrap/bin:$PATH"
printf '%s\n' "$bootstrap/bin" > "$work/paths"
[[ "$(nix --version)" == 'nix (Nix) 2.35.2' ]] || fail 'Expected upstream Nix 2.35.2; use a fresh supported runner'
[[ "$(devbox version)" == '0.17.5' ]] || fail 'Expected Devbox 0.17.5'
phase=installation
cd "$work"
devbox install
phase=environment

# Capture first so an unsuccessful shellenv cannot be hidden by eval.
shellenv="$(devbox shellenv)"
eval "$shellenv"
phase="lock-verification"
cmp "$src/devbox.lock" "$work/devbox.lock" || fail 'devbox.lock changed during setup; regenerate and review it before release'
cmp "$src/nix/flake.lock" "$work/nix/flake.lock" || fail 'nix/flake.lock changed during setup; regenerate and review it before release'
phase="tool-verification"

# Plugins are packaged by the Helm wrapper, not inherited from a container.
unset HELM_PLUGINS CLOUDSDK_PYTHON

# Resolve tools from the environment Devbox publishes, never its private profile layout.
for tool in gcloud gke-gcloud-auth-plugin helm kubectl skaffold cue gh sops jq; do
  executable="$(command -v "$tool")" || fail "Missing tool: $tool"
  case "$(readlink -f "$executable")" in
    /nix/store/*) ;;
    *) fail "$tool resolved outside the Nix store: $executable" ;;
  esac
  printf '%s\n' "$(dirname "$executable")" >> "$work/paths"
done
bash "$src/setup/version-table.sh" "$src/devbox.json" > "$work/versions"

# Runtime credentials live outside the flake source and Nix store.
auth="$(mktemp -d "$RUNNER_TEMP/mlr-auth.XXXXXXXX")"
chmod 700 "$auth"
mkdir "$auth/gcloud" "$auth/docker"
printf 'mlr-toolchain\n' > "$auth/.owner"

# Publish only after installation, locks and tools have all passed validation.
sort -u "$work/paths" >> "$GITHUB_PATH"
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
  sha256sum "$src/devbox.json" "$src/devbox.lock" "$src/nix/flake.nix" "$src/nix/flake.lock"
  cat "$work/versions"
} | tee -a "$GITHUB_STEP_SUMMARY"

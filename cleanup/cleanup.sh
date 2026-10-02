#!/usr/bin/env bash
set -euo pipefail

# The Attic netrc is written before Nix installs, so remove it even after a failed setup.
netrc="${RUNNER_TEMP:-}/mlr-nix-netrc"
if [[ -n "${RUNNER_TEMP:-}" && -f "$netrc" && -O "$netrc" && ! -L "$netrc" ]]; then
  rm -f -- "$netrc"
fi

# Setup may have failed before creating authentication state.
[[ -n "${MLR_TOOLCHAIN_AUTH_DIR:-}" ]] || exit 0
[[ -e "$MLR_TOOLCHAIN_AUTH_DIR" ]] || exit 0
root="$(realpath "${RUNNER_TEMP:?}")"
auth="$(realpath "$MLR_TOOLCHAIN_AUTH_DIR")"
[[ "$root" != / && "$auth" == "$root"/mlr-auth.* && -d "$auth" && -O "$auth" && ! -L "$MLR_TOOLCHAIN_AUTH_DIR" ]] || {
  echo '::error::Refusing cleanup outside the owned toolchain auth directory' >&2
  exit 1
}
[[ "$(cat "$auth/.owner")" == mlr-toolchain ]] || exit 1
rm -rf -- "$auth"

# The deploy action keeps the existing image contract for this credential file.
if [[ -f /tmp/key.json && -O /tmp/key.json && ! -L /tmp/key.json ]]; then
  rm -f -- /tmp/key.json
fi

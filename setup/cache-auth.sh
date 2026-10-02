#!/usr/bin/env bash
# Writes the Nix netrc for the Attic toolchain cache before Nix is installed.
set -euo pipefail

: "${RUNNER_TEMP:?}"
fail() { echo "::error::$*" >&2; exit 1; }
host=attic.litehub.io
cache=deploy-toolchain
netrc="$RUNNER_TEMP/mlr-nix-netrc"
token="${ATTIC_TOKEN:-}"

[[ -n "$token" ]] || fail 'attic-token is empty; pass secrets.ATTIC_PULL_TOKEN (fork PRs receive no secrets)'
# Attic tokens are JWTs; anything else could inject extra netrc entries.
[[ "$token" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'attic-token contains unexpected characters'

(umask 077 && printf 'machine %s\npassword %s\n' "$host" "$token" > "$netrc")

# A rejected token is a configuration error; an unreachable cache only makes Nix
# build the toolchain from upstream sources.
status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --netrc-file "$netrc" \
  "https://$host/$cache/nix-cache-info" 2>/dev/null)" || status=000
case "$status" in
  200) echo "Attic cache $cache is reachable" ;;
  401|403|404) rm -f -- "$netrc"; fail "Attic rejected the token for $cache (HTTP $status); check ATTIC_PULL_TOKEN" ;;
  *) echo "::warning::Attic cache $cache is unavailable (HTTP $status); Nix will build missing paths" ;;
esac

#!/usr/bin/env bash
# Regenerates nix/store-paths.json: the toolchain and version-check paths setup
# fetches without evaluating the flake. Evaluation only, so it runs on any host.
# --check fails instead of writing when the committed file is stale.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
flake="path:$root/nix"
out="$root/nix/store-paths.json"

tools="$(nix eval --json --no-update-lock-file "$flake#packages" \
  --apply 'builtins.mapAttrs (_: p: p.default.outPath)')"
checks="$(nix eval --json --no-update-lock-file "$flake#checks" \
  --apply 'builtins.mapAttrs (_: c: c.versions.outPath)')"
json="$(python3 -c '
import json, sys
tools, checks = json.loads(sys.argv[1]), json.loads(sys.argv[2])
print(json.dumps({s: {"tools": tools[s], "check": checks[s]} for s in sorted(tools)}, indent=2))
' "$tools" "$checks")"

if [[ "${1:-}" == --check ]]; then
  diff -u "$out" <(printf '%s\n' "$json") || {
    echo '::error::nix/store-paths.json is stale; run scripts/update-store-paths.sh and commit it' >&2
    exit 1
  }
else
  printf '%s\n' "$json" > "$out"
fi

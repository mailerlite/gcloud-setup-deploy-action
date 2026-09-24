#!/usr/bin/env bash
set -euo pipefail
printf '### Deploy toolchain\n\n```text\n'
nix --version
devbox version
for tool in gcloud gke-gcloud-auth-plugin helm kubectl skaffold cue gh sops jq; do
  printf '\n%s: %s\n' "$tool" "$(command -v "$tool")"
  case "$tool" in
    helm) helm version --short; helm plugin list ;;
    kubectl) kubectl version --client ;;
    skaffold|cue) "$tool" version ;;
    *) "$tool" --version ;;
  esac
done
printf '\nRunner dependencies:\n'
docker --version
docker buildx version
printf '```\n'
# Compare ordinary CLI versions with their manifest pins, not a second version list.
python3 - "${1:?Expected devbox.json}" <<'PYTHON'
import json
import re
import subprocess
import sys
for package in json.load(open(sys.argv[1]))['packages']:
    if package.startswith('path:'):
        continue
    tool, expected = package.rsplit('@', 1)
    args = ['version'] if tool in ('skaffold', 'cue') else ['--version']
    result = subprocess.check_output([tool, *args], text=True)
    if not re.search(r'(?<![0-9.])' + re.escape(expected) + r'(?![0-9.])', result):
        raise SystemExit(f'{tool}: expected {expected}, got {result.strip()}')
PYTHON

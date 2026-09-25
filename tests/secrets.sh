#!/usr/bin/env bash
set -euo pipefail
fixture="$(mktemp -d "$RUNNER_TEMP/mlr-secrets-test.XXXXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT
age-keygen -o "$fixture/key" 2> "$fixture/public"
export SOPS_AGE_KEY_FILE="$fixture/key"
recipient="$(age-keygen -y "$fixture/key")"
printf 'test_value: toolchain-fixture\n' > "$fixture/plain.yaml"
sops --encrypt --age "$recipient" "$fixture/plain.yaml" > "$fixture/encrypted.yaml"
helm secrets decrypt "$fixture/encrypted.yaml" > "$fixture/decrypted.yaml"
cmp "$fixture/plain.yaml" "$fixture/decrypted.yaml"

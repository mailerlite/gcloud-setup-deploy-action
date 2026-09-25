#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACT_REGISTRY:?Expected registry hostname}"
[[ "$ARTIFACT_REGISTRY" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*(:[0-9]+)?$ ]] || {
  echo '::error::artifact_registry must be a hostname, without a URL scheme or path' >&2
  exit 1
}

gcloud auth configure-docker "$ARTIFACT_REGISTRY" --quiet
gcloud auth application-default print-access-token |
  helm registry login --username oauth2accesstoken --password-stdin "$ARTIFACT_REGISTRY"

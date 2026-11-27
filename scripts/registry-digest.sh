#!/usr/bin/env bash
# Prints the current digest of a Docker Hub image tag, e.g. `registry-digest.sh php:8.4.28-apache`.
# Uses an anonymous HEAD request, which Docker Hub does not count as a pull.
# Exit codes: 0 = digest printed, 2 = tag does not exist, 1 = any other error (network, rate limit, ...).
set -euo pipefail

ref="${1:?usage: registry-digest.sh <image>:<tag>}"
repo="${ref%:*}"
tag="${ref##*:}"
[[ "$repo" == */* ]] || repo="library/$repo"

token=$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" | jq -r .token)

headers=$(curl -sS -I -H "Authorization: Bearer $token" \
  -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
  "https://registry-1.docker.io/v2/${repo}/manifests/${tag}")

status=$(head -n1 <<< "$headers" | awk '{print $2}')
case "$status" in
  200) ;;
  404) exit 2 ;;
  *) echo "registry-digest: HTTP ${status:-none} for $ref" >&2; exit 1 ;;
esac

digest=$(tr -d '\r' <<< "$headers" | awk 'tolower($1) == "docker-content-digest:" {print $2}')
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "registry-digest: no digest for $ref" >&2; exit 1; }
echo "$digest"

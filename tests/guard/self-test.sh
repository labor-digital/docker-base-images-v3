#!/usr/bin/env bash
# Runs scripts/renovate-guard.sh against every fixture in this folder, without network access.
# pass-*.json must be accepted for the auto lane, review-*.json must be sent to a human review.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
export REGISTRY_FIXTURE="$here/registry.txt"
failures=0

for f in "$here"/*.json; do
  name=$(basename "$f" .json)
  if out=$("$here/../../scripts/renovate-guard.sh" "$f" 2>&1); then got=pass; else got=review; fi
  # A review verdict must be a deliberate decision, not a crash that happens to exit non-zero
  [ "$got" = pass ] || grep -q "^needs review: " <<< "$out" || got="crash"
  want=${name%%-*}
  if [ "$got" = "$want" ]; then
    echo "ok    $name: $(tail -n1 <<< "$out")"
  else
    echo "FAIL  $name: expected $want, got $got: $out"
    failures=$((failures + 1))
  fi
done

[ "$failures" -eq 0 ] || { echo "$failures guard self-test case(s) failed" >&2; exit 1; }

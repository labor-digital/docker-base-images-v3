#!/usr/bin/env bash
# Auto-lane check (.design-log/001 §4.1): may this PR merge without a human review?
#
#   renovate-guard.sh <files.json>
#
# <files.json> is the PR's file list from GET /repos/{repo}/pulls/{n}/files. The PR's code is never
# checked out or executed; only this diff text is read.
# Exit 0 only if the PR is a pure upstream patch or digest bump of existing lines in docker-bake.hcl,
# and every new digest is exactly what Docker Hub serves for that tag right now. Exit 1 otherwise,
# with the reasons on stderr.
#
# Self-test: REGISTRY_FIXTURE=<file with "image:tag digest" lines> replaces the Docker Hub lookup.
set -euo pipefail

files_json="${1:?usage: renovate-guard.sh <files.json>}"
here="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "needs review: $*" >&2; exit 1; }

lookup() {
  if [ -n "${REGISTRY_FIXTURE:-}" ]; then
    awk -v r="$1" '$1 == r {print $2; f=1} END {exit !f}' "$REGISTRY_FIXTURE"
  else
    "$here/registry-digest.sh" "$1"
  fi
}

# 1. Exactly one file, docker-bake.hcl, modified in place
[ "$(jq 'length' "$files_json")" -eq 1 ] || fail "the PR changes $(jq 'length' "$files_json") files, the auto lane allows only docker-bake.hcl"
[ "$(jq -r '.[0].filename' "$files_json")" = "docker-bake.hcl" ] || fail "the changed file is $(jq -r '.[0].filename' "$files_json"), not docker-bake.hcl"
[ "$(jq -r '.[0].status' "$files_json")" = "modified" ] || fail "docker-bake.hcl is $(jq -r '.[0].status' "$files_json"), not modified"
patch=$(jq -r '.[0].patch // empty' "$files_json")
[ -n "$patch" ] || fail "GitHub returned no diff for docker-bake.hcl"

# 2. Every changed line is a version row (same format Renovate's regex manager writes)
row='^[[:space:]]*\{ minor = "([0-9]+\.[0-9]+)", image = "(php|node)", tag = "([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-z0-9.-]+)", digest = "(sha256:[a-f0-9]{64})" \},[[:space:]]*$'
declare -A old_tag=() old_image=() old_digest=()
added=()
while IFS= read -r line; do
  case "$line" in
    @@*|" "*|"") continue ;;
    "\\ No newline at end of file") continue ;;
    -*|+*)
      body="${line:1}"
      [[ "$body" =~ $row ]] || fail "changed line is not a version row: $body"
      minor="${BASH_REMATCH[1]}"
      if [[ "$line" == -* ]]; then
        [ -z "${old_tag[$minor]:-}" ] || fail "line $minor removed twice"
        old_image[$minor]="${BASH_REMATCH[2]}"
        old_tag[$minor]="${BASH_REMATCH[3]}.${BASH_REMATCH[4]}.${BASH_REMATCH[5]}${BASH_REMATCH[6]}"
        old_digest[$minor]="${BASH_REMATCH[7]}"
      else
        added+=("$body")
      fi
      ;;
    *) fail "unexpected diff line: $line" ;;
  esac
done <<< "$patch"

[ "${#added[@]}" -gt 0 ] || fail "no version row was changed"
[ "${#added[@]}" -eq "${#old_tag[@]}" ] || fail "${#old_tag[@]} rows removed but ${#added[@]} added"

# 3. Each added row replaces the row of the same line: same image, same minor, same suffix, patch not lower,
#    and the new digest is what the registry serves for the new tag
seen=()
for body in "${added[@]}"; do
  [[ "$body" =~ $row ]]
  minor="${BASH_REMATCH[1]}" image="${BASH_REMATCH[2]}"
  major_minor="${BASH_REMATCH[3]}.${BASH_REMATCH[4]}" patch_no="${BASH_REMATCH[5]}" suffix="${BASH_REMATCH[6]}"
  tag="${major_minor}.${patch_no}${suffix}" digest="${BASH_REMATCH[7]}"

  [ -n "${old_tag[$minor]:-}" ] || fail "line $minor is new, new lines need a review"
  [[ " ${seen[*]:-} " != *" $minor "* ]] || fail "line $minor added twice"
  seen+=("$minor")
  [ "$image" = "${old_image[$minor]}" ] || fail "line $minor changes image ${old_image[$minor]} -> $image"
  [ "$major_minor" = "$minor" ] || fail "line $minor gets tag $tag from another minor"

  [[ "${old_tag[$minor]}" =~ ^[0-9]+\.[0-9]+\.([0-9]+)(-.+)$ ]]
  old_patch="${BASH_REMATCH[1]}" old_suffix="${BASH_REMATCH[2]}"
  [ "$suffix" = "$old_suffix" ] || fail "line $minor changes variant $old_suffix -> $suffix"
  [ "$patch_no" -ge "$old_patch" ] || fail "line $minor goes back from ${old_tag[$minor]} to $tag"
  [ "$tag:$digest" != "${old_tag[$minor]}:${old_digest[$minor]}" ] || fail "line $minor is unchanged"

  current=$(lookup "$image:$tag") || fail "could not look up $image:$tag on Docker Hub"
  [ "$current" = "$digest" ] || fail "$image:$tag is $current on Docker Hub, the PR pins $digest"
  echo "ok: $minor $image ${old_tag[$minor]} -> $tag ($digest)"
done

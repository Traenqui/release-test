#!/bin/bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
source scripts/lib/release.sh

readonly RELEASE_BRANCH="master"

fail() {
  echo "$1" >&2
  exit 1
}

# jg 30.09.26
ensure_tag_is_on_release_branch() {
  local tag="$1"
  if [[ ! "$tag" =~ $SEMVER_TAG_PATTERN ]]; then
    fail "Invalid release tag: $tag"
  fi
  if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "$tag^{commit}")" ]]; then
    fail "HEAD is not at $tag. Check out the tag first."
  fi
  git fetch --quiet origin "$RELEASE_BRANCH"
  if ! git merge-base --is-ancestor "$tag" "origin/$RELEASE_BRANCH"; then
    fail "Tag $tag is not on '$RELEASE_BRANCH'."
  fi
}

# jg 30.09.26
ensure_tag_matches_commits() {
  local tag="$1" version status=0
  version="$(./scripts/update_version.sh "$tag")" || status=$?
  if [[ $status -eq $EXIT_NO_RELEASE ]]; then
    fail "Tag $tag has no release-relevant commits."
  fi
  if [[ $status -ne 0 ]]; then exit "$status"; fi
  if [[ "$tag" != "v$version" ]]; then
    fail "Tag $tag does not match the commits. Expected v$version."
  fi
}

# jg 30.09.26
main() {
  local tag="${1:?Usage: $0 <vMAJOR.MINOR.PATCH>}"
  ensure_tag_is_on_release_branch "$tag"
  ensure_tag_matches_commits "$tag"
  ./scripts/generate_changelog.sh --dry-run "$tag"
}

main "$@"

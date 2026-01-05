#!/bin/bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
source scripts/lib/release.sh

readonly RELEASE_BRANCH="master"

fail() {
  echo "$1" >&2
  exit 1
}

ensure_release_branch_is_current() {
  if [[ "$(git branch --show-current)" != "$RELEASE_BRANCH" ]]; then
    fail "Releases are cut from '$RELEASE_BRANCH' only."
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    fail "Working tree is not clean."
  fi
  git fetch --quiet --tags origin "$RELEASE_BRANCH"
  if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$RELEASE_BRANCH")" ]]; then
    fail "Local '$RELEASE_BRANCH' differs from 'origin/$RELEASE_BRANCH'. Sync it first."
  fi
}

main() {
  ensure_release_branch_is_current

  local version status=0
  version="$(./scripts/update_version.sh)" || status=$?
  if [[ $status -eq $EXIT_NO_RELEASE ]]; then
    echo "Nothing to release."
    exit 0
  fi
  if [[ $status -ne 0 ]]; then exit "$status"; fi

  local tag="v$version"
  if git rev-parse --quiet --verify "refs/tags/$tag" > /dev/null; then
    fail "Tag $tag already exists."
  fi

  ./scripts/generate_changelog.sh "$tag"
  git add CHANGELOG.md
  git commit --quiet -m "chore(release): $tag"
  git tag -a "$tag" -m "Release $tag"
  git push --atomic origin "HEAD:$RELEASE_BRANCH" "$tag"
  echo "Released $tag."
}

main "$@"

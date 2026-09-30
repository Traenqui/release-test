#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/release.sh"

release_level() {
  local level=none hash subject kind
  while IFS="$FIELD_SEPARATOR" read -r hash subject kind; do
    case "$kind" in
      breaking)
        echo "[major] $subject" >&2
        level=major
        ;;
      feat)
        echo "[minor] $subject" >&2
        if [[ "$level" != major ]]; then level=minor; fi
        ;;
      fix)
        echo "[patch] $subject" >&2
        if [[ "$level" == none ]]; then level=patch; fi
        ;;
      *)
        echo "[none]  $subject" >&2
        ;;
    esac
  done
  echo "$level"
}

bump_version() {
  local tag="$1" level="$2"
  if [[ ! "$tag" =~ $SEMVER_TAG_PATTERN ]]; then
    echo "Invalid release tag: $tag" >&2
    return 1
  fi
  local major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
  case "$level" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
  esac
}

main() {
  local release_tag="${1:-}" tag level
  tag="$(latest_release_tag "$release_tag")"
  echo "Base tag: ${tag:-<none>}" >&2
  level="$(each_commit "${tag:+$tag..}HEAD" | release_level)"
  if [[ "$level" == none ]]; then
    echo "No release-relevant commits." >&2
    exit "$EXIT_NO_RELEASE"
  fi
  bump_version "${tag:-v0.0.0}" "$level"
}

main "$@"

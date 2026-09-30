#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/release.sh"

readonly CHANGELOG_FILE="CHANGELOG.md"
readonly RELEASE_BRANCH="master"

# jg 30.09.26
main() {
  cd "$(git rev-parse --show-toplevel)"
  if [[ "$(git branch --show-current)" != "$RELEASE_BRANCH" ]]; then
    echo "The changelog is committed on '$RELEASE_BRANCH' only." >&2
    exit 1
  fi

  ./scripts/generate_changelog.sh --init
  if [[ -z "$(git status --porcelain -- "$CHANGELOG_FILE")" ]]; then
    echo "$CHANGELOG_FILE is up to date."
    return
  fi

  git add "$CHANGELOG_FILE"
  git commit --quiet -m "$CHANGELOG_COMMIT_SUBJECT"
  git push --quiet origin "HEAD:$RELEASE_BRANCH"
  echo "$CHANGELOG_FILE committed to $RELEASE_BRANCH."
}

main "$@"

#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/release.sh"

main() {
  local title="${1:-}"
  if [[ "$title" =~ $CONVENTIONAL_SUBJECT_PATTERN ]] && [[ "$KNOWN_COMMIT_TYPES" == *" ${BASH_REMATCH[1]} "* ]]; then
    echo "PR title is valid: $title"
    return
  fi
  echo "::error title=PR title::'$title' is not a conventional commit. Expected '<type>(<scope>)!: <description>' with type one of:$KNOWN_COMMIT_TYPES"
  exit 1
}

main "$@"

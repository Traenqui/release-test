#!/bin/bash
set -euo pipefail

readonly SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/lib/release.sh"

preview_dir=""

remove_preview_worktree() {
  if [[ -z "$preview_dir" ]]; then return; fi
  git -C "$SCRIPTS_DIR" worktree remove --force "$preview_dir" > /dev/null 2>&1 || true
  rm -rf "$preview_dir"
}

main() {
  local base_ref="${1:?Usage: $0 <base-ref> <pr-title>}" title="${2:?Usage: $0 <base-ref> <pr-title>}"
  preview_dir="$(mktemp -d)"
  trap remove_preview_worktree EXIT

  git worktree add --quiet --detach "$preview_dir" "$base_ref"
  cd "$preview_dir"
  # Squash merges turn the PR title into the commit subject, so the title decides the bump, not the branch commits.
  git -c user.name=preview -c user.email=preview@example.invalid commit --quiet --allow-empty -m "$title"

  local version status=0
  version="$("$SCRIPTS_DIR/update_version.sh" 2>/dev/null)" || status=$?
  if [[ $status -eq $EXIT_NO_RELEASE ]]; then
    echo "### Next release: none"
    echo
    echo "Merging this PR does not trigger a release."
    return
  fi
  if [[ $status -ne 0 ]]; then exit "$status"; fi

  echo "### Next release: v$version"
  echo
  "$SCRIPTS_DIR/generate_changelog.sh" --dry-run "v$version" 2>/dev/null
}

main "$@"

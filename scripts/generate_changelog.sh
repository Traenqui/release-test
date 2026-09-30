#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/release.sh"

readonly CHANGELOG_FILE="CHANGELOG.md"
readonly GITHUB_REMOTE_PATTERN='github\.com[:/]([^/]+/[^/]+)$'
readonly PULL_REQUEST_PATTERN='\(#([0-9]+)\)'
readonly UNRELEASED_LABEL="Unreleased"
readonly SECTION_ORDER=(breaking feat fix perf refactor style test docs build ci other)
declare -rA SECTION_TITLES=(
  [breaking]="⚠ BREAKING CHANGES"
  [feat]="✨ Features"
  [fix]="🐛 Bug Fixes"
  [perf]="⚡ Performance Improvements"
  [refactor]="🛠 Code Refactoring"
  [style]="🎨 Style Changes"
  [test]="🧪 Tests"
  [docs]="📚 Documentation"
  [build]="🔧 Build System"
  [ci]="👷 CI Configuration"
  [other]="🔄 Other Changes"
)

repository_slug() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    echo "$GITHUB_REPOSITORY"
    return
  fi
  local remote_url
  remote_url="$(git config --get remote.origin.url)"
  remote_url="${remote_url%.git}"
  if [[ "$remote_url" =~ $GITHUB_REMOTE_PATTERN ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  echo "Unsupported git remote: $remote_url" >&2
  return 1
}

link_pull_request() {
  local subject="$1" slug="$2"
  if [[ "$subject" =~ $PULL_REQUEST_PATTERN ]]; then
    local number="${BASH_REMATCH[1]}"
    subject="${subject/"(#$number)"/"([#$number](https://github.com/$slug/pull/$number))"}"
  fi
  echo "$subject"
}

render_section() {
  local range="$1" label="$2" date="$3" slug="$4"
  local -A entries=()
  local hash subject kind
  while IFS="$FIELD_SEPARATOR" read -r hash subject kind; do
    if [[ -z "${SECTION_TITLES[$kind]:-}" ]]; then kind=other; fi
    entries[$kind]+="* $(link_pull_request "$subject" "$slug") [\`$hash\`](https://github.com/$slug/commit/$hash)"$'\n'
  done < <(each_commit "$range")

  if [[ ${#entries[@]} -eq 0 ]]; then return 0; fi
  printf '## [%s] - %s\n' "$label" "$date"
  for kind in "${SECTION_ORDER[@]}"; do
    if [[ -n "${entries[$kind]:-}" ]]; then
      printf '\n### %s\n%s' "${SECTION_TITLES[$kind]}" "${entries[$kind]}"
    fi
  done
}

tag_date() {
  git for-each-ref --format='%(creatordate:short)' "refs/tags/$1"
}

render_full_history() {
  local slug="$1" tags index range previous_tag section
  local -a sections=()
  mapfile -t tags < <(git tag --merged HEAD --list "$SEMVER_TAG_GLOB" --sort=-v:refname)

  section="$(render_section "${tags[0]:+${tags[0]}..}HEAD" "$UNRELEASED_LABEL" "$(date +%F)" "$slug")"
  if [[ -n "$section" ]]; then sections+=("$section"); fi
  for index in "${!tags[@]}"; do
    previous_tag="${tags[$((index + 1))]:-}"
    range="${previous_tag:+$previous_tag..}${tags[$index]}"
    section="$(render_section "$range" "${tags[$index]}" "$(tag_date "${tags[$index]}")" "$slug")"
    if [[ -n "$section" ]]; then sections+=("$section"); fi
  done

  local first=true
  for section in "${sections[@]}"; do
    if [[ "$first" == false ]]; then echo; fi
    printf '%s\n' "$section"
    first=false
  done
}

render_pending_release() {
  local slug="$1" label="$2" tag
  tag="$(latest_release_tag "$label")"
  render_section "${tag:+$tag..}HEAD" "$label" "$(date +%F)" "$slug"
}

without_unreleased_section() {
  awk '/^## \[Unreleased\]/ { skip = 1; next } /^## \[/ { skip = 0 } !skip' "$1"
}

prepend_to_changelog() {
  local section="$1"
  local temporary_file="$CHANGELOG_FILE.tmp"
  {
    printf '%s\n' "$section"
    if [[ -f "$CHANGELOG_FILE" ]]; then
      echo
      without_unreleased_section "$CHANGELOG_FILE"
    fi
  } > "$temporary_file"
  mv "$temporary_file" "$CHANGELOG_FILE"
}

usage() {
  echo "Usage: $0 [--init] [--dry-run] [vMAJOR.MINOR.PATCH]" >&2
  exit 1
}

main() {
  local is_init=false is_dry_run=false label="$UNRELEASED_LABEL" argument
  for argument in "$@"; do
    case "$argument" in
      --init) is_init=true ;;
      --dry-run) is_dry_run=true ;;
      v*) if [[ "$argument" =~ $SEMVER_TAG_PATTERN ]]; then label="$argument"; else usage; fi ;;
      *) usage ;;
    esac
  done

  cd "$(git rev-parse --show-toplevel)"
  local slug content
  slug="$(repository_slug)"

  if [[ "$is_init" == true ]]; then
    content="$(render_full_history "$slug")"
  else
    content="$(render_pending_release "$slug" "$label")"
  fi

  if [[ -z "$content" ]]; then
    echo "No commits since the last release." >&2
    exit 0
  fi
  if [[ "$is_dry_run" == true ]]; then
    printf '%s\n' "$content"
    return
  fi
  if [[ "$is_init" == true ]]; then
    printf '%s\n' "$content" > "$CHANGELOG_FILE"
  else
    prepend_to_changelog "$content"
  fi
  echo "$CHANGELOG_FILE updated [$label]" >&2
}

main "$@"

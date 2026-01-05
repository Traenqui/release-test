#!/bin/bash

readonly SEMVER_TAG_GLOB='v[0-9]*.[0-9]*.[0-9]*'
readonly SEMVER_TAG_PATTERN='^v([0-9]+)\.([0-9]+)\.([0-9]+)$'
readonly CONVENTIONAL_SUBJECT_PATTERN='^([a-z]+)(\([^)]*\))?(!)?: '
readonly BREAKING_FOOTER_PATTERN='^BREAKING[ -]CHANGE: '
readonly KNOWN_COMMIT_TYPES=" feat fix perf refactor style test docs build ci chore revert "
readonly EXIT_NO_RELEASE=3
readonly FIELD_SEPARATOR=$'\x1f'
readonly RECORD_SEPARATOR=$'\x1e'

latest_release_tag() {
  git describe --tags --abbrev=0 --match "$SEMVER_TAG_GLOB" HEAD 2>/dev/null || true
}

commit_kind() {
  local subject="$1" body="$2"
  if grep -qE "$BREAKING_FOOTER_PATTERN" <<< "$body"; then
    echo breaking
    return
  fi
  if [[ "$subject" =~ $CONVENTIONAL_SUBJECT_PATTERN ]]; then
    local type="${BASH_REMATCH[1]}" bang="${BASH_REMATCH[3]}"
    if [[ -n "$bang" ]]; then
      echo breaking
    elif [[ "$KNOWN_COMMIT_TYPES" == *" $type "* ]]; then
      echo "$type"
    else
      echo other
    fi
    return
  fi
  echo other
}

each_commit() {
  local range="$1" hash subject body
  git log "$range" --no-merges --format="%h${FIELD_SEPARATOR}%s${FIELD_SEPARATOR}%b${RECORD_SEPARATOR}" |
    while IFS="$FIELD_SEPARATOR" read -r -d "$RECORD_SEPARATOR" hash subject body; do
      hash="${hash#$'\n'}"
      printf '%s%s%s%s%s\n' "$hash" "$FIELD_SEPARATOR" "$subject" "$FIELD_SEPARATOR" "$(commit_kind "$subject" "$body")"
    done
}

#!/bin/bash
set -uo pipefail

readonly SANDBOX_REPO="$(git rev-parse --show-toplevel)"
readonly EXIT_NO_RELEASE=3
export GITHUB_REPOSITORY="traenqui/release-test"

failures=0
scratch_dirs=()

cleanup() {
  if [[ ${#scratch_dirs[@]} -gt 0 ]]; then rm -rf "${scratch_dirs[@]}"; fi
}

fresh_clone() {
  local scratch
  scratch="$(mktemp -d)"
  scratch_dirs+=("$scratch")
  git clone --quiet --bare "$SANDBOX_REPO" "$scratch/origin.git"
  git clone --quiet "$scratch/origin.git" "$scratch/work"
  cd "$scratch/work" || exit 1
  git config user.name "Release Test"
  git config user.email "test@example.invalid"
  git switch --quiet -C master
  git push --quiet --force origin master
}

tag_and_push() {
  git tag "$1"
  git push --quiet origin master "$1"
}

add_commit() {
  git commit --quiet --allow-empty -m "$1" ${2:+-m "$2"}
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    echo "      expected: $expected"
    echo "      actual:   $actual"
    failures=$((failures + 1))
  fi
}

check_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then check "$name" yes yes; else check "$name" "contains '$needle'" "missing"; fi
}

check_missing() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then check "$name" "no '$needle'" "found"; else check "$name" yes yes; fi
}

changelog_section() {
  awk -v heading="## [$1]" 'index($0, heading) == 1 { found = 1; print; next } /^## \[/ { found = 0 } found' <<< "$2"
}

test_no_release_when_only_docs_chore_and_unknown_types() {
  fresh_clone
  local log status=0
  log="$(./scripts/update_version.sh 2>&1 >/dev/null)" || status=$?
  check "no release: exit code" "$EXIT_NO_RELEASE" "$status"
  check_contains "no release: hotfix tag off master is ignored" "Base tag: v2.0.1" "$log"
}

test_feat_bumps_minor() {
  fresh_clone
  add_commit "feat(chat): stream answers (#10)"
  check "feat bumps minor" "2.1.0" "$(./scripts/update_version.sh 2>/dev/null)"
}

test_breaking_footer_bumps_major_without_conventional_subject() {
  fresh_clone
  add_commit "Rework public api" "BREAKING-CHANGE: all routes renamed"
  check "breaking footer bumps major" "3.0.0" "$(./scripts/update_version.sh 2>/dev/null)"
}

test_full_changelog() {
  fresh_clone
  local changelog major_release breaking_block
  changelog="$(./scripts/generate_changelog.sh --init --dry-run 2>/dev/null)"
  major_release="$(changelog_section v2.0.0 "$changelog")"
  breaking_block="$(sed -n '/BREAKING CHANGES/,/^$/p' <<< "$major_release")"
  check_contains "changelog: feat! is breaking" "* feat!: version 2" "$breaking_block"
  check_contains "changelog: footer is breaking" "* refactor(api): rename chat routes" "$breaking_block"
  check_missing "changelog: v2.0.0 has no feature section" "### ✨ Features" "$major_release"
  check_missing "changelog: hotfix off master is not listed" "fix(deploy)" "$changelog"
  check_contains "changelog: body line does not make docs a feature" "### 📚 Documentation"$'\n'"* docs: describe release flow" "$changelog"
  check_contains "changelog: unknown type is other" "* cinema: not a conventional type" "$(sed -n '/Other Changes/,/^$/p' <<< "$changelog")"
  check_contains "changelog: pull request is linked" "([#8](https://github.com/traenqui/release-test/pull/8))" "$changelog"
  check "changelog: newest entry is unreleased" "## [Unreleased]" "$(head -1 <<< "$changelog" | cut -d' ' -f1-2)"
}

test_release_accepts_matching_tag() {
  fresh_clone
  add_commit "feat(chat): stream answers (#10)"
  tag_and_push v2.1.0
  local notes status=0
  notes="$(./release.sh v2.1.0 2>/dev/null)" || status=$?
  check "release: matching tag succeeds" 0 "$status"
  check "release: notes use the tag" "## [v2.1.0] - $(date +%F)" "$(head -1 <<< "$notes")"
  check_contains "release: notes list the feature" "* feat(chat): stream answers ([#10]" "$notes"
  check_missing "release: notes skip older releases" "feat(auth): add login" "$notes"
}

test_release_rejects_wrong_version() {
  fresh_clone
  add_commit "feat(chat): stream answers (#10)"
  tag_and_push v2.0.3
  local output status=0
  output="$(./release.sh v2.0.3 2>&1)" || status=$?
  check "release: wrong version fails" 1 "$status"
  check_contains "release: wrong version message" "Expected v2.1.0." "$output"
}

test_release_rejects_tag_without_release_commits() {
  fresh_clone
  add_commit "docs: fix typo"
  tag_and_push v2.0.3
  local output status=0
  output="$(./release.sh v2.0.3 2>&1)" || status=$?
  check "release: no relevant commits fails" 1 "$status"
  check_contains "release: no relevant commits message" "has no release-relevant commits." "$output"
}

test_release_rejects_tag_off_master() {
  fresh_clone
  git switch --quiet -c side
  add_commit "feat(chat): stream answers (#10)"
  git tag v2.1.0
  git push --quiet origin v2.1.0
  local output status=0
  output="$(./release.sh v2.1.0 2>&1)" || status=$?
  check "release: tag off master fails" 1 "$status"
  check_contains "release: tag off master message" "Tag v2.1.0 is not on 'master'." "$output"
}

test_changelog_lists_staging_commits_as_unreleased() {
  fresh_clone
  add_commit "feat(chat): stream answers (#10)"
  git push --quiet origin master
  local status=0
  ./scripts/update_changelog.sh > /dev/null 2>&1 || status=$?
  check "changelog update: succeeds" 0 "$status"
  check "changelog update: commit pushed" "$(git rev-parse HEAD)" "$(git ls-remote origin refs/heads/master | cut -f1)"
  check "changelog update: bot commit subject" "chore(changelog): update changelog" "$(git log -1 --format=%s)"
  check_contains "changelog update: feature is unreleased" "* feat(chat): stream answers" "$(changelog_section Unreleased "$(cat CHANGELOG.md)")"
  check_missing "changelog update: bot commit is not listed" "chore(changelog)" "$(cat CHANGELOG.md)"
  local head_before
  head_before="$(git rev-parse HEAD)"
  ./scripts/update_changelog.sh > /dev/null 2>&1
  check "changelog update: second run adds no commit" "$head_before" "$(git rev-parse HEAD)"
}

test_changelog_turns_unreleased_into_release() {
  fresh_clone
  add_commit "feat(chat): stream answers (#10)"
  git push --quiet origin master
  ./scripts/update_changelog.sh > /dev/null 2>&1
  tag_and_push v2.1.0
  ./scripts/update_changelog.sh > /dev/null 2>&1
  check "changelog release: heading" "## [v2.1.0] - $(date +%F)" "$(head -1 CHANGELOG.md)"
  check_missing "changelog release: no unreleased section left" "[Unreleased]" "$(cat CHANGELOG.md)"
  check "changelog release: pushed" "$(git rev-parse HEAD)" "$(git ls-remote origin refs/heads/master | cut -f1)"
}

test_pr_title_check() {
  local title status
  for title in "feat(chat): stream answers" "fix!: drop legacy route" "chore: bump deps"; do
    status=0
    ./scripts/check_pr_title.sh "$title" > /dev/null || status=$?
    check "pr title accepted: $title" 0 "$status"
  done
  for title in "cinema: not a type" "feature: typo" "Update Dockerfile" "feat:missing space" ""; do
    status=0
    ./scripts/check_pr_title.sh "$title" > /dev/null || status=$?
    check "pr title rejected: '$title'" 1 "$status"
  done
}

test_preview_uses_pr_title_for_bump() {
  fresh_clone
  local preview
  preview="$(./scripts/release_preview.sh origin/master "feat(chat): stream answers (#10)")"
  check "preview: feat title shows minor" "### Next release: v2.1.0" "$(head -1 <<< "$preview")"
  check_contains "preview: title is in changelog" "* feat(chat): stream answers ([#10]" "$preview"
  check_contains "preview: changelog uses version label" "## [v2.1.0]" "$preview"
}

test_preview_without_release() {
  fresh_clone
  check "preview: docs title means no release" "### Next release: none" "$(./scripts/release_preview.sh origin/master "docs: fix typo" | head -1)"
}

test_preview_leaves_repository_untouched() {
  fresh_clone
  local head_before
  head_before="$(git rev-parse HEAD)"
  ./scripts/release_preview.sh origin/master "feat: anything" > /dev/null
  check "preview: HEAD unchanged" "$head_before" "$(git rev-parse HEAD)"
  check "preview: no worktree left" 1 "$(git worktree list | wc -l | tr -d ' ')"
  check "preview: working tree clean" "" "$(git status --porcelain)"
}

main() {
  local test_name
  for test_name in $(declare -F | awk '{print $3}' | grep '^test_'); do
    (failures=0; trap cleanup EXIT; cd "$SANDBOX_REPO" && "$test_name"; exit "$failures")
    failures=$((failures + $?))
  done
  echo
  if [[ $failures -eq 0 ]]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
  [[ $failures -eq 0 ]]
}

main "$@"

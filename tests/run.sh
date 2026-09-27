#!/usr/bin/env bash
# Lightweight, dependency-free test suite for skills/scratch-dir/scripts/scratch-hook.sh.
#
# Every test runs in a fresh throwaway repo, with HOME/GIT_CONFIG_GLOBAL/
# GIT_CONFIG_SYSTEM redirected to a temp dir so nothing touches this machine's real
# ~/.gitconfig or any skill install. Requires bash (test runner only; the script under
# test stays POSIX sh) and git 2.32+ (for GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM).
#
# Usage: tests/run.sh [name-filter]

set -uo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hookScript="$scriptDir/skills/scratch-dir/scripts/scratch-hook.sh"

passCount=0
failCount=0
currentTest=""

pass() {
  passCount=$((passCount + 1))
}

fail() {
  failCount=$((failCount + 1))
  echo "FAIL: $currentTest: $1"
}

assertEqual() {
  local expected="$1" actual="$2" message="${3:-}"
  if [ "$expected" = "$actual" ]; then
    pass
  else
    fail "expected [$expected], got [$actual] $message"
  fi
}

assertContains() {
  local haystack="$1" needle="$2" message="${3:-}"
  case "$haystack" in
    *"$needle"*) pass ;;
    *) fail "expected output to contain [$needle], got [$haystack] $message" ;;
  esac
}

assertNotContains() {
  local haystack="$1" needle="$2" message="${3:-}"
  case "$haystack" in
    *"$needle"*) fail "expected output NOT to contain [$needle], got [$haystack] $message" ;;
    *) pass ;;
  esac
}

assertSuccess() {
  local code="$1" message="${2:-}"
  if [ "$code" -eq 0 ]; then pass; else fail "expected success (exit 0), got exit $code $message"; fi
}

assertFailure() {
  local code="$1" message="${2:-}"
  if [ "$code" -ne 0 ]; then pass; else fail "expected failure (nonzero exit), got exit $code $message"; fi
}

assertFileExists() {
  local path="$1" message="${2:-}"
  if [ -f "$path" ]; then pass; else fail "expected $path to exist $message"; fi
}

assertFileAbsent() {
  local path="$1" message="${2:-}"
  if [ ! -f "$path" ]; then pass; else fail "expected $path to be absent $message"; fi
}

assertExecutable() {
  local path="$1" message="${2:-}"
  if [ -x "$path" ]; then pass; else fail "expected $path to be executable $message"; fi
}

hook() {
  sh "$hookScript" "$@"
}

setUp() {
  tmpHome="$(mktemp -d)"
  tmpRepo="$(mktemp -d)"
  export HOME="$tmpHome"
  export GIT_CONFIG_GLOBAL="$tmpHome/.gitconfig"
  export GIT_CONFIG_SYSTEM="$tmpHome/.gitconfig-system-empty"
  : > "$GIT_CONFIG_GLOBAL"
  : > "$GIT_CONFIG_SYSTEM"
  export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
  cd "$tmpRepo"
  git init -q -b main
}

tearDown() {
  cd "$scriptDir"
  rm -rf "$tmpRepo" "$tmpHome"
}

# --- status ---

test_status_not_a_repo() {
  local plainDir output
  plainDir="$(mktemp -d)"
  cd "$plainDir"
  output="$(hook status)"
  assertEqual "not-a-repo" "$output"
  cd "$scriptDir"
  rm -rf "$plainDir"
}

test_status_not_installed() {
  assertEqual "not-installed" "$(hook status)"
}

test_status_skip_repo() {
  git config --local scratchSkill.skipHookPrompt true
  assertEqual "skip-repo" "$(hook status)"
}

test_status_skip_global() {
  git config --global scratchSkill.skipHookPrompt true
  assertEqual "skip-global" "$(hook status)"
}

test_status_global_skip_wins_over_local_no() {
  git config --global scratchSkill.skipHookPrompt true
  git config --local scratchSkill.skipHookPrompt false
  assertEqual "skip-global" "$(hook status)"
}

test_status_installed() {
  hook install >/dev/null
  assertEqual "installed" "$(hook status)"
}

test_status_foreign_plain_hook() {
  local hooksDir
  hooksDir="$(git rev-parse --git-path hooks)"
  mkdir -p "$hooksDir"
  printf '#!/bin/sh\necho hi\n' > "$hooksDir/pre-commit"
  chmod +x "$hooksDir/pre-commit"
  assertEqual "foreign-hook-present" "$(hook status)"
}

test_status_foreign_precommit_framework() {
  echo "repos: []" > .pre-commit-config.yaml
  assertEqual "foreign-hook-present" "$(hook status)"
}

test_status_foreign_lefthook() {
  touch lefthook.yml
  assertEqual "foreign-hook-present" "$(hook status)"
}

# --- install ---

test_install_writes_marked_executable_hook() {
  local hooksDir output
  hooksDir="$(git rev-parse --git-path hooks)"
  output="$(hook install)"
  assertEqual "installed:$hooksDir/pre-commit" "$output"
  assertContains "$(cat "$hooksDir/pre-commit")" "scratch-dir-skill"
  assertExecutable "$hooksDir/pre-commit"
}

test_install_idempotent() {
  local hooksDir
  hooksDir="$(git rev-parse --git-path hooks)"
  hook install >/dev/null
  assertEqual "already-installed:$hooksDir/pre-commit" "$(hook install)"
}

test_install_targets_husky_when_core_hooks_path_set() {
  # A Husky repo sets core.hooksPath=.husky itself; hooksDir() resolves that.
  mkdir .husky
  git config core.hooksPath .husky
  assertEqual "installed:.husky/pre-commit" "$(hook install)"
  assertContains "$(cat .husky/pre-commit)" "scratch-dir-skill"
}

test_install_ignores_bare_husky_dir_without_core_hooks_path() {
  # A repo can have .husky/ files checked in (e.g. from package.json's "prepare"
  # script) before `npm install` has run, so core.hooksPath isn't set yet. Install
  # must target the real hooks directory in that case, not .husky/pre-commit, since
  # git wouldn't actually execute a hook placed there.
  local hooksDir
  hooksDir="$(git rev-parse --git-path hooks)"
  mkdir .husky
  assertEqual "installed:$hooksDir/pre-commit" "$(hook install)"
  assertFileAbsent ".husky/pre-commit" "install must not write into .husky/ unless core.hooksPath actually points there"
}

test_install_blocked_when_framework_managed() {
  echo "repos: []" > .pre-commit-config.yaml
  assertEqual "blocked:framework-managed" "$(hook install)"
}

test_install_preserves_existing_foreign_content() {
  local hooksDir
  hooksDir="$(git rev-parse --git-path hooks)"
  mkdir -p "$hooksDir"
  printf '#!/bin/sh\necho existing-hook-ran\n' > "$hooksDir/pre-commit"
  chmod +x "$hooksDir/pre-commit"
  hook install >/dev/null
  local content
  content="$(cat "$hooksDir/pre-commit")"
  assertContains "$content" "existing-hook-ran"
  assertContains "$content" "scratch-dir-skill"
}

# --- uninstall ---

test_uninstall_when_not_installed() {
  assertEqual "not-installed" "$(hook uninstall)"
}

test_uninstall_removes_block_keeps_foreign_content() {
  local hooksDir content
  hooksDir="$(git rev-parse --git-path hooks)"
  mkdir -p "$hooksDir"
  printf '#!/bin/sh\necho existing-hook-ran\n' > "$hooksDir/pre-commit"
  chmod +x "$hooksDir/pre-commit"
  hook install >/dev/null
  hook uninstall >/dev/null
  content="$(cat "$hooksDir/pre-commit")"
  assertContains "$content" "existing-hook-ran"
  assertNotContains "$content" "scratch-dir-skill"
}

test_uninstall_deletes_bare_stub_entirely() {
  local hooksDir
  hooksDir="$(git rev-parse --git-path hooks)"
  hook install >/dev/null
  hook uninstall >/dev/null
  assertFileAbsent "$hooksDir/pre-commit"
  assertEqual "not-installed" "$(hook status)"
}

# --- functional: does the installed hook actually block/allow the right commits ---

test_commit_blocked_for_new_file_added_under_scratch() {
  hook install >/dev/null
  mkdir -p _scratch
  echo "content" > _scratch/note.md
  git add _scratch/note.md
  local output code
  output="$(git commit -m "should be blocked" 2>&1)"
  code=$?
  assertFailure "$code"
  assertContains "$output" "Commit blocked"
  assertContains "$(git status --short)" "A  _scratch/note.md" "file should remain staged"
}

test_commit_blocked_for_rename_landing_in_scratch() {
  echo "content" > outside.md
  git add outside.md
  git commit -q -m "seed"
  hook install >/dev/null
  mkdir -p _scratch
  git mv outside.md _scratch/renamed.md
  local output code
  output="$(git commit -m "should be blocked" 2>&1)"
  code=$?
  assertFailure "$code"
  assertContains "$output" "Commit blocked"
}

test_commit_allowed_for_rename_promoting_out_of_scratch() {
  mkdir -p _scratch
  echo "content" > _scratch/draft.md
  git add _scratch/draft.md
  git commit -q -m "seed"
  hook install >/dev/null
  git mv _scratch/draft.md promoted.md
  git commit -q -m "promote"
  assertSuccess "$?"
}

test_commit_allowed_when_no_scratch_changes() {
  hook install >/dev/null
  echo "content" > normal.md
  git add normal.md
  git commit -q -m "normal commit"
  assertSuccess "$?"
}

test_commit_allowed_for_modification_of_preexisting_scratch_file() {
  # Only additions and renames landing in _scratch/ are blocked; a later modification
  # of a file that predates the hook is intentionally allowed through.
  mkdir -p _scratch
  echo "v1" > _scratch/draft.md
  git add _scratch/draft.md
  git commit -q -m "seed"
  hook install >/dev/null
  echo "v2" >> _scratch/draft.md
  git add _scratch/draft.md
  git commit -q -m "modify"
  assertSuccess "$?"
}

runTests() {
  local testFns t
  testFns="$(declare -F | awk '{print $3}' | grep '^test_')"
  if [ -n "${1:-}" ]; then
    testFns="$(printf '%s\n' "$testFns" | grep -- "$1" || true)"
  fi
  for t in $testFns; do
    currentTest="$t"
    setUp
    "$t"
    tearDown
  done
}

runTests "${1:-}"

# Only as part of "run everything" (no name filter): it's a single all-or-nothing
# check, not a set of named test_ cases the filter above could meaningfully match.
if [ -z "${1:-}" ]; then
  echo ""
  echo "--- SKILL.md frontmatter (Agent Skills spec) ---"
  if ! sh "$scriptDir/tests/check-frontmatter.sh"; then
    failCount=$((failCount + 1))
  fi
fi

echo ""
echo "Passed: $passCount  Failed: $failCount"
[ "$failCount" -eq 0 ]

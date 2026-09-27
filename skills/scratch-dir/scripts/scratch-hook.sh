#!/bin/sh
# Manages the pre-commit hook that blocks committing files under _scratch/.
# Usage: scratch-hook.sh {status|install|uninstall}
#
# status output (one line): not-a-repo | skip-global | skip-repo | installed |
#                            foreign-hook-present | not-installed
# install output (one line): not-a-repo | already-installed:<path> |
#                             blocked:framework-managed | installed:<path>
# uninstall output (one line): not-a-repo | not-installed | removed:<path>

set -eu

markerBegin='# >>> scratch-dir-skill >>>'
markerEnd='# <<< scratch-dir-skill <<<'

hookBlock() {
  printf '%s\n' "$markerBegin"
  cat <<'EOF'
offending=$(git diff --cached --name-status --diff-filter=AR | awk -F'\t' '{ path = ($1 ~ /^R/) ? $3 : $2 } path ~ /^_scratch\// { print path }')
if [ -n "$offending" ]; then
  echo "Commit blocked: staged scratch file(s) under _scratch/ (never committed by convention):"
  echo "$offending" | sed 's/^/  /'
  echo "Unstage with: git restore --staged <file>"
  exit 1
fi
EOF
  printf '%s\n' "$markerEnd"
}

isGitRepo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Respects core.hooksPath, so this resolves to .husky/ automatically once Husky has
# wired that up (during `husky`/`husky install`). Deliberately does not special-case
# a bare `.husky/` directory: on a repo where those files are checked in but
# `npm install` hasn't run yet, core.hooksPath isn't set, and writing into
# `.husky/pre-commit` in that state would produce a file git never actually executes.
hooksDir() {
  git rev-parse --git-path hooks
}

hasMarker() {
  [ -f "$1" ] && grep -qF "$markerBegin" "$1" 2>/dev/null
}

frameworkManaged() {
  [ -f .pre-commit-config.yaml ] || [ -f lefthook.yml ] || [ -f lefthook.yaml ]
}

cmdStatus() {
  if ! isGitRepo; then
    echo "not-a-repo"
    return
  fi

  if [ "$(git config --global --get scratchSkill.skipHookPrompt 2>/dev/null || echo false)" = "true" ]; then
    echo "skip-global"
    return
  fi
  if [ "$(git config --local --get scratchSkill.skipHookPrompt 2>/dev/null || echo false)" = "true" ]; then
    echo "skip-repo"
    return
  fi

  hookFile="$(hooksDir)/pre-commit"

  if hasMarker "$hookFile"; then
    echo "installed"
    return
  fi

  if [ -f "$hookFile" ]; then
    echo "foreign-hook-present"
    return
  fi

  if frameworkManaged; then
    echo "foreign-hook-present"
    return
  fi

  echo "not-installed"
}

cmdInstall() {
  if ! isGitRepo; then
    echo "not-a-repo"
    return
  fi

  hookFile="$(hooksDir)/pre-commit"

  if hasMarker "$hookFile"; then
    echo "already-installed:$hookFile"
    return
  fi

  if frameworkManaged; then
    echo "blocked:framework-managed"
    return
  fi

  mkdir -p "$(dirname "$hookFile")"

  if [ ! -f "$hookFile" ]; then
    printf '#!/bin/sh\n' > "$hookFile"
  fi

  hookBlock >> "$hookFile"
  chmod +x "$hookFile"
  echo "installed:$hookFile"
}

cmdUninstall() {
  if ! isGitRepo; then
    echo "not-a-repo"
    return
  fi

  hookFile="$(hooksDir)/pre-commit"

  if ! hasMarker "$hookFile"; then
    echo "not-installed"
    return
  fi

  tmp="$(mktemp)"
  awk -v b="$markerBegin" -v e="$markerEnd" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }
  ' "$hookFile" > "$tmp"

  remainder="$(grep -v '^#!' "$tmp" | tr -d '[:space:]')"
  if [ -z "$remainder" ]; then
    rm -f "$hookFile" "$tmp"
  else
    mv "$tmp" "$hookFile"
  fi
  echo "removed:$hookFile"
}

case "${1:-}" in
  status) cmdStatus ;;
  install) cmdInstall ;;
  uninstall) cmdUninstall ;;
  *)
    echo "usage: scratch-hook.sh {status|install|uninstall}" >&2
    exit 2
    ;;
esac

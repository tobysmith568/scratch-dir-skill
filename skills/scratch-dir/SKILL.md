---
name: scratch-dir
description: "Use before creating any file that supports the current task but isn't itself a deliverable and isn't meant to be committed: a plan, a design doc, an investigation write-up, notes, a findings report, or a throwaway example/demo/prototype (an HTML mockup, a one-off script, sample output) that the user will open, view, or iterate on. Covers where such a file should live and first-time setup of a git hook that keeps it from being committed by accident. Triggers on requests like \"make a plan for X\", \"investigate Y and report back\", \"write up your findings\", \"knock up a quick demo of Z\", even when no scratch/temp language is used. Use judgment on borderline cases; this isn't a fixed list of file types. Not for purely internal intermediate files the user will never see; those belong in the harness's own scratchpad/temp directory instead."
---

# Scratch files

## What qualifies

A scratch artifact supports the current task without being a deliverable itself, and isn't meant to be committed. Examples: a plan, a design doc, an investigation write-up, notes, a findings report, a throwaway example/demo/prototype (an HTML mockup, a one-off script, sample data) the user will open or iterate on.

Not scratch: source code changes, user-facing docs (README, CHANGELOG, API docs), or anything meant to ship. Also not scratch: purely internal intermediate files the user will never look at; those belong in the harness's own scratchpad/temp directory, not here. Use judgment on the edge cases; this isn't a fixed list.

## Where they live

`./_scratch/` at the repo root. A scratch artifact can be a single file or a small directory of related files (e.g. `_scratch/hero-fonts-demo/index.html` plus its assets). Prefer descriptive kebab-case names (`feature-x-plan.md`, `investigate-slow-query.md`).

Never add `_scratch/` to `.gitignore`: the user stages these files deliberately to read diffs on later edits via `git diff --cached`. Staging is expected and fine; only *committing* is meant to be blocked.

## Before creating the first scratch artifact in a repo this session

Run this check before every scratch-artifact creation: it's cheap and self-limiting, so there's no need to track "have I already asked" separately.

1. **Resolve the path to this skill's own `scripts/scratch-hook.sh`**: a path relative to this `SKILL.md`'s own directory (the skill root). If this harness tells you where the currently active skill's own files live, join that with `scripts/scratch-hook.sh` directly. Otherwise, locate the skill root yourself: check common install locations for the first that contains `scratch-dir/scripts/scratch-hook.sh`, e.g. (for Claude Code specifically) `.claude/skills/` (project-scope) or `~/.claude/skills/` (global-scope).

   If none of those apply (unrecognized harness, nothing found), or the shell fails to execute the script (e.g. no POSIX shell on this platform/harness), skip straight to step 4 with "not-installed" behavior, using the manual snippet below; never block file creation on this.

2. Run `sh <that-path> status`. It prints exactly one line:

   | Output | Meaning | Action |
   |---|---|---|
   | `not-a-repo` | not inside a git work tree | proceed silently, nothing to protect |
   | `skip-global` | user said "never ask again" on this machine | proceed silently |
   | `skip-repo` | user said "don't ask about this repo" | proceed silently |
   | `installed` | hook already in place | proceed silently |
   | `foreign-hook-present` | an unrecognized pre-commit hook/framework exists | one heads-up line + manual snippet (below), then proceed; don't block |
   | `not-installed` | no hook, no skip flag | go to step 3 |

3. **Only on `not-installed`:** first check `.gitignore` for any rule that would match `_scratch` (e.g. `_scratch`, `/_scratch`, `_scratch/`) and warn the user if found: that would defeat the purpose (files need to stay visible/diffable, not hidden).

   Then ask the user exactly these four options, using a structured-choice tool if this harness provides one (e.g. Claude Code's AskUserQuestion), otherwise plain text:
   - **Yes**: install the hook
   - **No**: not now, ask again next time
   - **No, don't ask about this repo**
   - **No, never ask me again**

   Handle the answer:
   - *Yes* → run `sh <that-path> install`. It prints `installed:<path>` on success or `blocked:framework-managed` if a hook framework config appeared since the status check; treat that outcome the same as `foreign-hook-present` (manual snippet, proceed). Report the installed path to the user.
   - *No* → proceed with creating the file. No state change.
   - *No, don't ask about this repo* → run `git config --local scratchSkill.skipHookPrompt true`.
   - *No, never ask me again* → run `git config --global scratchSkill.skipHookPrompt true`.

4. Create the scratch artifact under `_scratch/`.

## Manual snippet (for `foreign-hook-present` or a failed install)

Tell the user their existing hook setup wasn't touched, and offer this to add by hand to their pre-commit hook (or equivalent step in their hook framework config):

```sh
offending=$(git diff --cached --name-status --diff-filter=AR | awk -F'\t' '{ path = ($1 ~ /^R/) ? $3 : $2 } path ~ /^_scratch\// { print path }')
if [ -n "$offending" ]; then
  echo "Commit blocked: staged scratch file(s) under _scratch/ (never committed by convention):"
  echo "$offending" | sed 's/^/  /'
  echo "Unstage with: git restore --staged <file>"
  exit 1
fi
```

## Non-goals

- Don't gitignore `_scratch/`.
- Don't auto-migrate loose planning docs already sitting at a repo root from before this convention existed: that's the user's call, not something to do unprompted.

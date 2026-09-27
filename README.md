# scratch-dir-skill

A Claude Code (and other agent-harness) skill that formalizes a "scratch file" convention: planning docs, investigation write-ups, and throwaway demo/prototype artifacts live in `./_scratch/` at a repo's root, never gitignored, so they stay diffable, but never committed.

## What it does

- Teaches the agent where scratch artifacts belong and what counts as one.
- Before creating the first scratch artifact in a repo, checks whether a git hook is in place that blocks committing anything under `_scratch/`, and offers to install one if not.
- Remembers a "don't ask" preference per-repo or per-machine via plain `git config` (`scratchSkill.skipHookPrompt`, local or global). This avoids depending on the agent's own memory recalling it correctly.

## Install

```sh
npx skills add tobysmith568/scratch-dir-skill    # this project only
npx skills add -g tobysmith568/scratch-dir-skill # every repo on this machine
```

## Layout

- `skills/scratch-dir/SKILL.md`: the skill itself (instructions read by the agent). Nested under `skills/<name>/` rather than sitting at the repo root, since that's the discovery convention `npx skills add` and most other agent-skill tooling actually expect (and it's also required for the skill's own directory name to match its frontmatter `name`, per the [Agent Skills spec](https://agentskills.io/specification)); the repo itself keeps a `-skill` suffix for discoverability, matching how other single-skill repos (e.g. Cloudflare's `security-audit-skill`) split the two concerns.
- `skills/scratch-dir/scripts/scratch-hook.sh`: `status` / `install` / `uninstall` for the pre-commit hook. Run it directly if you want to manage the hook by hand:

  ```sh
  sh skills/scratch-dir/scripts/scratch-hook.sh status
  sh skills/scratch-dir/scripts/scratch-hook.sh install
  sh skills/scratch-dir/scripts/scratch-hook.sh uninstall
  ```

See `skills/scratch-dir/SKILL.md` for the full convention and decision tree.

## Testing

```sh
tests/run.sh        # run everything
tests/run.sh rename # run only tests matching a name filter
```

Each test runs in a throwaway repo with `HOME`/`GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` redirected to a temp dir, so nothing touches this machine's real git config. No dependencies beyond `bash` and `git` (2.32+, for the config env vars). The same script runs in CI (`.github/workflows/test.yml`) on Linux, macOS, and Windows. Windows in particular exercises the POSIX-`sh` portability assumption `scratch-hook.sh` relies on.

A full `tests/run.sh` run (no name filter) also runs `tests/check-frontmatter.sh`, which checks `SKILL.md`'s frontmatter against the [Agent Skills spec](https://agentskills.io/specification): `name`/`description` length limits, `name` character rules, that the skill's directory name matches its `name` field, and that no unexpected frontmatter fields are present. It can also be run standalone, or against another skill directory: `sh tests/check-frontmatter.sh [skill-dir]`.

This only covers `scratch-hook.sh` and `SKILL.md`'s frontmatter. The rest of `SKILL.md` is instructions for an agent, not code, so it isn't unit-testable the same way: verifying it means actually driving the skill.

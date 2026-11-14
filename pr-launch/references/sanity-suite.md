# Sanity suite resolution (Stage 3)

Goal: before anything leaves the machine, run the suites a human would run as a last sanity
check: unit, then the end-to-end suites (UI and API). This file says how to find them in
whatever repo you're standing in, and how to run them without stepping on anything.

## 1. Unit

The verify gate pr-review-fix ran on its final round counts as the unit run, **if** it ran
the repo's unit tests and nothing has changed since. Otherwise run the repo's unit command
once (resolve it the way pr-review-fix's `references/verify-gate.md` does).

## 2. End-to-end suites

Collect **every** match from the first tier that has any, and record each one's exact
command and working directory. Later tiers are only consulted when earlier ones are empty.

| Tier | Where to look |
|---|---|
| 1 | The user's own instructions for this session or repo (agent instruction files such as `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, user-level and repo-level) naming a sanity, smoke or e2e run |
| 2 | Repo-local commands or skills whose name matches `e2e*`, `*-e2e*`, `smoke*`, `sanity*`: `.claude/commands/`, `.claude/skills/`, `.agents/commands/`, `.agents/skills/`, `.cursor/commands/`, `.codex/commands/` |
| 3 | User-level commands or skills with those names (`~/.claude/commands/`, `~/.claude/skills/`, `~/.agents/skills/`, and the equivalents for the current host). Use one only if the command it runs exists in this repo (the script name is in the build file) |
| 4 | Repo docs: `grep -niE "e2e|end-to-end|smoke" README.md CONTRIBUTING.md docs/*.md` for a documented run command |
| 5 | Build files: `package.json` scripts matching `e2e|smoke` (`jq -r '.scripts | keys[]' package.json`), `Makefile` targets, `justfile` recipes, `tox`/`nox` sessions, `Taskfile` tasks |

Rules:

- Separate UI and API suites when the repo has both (a Playwright/Cypress suite vs an HTTP
  suite). Run both. Skip a suite only when the diff can't reach it (for example a docs-only
  change), and say so.
- Watch-mode or interactive commands (`--ui`, `--headed`, `open`, `watch`) aren't sanity
  runs. Use the headless variant, or skip it and say why.
- Never run a suite tagged or documented as hitting a shared or remote environment
  (staging, prod, a cloud project). Local only.
- **Nothing found** in any tier → note `no e2e suite found` in the report and move on. It's
  not a blocker.

## 3. Services the suites need

Many e2e suites expect local services already running: emulators, a database, a dev server.
Read the suite's command and docs for hosts and ports (`*_EMULATOR_HOST`, `localhost:<port>`,
`DATABASE_URL`).

1. **Probe first.** `ss -ltnp 2>/dev/null || lsof -nP -iTCP -sTCP:LISTEN` for each port.
2. **Already listening:** check the listener was started from this worktree before using it:
   `readlink /proc/<pid>/cwd` (and its parent's) on Linux, `lsof -p <pid> | grep cwd`
   elsewhere. Another worktree's or another session's services → **BLOCKED**, naming the
   port and the process. Never kill or restart them.
3. **Not listening:** start them only the way the repo documents (or the user's
   instructions say), in the background, and wait for the ports. No documented way →
   **BLOCKED** (say which service and port the suite needs).
4. Before any seed or test-data script, confirm every emulator-host variable points at
   `127.0.0.1`/`localhost` and no cloud project variable is set without its emulator host.
   Never seed a remote project.
5. Services this run started get stopped at the end of the stage. Services that were already
   running stay as they were.

## 4. Failures

- Read the failing test's output and trace it to the source before deciding anything.
- **Caused by this branch:** fix it, rerun that suite, commit (repo convention; or
  `fix: <suite> failure`). Counts toward the run's `FIX_ATTEMPTS` (cap 3, shared with CI).
- **Environment** (a service didn't come up, a port clash, a missing install or build step):
  fix the environment the documented way and rerun. Doesn't count as a fix attempt, but a
  second identical failure → **BLOCKED**.
- **Flaky** (passes on an immediate rerun of the same test with no change): rerun once, and
  name the flaky test in the report.
- **Fails on the default branch too:** prove it by running the same test on a clean checkout
  of the default branch (`git worktree add` into a temp dir, run, remove). Proven →
  **BLOCKED** with the evidence. Never call a failure pre-existing without that.

## 5. Record

Write `$RUN/sanity.md`: each suite, the exact command, pass/fail counts, duration, fixes
made, and services started. The final report and the Jira update both read from it.

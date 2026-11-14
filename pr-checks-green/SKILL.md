---
name: pr-checks-green
description: >-
  Watch the CI checks on your own open PR's head commit and fix what breaks until every
  check is green. Reads each failure's log, classifies it as caused by the branch (fix,
  commit, push, wait again), infrastructure or flake (rerun once), or red on the base branch
  too (proven from the base branch's own runs, then reported, never assumed). Caps fix
  attempts and total wait, and ends with a parseable RESULT line. Use after pushing a branch
  with an open PR when you want the checks driven to green, standalone or as a building
  block inside an orchestrator such as pr-launch or pr-shepherd.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git/gh/jq) rather than
    host-specific tools. Reads GitHub Actions logs through gh; any other CI is read by
    following the check's link, and an unreadable log is reported rather than guessed at.
when_to_use: >-
  Use when a PR you authored has checks running or failing on its head and you want them
  green without babysitting the CI page. Not for someone else's PR, not for review feedback
  (pr-address-feedback / pr-shepherd), and not for merging.
argument-hint: "[pr-number]"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
---

# PR checks green (watch CI, fix until green)

Take the PR's head commit from "checks running or red" to "all green", fixing only what this
branch broke.

**Two ways to run:**

- **Standalone** (a user invoked it): every push it wants to make is shown first and waits
  for a yes. Reruns of failed jobs don't need one.
- **Called by an orchestrator** (pr-launch, pr-shepherd, or a repo-local equivalent): the
  caller's standing authorization covers the commits and plain pushes below. The caller
  passes in its state (inputs below) and reads back the `RESULT:` line.

**What it never does:** force-push, push any other branch, `--no-verify`, disable a check,
skip or mark a test as expected-to-fail to get green, edit CI config to drop a job, or call
a failure "pre-existing" without proof from the base branch.

## Inputs

An orchestrator passes these. Standalone, resolve them in Step 0.

| Name | Meaning | Default |
|---|---|---|
| `PR` | PR number | the current branch's open PR |
| `HEAD_OID` | the commit to watch | the PR's `headRefOid` |
| `REMOTE` / `BRANCH` | where fixes get pushed | the branch's upstream |
| `BASE` | the PR's base branch | `baseRefName` |
| `FIX_ATTEMPTS` | fix pushes already spent in the caller's run | `0` |
| `PR_CI_TIMEOUT` | total minutes to wait (falls back to `SHEPHERD_CI_TIMEOUT`) | `60` |

`$SKILL_DIR` is the directory this file was loaded from. Hosts usually state it; the usual
fallbacks are `~/.claude/skills/pr-checks-green` and `~/.agents/skills/pr-checks-green`.

## Step 0: Preflight (standalone only)

```sh
command -v git gh jq && gh auth status >/dev/null
REPO=$(git rev-parse --show-toplevel) || exit
gh pr view ${PR:+"$PR"} --json number,headRefOid,headRefName,baseRefName,state,author \
  -q '{pr:.number, head:.headRefOid, branch:.headRefName, base:.baseRefName, state:.state, author:.author.login}'
gh api user -q .login
```

- No open PR, or its author isn't you → `RESULT: NOOP (<why>)`.
- The local `HEAD` isn't the PR head → stop and say so. Fixes must land on top of the commit
  CI ran, so sync first.
- Uncommitted changes to tracked files → **BLOCKED**. Someone may be working here.

## Step 1: Wait for the checks

```sh
"$SKILL_DIR/scripts/wait-checks.sh" "$HEAD_OID" --pr "$PR"    # bounded: ≤ ~9 min per call
```

Call it again while it exits `8` (still pending), up to `PR_CI_TIMEOUT` minutes in total.
Past that → **BLOCKED** (checks still pending, name them).

| Exit | Meaning | Do |
|---|---|---|
| 0 | all passed or skipped | `RESULT: DONE` |
| 3 | no checks registered | `RESULT: DONE (no CI on this repo)`; the caller treats local verify as the evidence |
| 4 | the PR head is someone else's commit | **BLOCKED** |
| 1 | failures in `.failed[]` | Step 2 for each failure, then back to Step 1 |

## Step 2: Handle each failed check

1. **Read the failure.** For GitHub Actions the URL contains `/actions/runs/<run>/job/<job>`,
   so use `gh run view <run> --job <job> --log-failed`. For any other CI, follow the link.
   Can't read the cause → **BLOCKED**.
2. **Classify it:**
   - **Caused by this branch** (a test, lint, type or build error in code the PR touches or
     depends on): fix it, run the matching local check, commit with the repo's message
     convention (`fix: <check> failure` when it has none), plain-push
     (`git push "$REMOTE" "HEAD:$BRANCH"`), `FIX_ATTEMPTS+=1`,
     `HEAD_OID=$(git rev-parse HEAD)`, and go back to Step 1 on the new head.
     At `FIX_ATTEMPTS > 3` → **BLOCKED**, naming the check and the last error.
   - **Infrastructure or flake** (runner lost, network/registry/rate-limit error, a timeout
     with no failing assertion, a cancellation): `gh run rerun <run> --failed`, **once** per
     check per head. If it fails again, treat it as caused by the branch.
   - **Red on the base branch too:** prove it before saying so. Run
     `gh run list --branch "$BASE" --workflow "<workflow>" -L 3 --json conclusion,headSha,url`
     and read that run's log for the same error. Proven → **BLOCKED** with both links.
     Never call a failure pre-existing without that proof.
3. **A rejected push → BLOCKED.** Never escalate to a force push. A failing pre-push hook is
   fixed at its cause and retried (it counts toward `FIX_ATTEMPTS`).

## Step 3: Report

A few plain lines: the head that went green, each failure and what was done about it (fix
commit, rerun, or proof it's red on base), and `FIX_ATTEMPTS`. An orchestrator also needs the
final `HEAD_OID`, so print it.

**The last line of output is always exactly one of:**

```
RESULT: DONE
RESULT: NOOP (<why>)
RESULT: BLOCKED (<what you need from the user>)
```

## Principles

- **Green means green.** Fix what the branch broke, rerun flakes once, and prove any
  "pre-existing" failure on the base branch before calling it that.
- **Never buy green.** No skipped tests, no dropped jobs, no `--no-verify`, no force.
- **Watch the commit you pushed.** Head SHA and checks are read in one query, so a stale head
  is never mistaken for the new one.
- **The last line is the contract.** One `RESULT:` line, so a caller never has to guess.

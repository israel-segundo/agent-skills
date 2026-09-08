# Implementation quality gates (execute-plan)

Open sections as each phase reaches them. Authoritative repo rules live in the repository's
own docs — this file is the operator checklist.

## A — Gap analysis subagents (optional)

When the target PR is non-trivial (many files or overlapping prior PRs) and the host
supports parallel read-only subagents:

1. Build a **verbatim** file list from `git diff --name-status BASE...HEAD` (or planned
   paths if no commits yet).
2. Spawn specialists read-only in parallel — each returns gaps/stale assumptions with
   `path:line` evidence.
3. Lead merges deduped gaps into the Phase 4 brief.

Skip for single-file doc tweaks or when subagents are unavailable.

```sh
# Resolve default branch
DEFAULT="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
: "${DEFAULT:=main}"
git merge-base "origin/$DEFAULT" HEAD
```

## B — Mid-PR sanity check (opt-in)

Run only when intuition fires — not on a schedule:

- Task N's pattern may not match task 1
- A later task structurally depends on an earlier one (UI consumes API you just wrote)
- You changed a public contract and have not checked surviving callers or tests
- You touched API/error paths without checking logging

**Output (3–8 bullets):** trigger, files touched, findings (S0–S3), actions taken.

**S0/S1 → stop** until fixed. Most PRs skip this and go straight to Section C.

## C — Pre-merge self-check (mandatory)

Run after full verification is green.

### C1 — Diff and blast radius

```sh
git diff --name-status BASE...HEAD
```

Walk changed paths against repo security/architecture docs. Fix S0/S1 issues before handoff.

### C2 — Plan alignment

Re-read the target PR's tasks vs the actual diff. Every planned task is done or explicitly
deferred with human consent.

### C3 — Repo verification

Run the repo's full verification command (from the plan or `CONTRIBUTING.md`). Record command
and exit status.

### C4 — Behavioral check (executed)

Perform the check from the plan's **Behavioral check (planned)** line yourself. Do not defer
to the human without trying.

Record under the PR's Verification section:

```markdown
**Behavioral check (executed):** <what you ran> → <what happened>
```

Or `deferred — <reason>` / `N/A — no runtime behavior` with human acceptance.

### C5 — Pre-merge self-check block

Emit a short block in the session log:

- Commands run + exit codes
- Behavioral check result
- Open S2 items (must be zero or explicitly accepted)
- Plan contract artifacts honored (yes/no per artifact)

## D — Verification commands

Discover from the plan, `CONTRIBUTING.md`, `package.json`, `Makefile`, or CI config.
Examples (use what the repo actually documents):

```sh
make test && make lint
cargo test && cargo clippy
pytest && ruff check .
go test ./...
```

Run scoped checks during tasks; full verify at Phase 6.

**Escalation:** after 3 consecutive failures on the same task or 2 full-verify failures —
stop, summarize, ask whether to continue, revise the plan, or accept current state.

## E — Critique → revise (default before PR)

Run an adversarial review on `BASE...HEAD` before handoff. Pick the mode that fits:

| Mode | Skill | When |
|------|-------|------|
| **Interactive** | **pr-code-review** | Human in the loop; challenge loop; optional GitHub post on request |
| **Unattended** | **pr-code-review-batch** | Headless pre-PR scan; writes `findings.md` + HTML report; no prompts or posts |

**Default (human present):** **pr-code-review** — bounded revise loop per steps below.

**Batch pre-pass (optional):** run **pr-code-review-batch** first when you want a
findings artifact without chat interaction (same methodology, no HITL). Fix S0/S1-equivalent
findings from `findings.md`, then run **pr-code-review** if interactive sparring is still
wanted.

For either mode:

1. Run the review on `BASE...HEAD`.
2. Fix S0/S1 findings; push back on incorrect ones (interactive only).
3. Re-review after fixes (max 2 full cycles unless human extends).
4. Record a short ledger: findings → disposition → re-verify status.

Skip only with explicit human **skip review** consent.

## F — Optional helper scripts

If the repo documents verification or review helper scripts in `CONTRIBUTING.md` or the
plan, run them when called for. Do not invent scripts the repo does not ship.

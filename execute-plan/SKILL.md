---
name: execute-plan
description: >-
  Implement one PR slice from an existing PLAN.md, with human confirmation gates or, with
  --unattended, without them (the approved plan is the go-ahead). Resolves the plan from a
  user path, PLANS_DIR, PLANS_ROOT or .plan-store (plans may live outside the repo). Runs
  load → branch + worktree → gap analysis → confirm → implement (TDD) → verify → self-check
  → optional review → handoff; unattended runs hand off straight to pr-launch. Use when the
  user asks to execute, run, continue, or implement an existing plan. Not for authoring plans
  (create-plan), read-only reviews (pr-code-review), or opening PRs (create-pr).
license: Unlicense
metadata:
  version: "1.4.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git, gh, rg) rather than
    host-specific tools, and degrades gracefully when a capability is absent. Plan directory
    is configurable via .plan-store or PLANS_DIR and may live outside the repository.
when_to_use: >-
  Use when a PLAN.md already exists and the user wants implementation one PR at a time, with
  explicit confirmation before coding or unattended (--unattended) once the plan is
  approved. Not for writing plans (create-plan) or posting
  reviews. If a repo ships its own execute-plan skill, that one wins for domain specifics.
argument-hint: "[path/to/PLAN.md | TICKET-123] [prN] [--unattended] [--no-launch] [--reviewers a,b]"
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# Execute implementation plan

Disciplined **load → branch → gap analysis → confirm → implement → verify → self-check →
(review) → handoff** loop against an existing **PLAN.md**.

Branch + worktree setup: [references/worktree.md](references/worktree.md)

Quality gate detail: [references/quality-gates.md](references/quality-gates.md)  
Implementation rules: [references/implementation-rules.md](references/implementation-rules.md)  
Plan store resolution: [references/plan-store.md](references/plan-store.md)  
PR map conventions: [references/pr-map.md](references/pr-map.md)  
Multi-repo execution: [references/multi-repo.md](references/multi-repo.md)

## Primary outcome

Ship PR slices with fewer review surprises. Treat plan tasks and repo rules as requirements,
not post-hoc polish. Prove alignment in-session before handoff.

## When not to use

- **Authoring plans** → **create-plan**
- **Read-only diff review** → **pr-code-review** (interactive) or **pr-code-review-batch**
  (unattended; writes `findings.md` + HTML)
- **Opening PRs** → **create-pr**

## Inputs

User supplies one or more of:

- Absolute or repo-relative path to **PLAN.md**
- Ticket key — discover via [references/plan-store.md](references/plan-store.md)

If ambiguous, list candidates and ask — do not guess.

Flags:

| Flag | Effect |
|---|---|
| `--unattended` | No confirmation gates; see **Unattended mode** below |
| `--no-launch` | Unattended only: stop after the commit instead of running pr-launch |
| `--reviewers a,b` | Passed to pr-launch |
| `prN` (e.g. `pr3`) | Execute that slice instead of the first unblocked one. Its **Depends on** rows must be `MERGED`, else stop (unattended: BLOCKED) |

## Unattended mode

The user approving the plan is the go-ahead for every slice in it. Invoking with
`--unattended` authorizes, for this slice only: creating the branch and worktree, moving the
ticket to in progress, implementing and committing, editing the plan, and handing off to
**pr-launch** (whose own authorization then covers push, PR, Slack and ticket comment).

- Every place below that says **ask** or **wait** becomes: decide from the plan, the ticket
  and the repo's docs; if that can't settle it, **stop** with `RESULT: BLOCKED (<the
  question>)`. Never guess scope.
- Every run ends with exactly one `RESULT: DONE | NOOP (<why>) | BLOCKED (<need>)` line
  (after pr-launch's own, when it ran). No slice left to ship → `RESULT: NOOP (plan complete)`.
- It never files tickets, never pushes before pr-launch, and never works on the default
  branch.

## Mandatory human gates (interactive mode)

Before implementation edits:

1. **Do not assume.** Ask when scope, dependencies, or ACs are unclear.
2. **Do not start coding** until the human confirms the **next PR** brief (intent, files,
   risks, verification commands).

After confirmation, implement only that slice unless scope widens explicitly.

## Process

### Phase 1 — Load and align

1. Resolve and read **PLAN.md** in full (plus linked diagrams).
2. Read the **PR map** first — it is the authoritative rollout summary. Cross-check against
   each `### PR N:` block; if they disagree, ask which is correct before proceeding.
3. When **## Repositories** is present, read
   [references/multi-repo.md](references/multi-repo.md). Sync each target repo's default
   branch (`fetch`, checkout default, `pull --ff-only`) before gap analysis.
4. Read the **target repo's documented rules** (`AGENTS.md`, `CONTRIBUTING.md`, `docs/`,
   etc.).
5. Parse **Status** and each `### PR N:` block. Classify PR markers:

   | Class | Markers | Pick for implementation? |
   |-------|---------|------------------------|
   | **Done** | COMPLETED, DONE, IMPLEMENTED, CODE COMPLETE, MERGED | No |
   | **Awaiting review** | IN REVIEW, READY TO PUSH, READY FOR REVIEW | No — code complete; do not re-implement unless the human names that PR |
   | **Still to ship** | PENDING, IN PROGRESS | Yes |
   | **Not shipping** | DEFERRED | No |

   Map these to the PR map **Status** column per [references/pr-map.md](references/pr-map.md).
   Unrecognized markers → ask which slice to execute.

6. **Reconcile with GitHub.** For each row marked `IN REVIEW` or `COMPLETED` that has a PR
   link, read its real state (`gh pr view <url> --json state -q .state`). `MERGED` → set the
   row to `MERGED` (a plan outside the repo: edit in place; inside the repo: the change rides
   in this slice's commit). `CLOSED` → leave it and mention it. This catches PRs merged by
   hand, so their dependents become pickable.
7. Flag stale plan references (missing files/APIs) for gap analysis.
8. Pick the **first PR still to ship** (lowest N with status **PENDING** or **IN PROGRESS**
   whose **Depends on** PRs are **MERGED** in the map), unless the human named a specific PR
   (a `prN` argument, or "PR N" in the request).

### Phase 2 — Branch and worktree setup

Identify the **target repo** for this PR from the PR map **Repo(s)** column and the PR
heading's **Repo:** line: its path from **## Repositories** (or the planning repo when
single-repo). **Multi-repo:** branch operations run in the target repo, not necessarily
where `PLAN.md` lives.

Follow [references/worktree.md](references/worktree.md): branch name by the repo's
convention, a dedicated worktree from the latest default branch, reuse only when clean.
Interactive mode shows the name and path and **asks** before creating; unattended creates.
Already on a feature branch for this slice (a human or a workspace tool such as herdr set it
up) → confirm and continue there (unattended: continue if it's clean, carries the ticket key,
and either names this slice's `pr<N>` or names no slice at all; a branch naming a different
slice → BLOCKED).

Then move the ticket: **jira-transition** `--to in_progress --if-category new` (interactive:
offer it; unattended: authorized). A NOOP or a missing Jira transport is fine.

Then take the worktree's lock ([references/worktree.md § 5](references/worktree.md)). Another
run already holds it → stop (`RESULT: NOOP (another execute-plan run is active …)`), so two
agents never edit the same worktree. Release it on every exit.

Never implement on the default branch.

### Phase 3 — Gap analysis (no code)

For the target PR:

1. Search/read reference files from the plan vs current codebase **in the target repo**
   (and sibling repos when the PR touches cross-repo contracts).
2. List gaps: missing files, outdated assumptions, blocked dependencies, trust-boundary issues.
3. Blockers → stop; resolve with human or return to **create-plan**.

Optional parallel subagents: [references/quality-gates.md § A](references/quality-gates.md).

### Phase 4 — Next-PR proposal (no code)

Brief for the target PR only:

- Scope recap (1–3 sentences)
- **Target repo** path and slug
- Files to create/modify (paths tied to tasks)
- Work order (test-first per task)
- Verification commands (from plan + **that repo's** docs)
- Behavioral check for this PR (from plan's **Behavioral check (planned)** line)
- **PR map context** — depends on / parallel with sibling PRs
- Gap analysis summary
- Open questions

End with one confirmation question (e.g. "Reply **go** to implement PR N"). **Wait.**

**Unattended:** write the brief to the plan's notes for this PR (dated) and go straight to
Phase 5. Any open question the plan can't answer → BLOCKED with that question.

### Phase 5 — Execute tasks

After confirmation:

1. Track tasks (host todo list or written checklist); one in progress at a time.
2. Per task — see [references/implementation-rules.md](references/implementation-rules.md):
   - Honor plan contract artifacts first
   - Test-first when behavior changes
   - Implement minimal code; scoped verify; fix lints you introduced
   - Mark complete only after fresh verification output
3. Update **PLAN.md** factually: pre-check results, deviations (ask before silent rewrites;
   unattended: record each deviation with its reason under the PR's notes, and stop with
   BLOCKED if it widens scope beyond this slice). Set this slice's PR-map row to
   `IN PROGRESS`. Final PR status updates happen in Phase 9.

Lean diffs: delete superseded code in the same commit when replacing behavior.

Mid-PR sanity check: [references/quality-gates.md § B](references/quality-gates.md) — opt-in.

### Phase 6 — Verification

1. Run **full** agreed verification commands.
2. Record commands and exit status.
3. State verification passed only after tool output confirms green.
4. Run integration/E2E smoke when the plan or repo docs require it and tooling exists.
5. Perform the **behavioral check** yourself — [references/quality-gates.md § C4](references/quality-gates.md).

Escalation limits: [references/quality-gates.md § D](references/quality-gates.md).

### Phase 7 — Pre-merge quality gates

Run [references/quality-gates.md § C](references/quality-gates.md) in full. Fix S0/S1
equivalents before handoff.

### Phase 8 — Critique → revise (default)

[references/quality-gates.md § E](references/quality-gates.md) — run **pr-code-review**
(interactive) or **pr-code-review-batch** (unattended findings artifact) before **create-pr**.
Bounded revise loop; ledger for handoff.

Skip only with explicit human consent. **Unattended with launch:** skipped, because
pr-launch runs **pr-review-fix** to a clean round on the exact head it publishes.
`--no-launch`: run it as usual (batch review, bounded revise loop).

### Phase 9 — Handoff

**Plan-sync checkpoint** before offering options:

1. Update **PLAN.md**:
   - **PR map** row for this PR (Status → `IN REVIEW`, `COMPLETED`, or `MERGED` as appropriate;
     add PR link when opened)
   - Status section (`Overall`, `Last updated`)
   - PR heading (must match the map)
   - Task checkboxes and verification lines
   - **Behavioral check (executed)** line under Verification
2. Rewrite remaining PENDING PR text if this slice discovered new facts.
3. Commit plan updates with implementation (or include in the same PR).
4. Do not open a PR with the executed slice still marked PENDING in the map or heading.

**Unattended:** commit (repo convention, message via `-F` file), then, unless `--no-launch`,
run **pr-launch** in the slice's worktree (passing `--reviewers`), still holding the lock, and
release the lock when pr-launch returns. Its `RESULT:` line is the
last line of output. With `--no-launch`, report the worktree, branch and commit and end with
`RESULT: DONE`.

**Interactive:** present options:

1. **Launch unattended** — use **pr-launch**: review and fix, sanity tests, push, ready PR,
   green CI, review request and ticket update in one run, stopping only on a blocker.
2. **Open a PR** — use **create-pr** after Phases 7–8 and plan-sync.
3. **Continue to next PR** — loop to Phase 1.
4. **Keep branch as-is** — human handles PR/merge.

## Branch and safety

- Conventional commits per repo rules.
- Stop on failing tests, unclear instructions, missing secrets — ask (unattended: BLOCKED
  after the fix attempts in quality-gates.md § D).
- Human updates plan or scope → return to Phases 1–4 for affected PRs.

## Context management

Between PRs, start a fresh session when possible carrying only plan path, branch, and
completed-PR summary. Prefer scoped reads within a PR.

## Related skills

| Skill | Role |
|-------|------|
| **create-plan** | Authors PLAN.md and PR breakdown |
| **pr-code-review** | Interactive adversarial review before PR (Phase 8) |
| **pr-code-review-batch** | Unattended review; `findings.md` + HTML when no HITL |
| **create-pr** | Opens structured GitHub PR from current branch |
| **pr-launch** | Unattended handoff: review, sanity tests, push, ready PR, green CI, review request, ticket update |
| **jira-transition** | Moves the ticket to in progress at Phase 2 |
| **pr-queue-for-merge** | After approval: merge queue (re-queues flakes), plan row MERGED, ticket Done, cleanup, next slice |

## Skill layout

```
execute-plan/
├── SKILL.md
└── references/
    ├── plan-store.md
    ├── worktree.md
    ├── pr-map.md
    ├── multi-repo.md
    ├── implementation-rules.md
    └── quality-gates.md
```

---
name: execute-plan
description: >-
  Implement one PR slice from an existing PLAN.md with human confirmation gates. Resolves
  the plan from a user path, PLANS_DIR, or .plan-store (supports external plan directories
  outside the repo). Runs load → branch → gap analysis → confirm → implement (TDD) → verify
  → pre-merge self-check → optional code review → handoff. Use when the user asks to
  execute, run, continue, or implement an existing plan. Not for authoring plans
  (create-plan), read-only reviews (pr-code-review), or opening PRs (create-pr).
license: Unlicense
metadata:
  version: "1.1.1"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git, gh, rg) rather than
    host-specific tools, and degrades gracefully when a capability is absent. Plan directory
    is configurable via .plan-store or PLANS_DIR and may live outside the repository.
when_to_use: >-
  Use when a PLAN.md already exists and the user wants implementation one PR at a time with
  explicit confirmation before coding. Not for writing plans (create-plan) or posting
  reviews. If a repo ships its own execute-plan skill, that one wins for domain specifics.
argument-hint: "[path/to/PLAN.md | TICKET-123]"
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

## Mandatory human gates

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

   | Class | Markers |
   |-------|---------|
   | **Done** | COMPLETED, DONE, IMPLEMENTED, CODE COMPLETE, MERGED |
   | **Still to ship** | PENDING, IN PROGRESS, IN REVIEW, READY TO PUSH, READY FOR REVIEW |
   | **Not shipping** | DEFERRED |

   Map these to the PR map **Status** column per [references/pr-map.md](references/pr-map.md).
   Unrecognized markers → ask which slice to execute.

6. Flag stale plan references (missing files/APIs) for gap analysis.
7. Pick the **first PR still to ship** (lowest N with *still to ship* whose **Depends on**
   PRs are **MERGED** in the map), unless the human named a specific PR. If dependencies
   are unmet, say so and ask whether to stack on open branches or wait.

### Phase 2 — Branch setup

Identify the **target repo** for this PR from the PR map **Repo(s)** column and the PR
heading's **Repo:** line. `cd` to that repo's path from **## Repositories** (or the
planning repo when single-repo).

```sh
git -C "$TARGET_REPO" branch --show-current
```

1. Not on `main`/`master` — confirm branch or ask to create one per repo conventions.
2. On default branch — propose a feature branch; **ask** before creating.
3. Existing branch for this plan/PR — confirm continue on it.
4. **Multi-repo:** branch operations run in the target repo, not necessarily where
   `PLAN.md` lives.

Never implement on `main`/`master` without explicit consent.

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

### Phase 5 — Execute tasks

After confirmation:

1. Track tasks (host todo list or written checklist); one in progress at a time.
2. Per task — see [references/implementation-rules.md](references/implementation-rules.md):
   - Honor plan contract artifacts first
   - Test-first when behavior changes
   - Implement minimal code; scoped verify; fix lints you introduced
   - Mark complete only after fresh verification output
3. Update **PLAN.md** factually: pre-check results, deviations (ask before silent rewrites).
   Final PR status updates happen in Phase 9.

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

Skip only with explicit human consent.

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

Present options:

1. **Open a PR** — use **create-pr** after Phases 7–8 and plan-sync.
2. **Continue to next PR** — loop to Phase 1.
3. **Keep branch as-is** — human handles PR/merge.

## Branch and safety

- Conventional commits per repo rules.
- Stop on failing tests, unclear instructions, missing secrets — ask.
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

## Skill layout

```
execute-plan/
├── SKILL.md
└── references/
    ├── plan-store.md
    ├── pr-map.md
    ├── multi-repo.md
    ├── implementation-rules.md
    └── quality-gates.md
```

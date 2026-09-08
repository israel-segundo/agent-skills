---
name: create-plan
description: >-
  Author a structured PLAN.md for a new feature, issue, or work breakdown. Resolves the plan
  store directory from user input, PLANS_DIR, or .plan-store (supports external directories
  outside the repo). Gathers issue context, explores the codebase, breaks work into
  independently mergeable PRs with verification steps, and writes the plan using the bundled
  template. Use when the user wants to plan a feature, prepare a ticket for implementation,
  create or update a PLAN.md, break work into PRs, or map acceptance criteria to tasks
  before coding. Not for implementing an existing plan — use execute-plan.
license: Unlicense
metadata:
  version: "1.1.1"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git, gh, rg) rather than
    host-specific tools, and degrades gracefully when a capability is absent. Plan directory
    is configurable via .plan-store or PLANS_DIR and may live outside the repository.
when_to_use: >-
  Use when planning work before coding: new features, issue/ticket breakdown, PR sequencing,
  or refreshing an existing PLAN.md. Not for executing a plan (execute-plan) or opening PRs
  (create-pr). If a repo ships its own create-plan skill, that one wins for domain specifics.
argument-hint: "[TICKET-123 | feature description]"
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# Create implementation plan

Generate a structured **PLAN.md** for a feature or issue. Plans live in a configurable
**plan store** (often outside the repo). See [references/plan-store.md](references/plan-store.md)
for resolution rules.

**Related:** **execute-plan** implements plans; **create-pr** opens PRs after implementation.
**pr-code-review** (interactive) and **pr-code-review-batch** (unattended, writes
`findings.md` + HTML) pressure-test changes before merge.

## Planning discipline

Read [references/planning-discipline.md](references/planning-discipline.md) before writing.
Repo-specific rules in `AGENTS.md`, `CONTRIBUTING.md`, `docs/`, and any project standards
files the repo maintains override generic guidance here.

## Input

The user provides one or more of:

- An issue/ticket ID (e.g. `PROJ-123`, `ABC-456`)
- A feature description in plain text
- A path to an existing plan to update

If no ticket ID is provided, use `TICKET-XXX` as a placeholder and note it in **To Be
Clarified**.

## Step 0 — Resolve plan store

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"
```

Follow [references/plan-store.md](references/plan-store.md). If no config exists:

1. Ask the user where plans should live (absolute or repo-relative path).
2. `mkdir -p` that directory.
3. Write `$REPO_ROOT/.plan-store` with `plans_dir=<path>`.
4. Ask whether to add `.plan-store` to `.gitignore` when the path is machine-specific.

Record the resolved `plans_dir` in the plan's **Status** section.

## Step 1 — Gather issue context

**Prefer live issue fetch over asking for pastes.** Only request clarifications after
available tools are exhausted.

| Input | Action |
|-------|--------|
| **Ticket ID** | Probe issue sources (see below). On failure, note under **To Be Clarified** and ask for a paste. |
| **User pasted** full description | Proceed if complete and recent. |
| **No ticket ID** | Use `TICKET-XXX`; no fetch. |

**Issue source probe** (try in order; stop at first success):

```sh
command -v gh && gh issue view PROJ-123 --json title,body,labels,comments 2>/dev/null
# Jira / Linear / other: use whatever MCP or CLI the host exposes — read tool schemas first
```

Extract: acceptance criteria, constraints from comments, dependencies, links to design docs,
attachments mentioned (ask user to share if not fetchable).

## Step 2 — Read template and repo docs

1. Read [template.md](template.md) for canonical structure.
2. Read [references/pr-map.md](references/pr-map.md) for the at-a-glance PR map table.
3. Read [references/pr-shape.md](references/pr-shape.md) for PR ordering and cleanup shapes.
4. Read [references/multi-repo.md](references/multi-repo.md) when the ticket may span multiple
   repositories.
5. Skim repo docs relevant to the feature: `CONTRIBUTING.md`, architecture docs, decision
   records, testing guides, and any project standards or agent-rules files the repo maintains.

Discover each involved repo's **verification command** from that repo's `CONTRIBUTING.md`,
`package.json`, `Makefile`, or CI config. Use the correct command in each PR's Verification
section.

## Step 3 — Explore the codebase

Search and read the areas the feature will touch in **every repository** the plan will
modify. Record pattern files as **Reference files discovered** in the plan (prefix paths with
the repo slug when multi-repo).

### Multi-repository exploration

When the ticket spans sibling repos, follow [references/multi-repo.md](references/multi-repo.md):

1. **Discover checkouts** — scan common local paths or ask the human for coordinates; record
   confirmed paths in **## Repositories**.
2. **Sync before reading** — in each repo: `git fetch`, checkout default branch, `git pull
   --ff-only`. Explore **main** (or the repo's default), not a stale feature branch.
3. **Cross-repo contracts** — note which repo owns shared types, APIs, or infra; reflect
   merge order in the PR map **Depends on** column.

**Pre-check fact-checkable items now** — existence of helpers, enum readers, test coverage,
fixture flags. Bake findings into tasks with dated notes (see planning-discipline.md).

When the host supports parallel exploration subagents, use them for large features; prefer
scoped reads over full-file reads.

## Step 4 — Design the approach

Document key decisions in **Architecture Notes**:

- Data model changes (new entities vs extending existing)
- API / service boundaries and auth/trust model
- Event-driven or async flows if applicable
- **Architecture decision record:** `Required` or `Not required` with one-line rationale (see
  pr-shape.md cleanup variants)

Read existing architecture/decision docs before proposing new patterns.

## Step 5 — Break into PRs

Follow [references/pr-shape.md](references/pr-shape.md):

- Standard ordering: data → backend → frontend → integration → cleanup
- Each PR independently mergeable with **one** behavioral check (command or manual step)
- Cleanup PR always last when architecture-record migration or plan deletion applies
- Lean diffs: include tasks to delete superseded code/docs
- **Multi-repo:** split by repo when review/merge independence allows; use **Depends on** for
  contract repos that must land first; use **Parallel** when sibling PRs target different
  repos and share no blocking dependency (see [references/pr-map.md](references/pr-map.md))

Draft the **PR map** table (one row per PR) before writing task detail — it forces sane
ordering and surfaces parallel vs stacked work early.

## Step 6 — Write the plan

**Check for existing plan** under `plans_dir`:

```sh
# Example search — adapt KEY (e.g. PROJ-123)
find "$PLANS_DIR" -maxdepth 2 \( -name 'PLAN.md' -o -name '*plan*.md' \) 2>/dev/null | rg 'PROJ-123'
```

If found, ask the user: **Replace**, **Update**, or **Create new** (different suffix).

Create `{plans_dir}/{TICKET-XXX-short-description}/PLAN.md` from the template.

**Required sections:** Status, **PR map** (see [references/pr-map.md](references/pr-map.md)),
Context, Implementation Plan (PRs + tasks), Architecture Notes, How to Update This Plan.

**Required when multi-repo:** **Repositories** registry (see
[references/multi-repo.md](references/multi-repo.md)). Each `### PR N:` block names its
target repo; paths match the registry.

**Recommended:** Acceptance criteria traceability table when the issue lists ACs.

**Optional:** To Be Clarified, Risks & Mitigations, Rollout, Mermaid diagrams (required when
the architecture decision record is Required).

**Mermaid:** when a durable architecture record is warranted, add diagrams under the plan
directory; migrate into the repo's architecture docs at cleanup.

## Step 7 — Self-check

Walk each PR briefly:

1. **PR map** — one row per PR; Status/Scope/Repo(s)/Depends on/Parallel consistent with
   Implementation Plan headings and [references/pr-map.md](references/pr-map.md).
2. **Behavioral check** — can you name one command or manual step that proves this PR works?
   If not, split the PR.
3. **Verification** — commands match what each **target repo** actually runs.
4. **Multi-repo** — every repo in the map exists in **Repositories**; exploration used
   up-to-date default branches.
5. **Plan contract** — no `*[pre-check result]*` left empty; no "add test if missing" hedges;
   risk mitigations map to tasks.
6. **Proportionality** — plan size matches ticket scope.
7. **Cleanup** — matches the architecture decision record assessment; plan deletion is last.
8. **Stale references** — no files/APIs you could not verify.

Fix gaps before finishing.

## Output

After creating the plan:

1. Report the full path to `PLAN.md` and the plan store directory
2. Summarize the **PR map** (or repeat the table: PR #, status, scope, repo(s), depends on)
3. Call out open questions in **To Be Clarified**
4. If `TICKET-XXX` placeholders remain, remind the user to update them
5. Remind implementers to run the repo's verification command before merge

## Context management

Large features fill the context window during exploration. Use scoped reads, subagents when
available, and complete one section before expanding scope. If the session degrades, save
partial progress to the plan file and continue in a fresh session.

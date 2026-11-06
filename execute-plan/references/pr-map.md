# PR map — at-a-glance rollout table

> Keep in sync with `create-plan/references/pr-map.md` (canonical).

The **PR map** is the human-facing summary at the top of every plan. A reader should
understand rollout status, which repos are touched, and what can run in parallel — without
scrolling into task lists.

## Placement

Put **## PR map** immediately after **## Status** and before **## Context**.

## Table columns

| Column | Required | Purpose |
|--------|----------|---------|
| **PR** | Yes | `1`, `2`, … or `1a` when two PRs are intentionally parallel |
| **Status** | Yes | Current lifecycle state (see below) |
| **Scope** | Yes | One line — what this PR delivers |
| **Repo(s)** | Yes | Target repo slug or path (see multi-repo.md) |
| **Depends on** | Yes | PR numbers that must be **merged** first, or `—` |
| **Parallel** | Yes | PR numbers that *may* run concurrently once dependencies are met, or `—` |

Optional columns when useful: **Branch**, **PR link** (GitHub URL after opened).

## Status values

Use the **most advanced** state that applies. Prefer these exact tokens:

| Status | Meaning |
|--------|---------|
| `PENDING` | Not started |
| `IN PROGRESS` | Implementation underway on a branch |
| `IN REVIEW` | PR open and awaiting review |
| `COMPLETED` | Code complete on branch; PR not yet merged (or no PR yet) |
| `MERGED` | Landed on the target repo's default branch |
| `DEFERRED` | Out of scope for now |

Compound display is allowed when helpful: `COMPLETED / IN REVIEW` means done locally and
in review. **execute-plan** and **create-plan** must keep this table in sync with each
`### PR N:` heading — the map is the summary; the PR section is the detail.

## Dependency vs parallel

- **Depends on** = hard ordering. PR 3 with `Depends on: 1, 2` must not start until PR 1
  and PR 2 are **MERGED** (or the human explicitly accepts stacking on unmerged branches).
- **Parallel** = safe to implement concurrently once dependencies are satisfied. Example:
  PR 4 touches `repo-a` and PR 5 touches `repo-b` with the same dependency on PR 2 →
  `Parallel: 4 ↔ 5` or list the sibling PR number.
- When PRs **stack** (PR 2 branch based on PR 1 branch), say so in **Scope** or
  **Architecture Notes** — the map's **Depends on** still reflects merge order.

## Single-repo plans

**Repo(s)** column repeats the primary repo slug (e.g. `this repo` or `acme-api`) on every
row. **Depends on** / **Parallel** work the same.

## Maintenance rules

1. **create-plan** fills one row per PR when the plan is authored; all start `PENDING`.
2. **execute-plan** updates the row when a PR moves state (start → review → merged).
3. On every plan edit, **Last updated** in Status and the PR map must agree with PR headings.
4. Adding or removing a PR requires updating both the map and **Implementation Plan**.

## Example

| PR | Status | Scope | Repo(s) | Depends on | Parallel |
|----|--------|-------|---------|------------|----------|
| 1 | MERGED | Shared event schema | `acme/contracts` | — | — |
| 2 | MERGED | Publish events from API | `acme/api` | 1 | — |
| 3 | IN REVIEW | Subscribe in worker | `acme/worker` | 2 | — |
| 4 | PENDING | Dashboard UI | `acme/web` | 2 | 3 (after 2 merges) |
| 5 | PENDING | Cleanup + arch. record | `acme/api`, `acme/web` | 3, 4 | — |

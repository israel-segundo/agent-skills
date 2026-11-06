# Status and action rules

Classification is computed by `scripts/fetch.sh`. This file is the human-readable
spec; if the script and this doc disagree, **fix the script** to match this doc.

## Status (exactly one per PR)

Evaluated top-down; first match wins:

| Priority | Status | Condition |
|---:|---|---|
| 1 | **Draft** | `isDraft` |
| 2 | **Conflicted** | `mergeable == CONFLICTING` |
| 3 | **Changes requested** | `reviewDecision == CHANGES_REQUESTED` |
| 4 | **Feedback received** | Non-author `COMMENTED` / `CHANGES_REQUESTED` review or issue comment **after** the latest commit, and not already `APPROVED` |
| 5 | **Approved** | `reviewDecision == APPROVED` |
| 6 | **Awaiting review** | Everything else (typically `REVIEW_REQUIRED` / no decision yet) |

There is no separate **Rejected** status for *open* PRs. GitHub's equivalent of
rejection-while-open is **Changes requested**. Closed-unmerged PRs are out of scope
(this skill only lists open PRs).

## Action needed

Derived from status plus CI / age:

| Status | Extra signal | Action |
|---|---|---|
| Draft | — | Finish and mark ready for review |
| Conflicted | — | Rebase / resolve conflicts |
| Changes requested | — | Address review feedback |
| Feedback received | — | Address review comments |
| Approved | CI `FAILURE` / `ERROR` | Fix failing CI |
| Approved | CI `PENDING` / `EXPECTED` | Wait for CI, then merge |
| Approved | `mergeable == MERGEABLE` | Ready to merge |
| Approved | otherwise | Approved — check merge blockers |
| Awaiting review | CI failing | Fix failing CI (reviewers may wait) |
| Awaiting review | age ≥ 3 days | Waiting on reviewers — consider nudging (Nd old) |
| Awaiting review | otherwise | Waiting on reviewers |

When a PR has open dependencies, the summary still shows the computed action, and the
**Depends on** column explains why merge may need to wait. Prefer acting on dependency
roots first — that is why the table is ordered that way.

## Dependencies

Two sources, merged and de-duplicated:

1. **Stack** — `base` branch ≠ repo default, and another of *your* open PRs in the same
   repo has `head == this.base`. Kind: `stack`. If the base branch has no matching open
   PR, kind is `stack-branch` (listed but does not block sort).
2. **Mention** — PR body or title references another of your open PRs via
   `owner/repo#N` or `https://github.com/owner/repo/pull/N`. Kind: `mentioned`.

## Sort order

Kahn topological order over the open-PR dependency graph (only edges whose target is
also in the open set). Among ready nodes: **oldest `createdAt` first**. Cycles fall
back to oldest-first for the remaining set.

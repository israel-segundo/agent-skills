# PR shape — breaking work into mergeable slices

## PR map (summary table)

Before writing task detail, fill the **PR map** at the top of the plan. See
[pr-map.md](pr-map.md) for column definitions, status tokens, and dependency vs parallel
semantics. The map is the human-readable rollout view; **Implementation Plan** sections
hold the detail.

## Standard ordering

Typical sequence (adapt to the stack):

| Order | Layer | Delivers |
|-------|-------|----------|
| 1 | Data / schema / models | Types, migrations, shared constants |
| 2 | Backend / API / services | API endpoints, server logic, authorization rules |
| 3 | Frontend / CLI / UI | User-visible behavior |
| 4 | Integration / E2E | End-to-end coverage |
| 5 | Cleanup | Architecture-record migration, plan directory cleanup, dead-code removal |

Small features may combine layers **only when** a single behavioral check still covers
the whole slice. The final **Cleanup** PR stays separate when the plan includes architecture
record migration or plan-directory deletion.

## Behavioral check — one per PR

Every content PR must name **one** method to prove the slice works (command + expected
output, or `N/A — no runtime behavior` for docs-only).

If you cannot name one method covering the whole PR, split it. Line-count caps are not the
split rule.

Examples:

- Schema PR → run targeted unit tests for new types/services
- API PR → `curl` / integration test / API E2E spec for the new endpoint
- UI PR → manual walkthrough steps or UI test for the changed flow
- Docs-only → `N/A — no runtime behavior`

## Cleanup PR variants

Pick the heading that matches the plan:

| User-facing | Arch. record required | Cleanup focus |
|-------------|----------------------|---------------|
| Yes | Yes | Integration tests + arch. record + delete plan dir |
| Yes | No | Integration tests + record confirmation + delete plan dir |
| No | Yes | Arch. record migration + delete plan dir |
| No | No | Verification ritual + delete plan dir |

**Plan directory deletion** is always the last cleanup task, gated on architecture-record
work when applicable. If the directory is a permanent deliverable (spike `FINDINGS.md`),
delete only `PLAN.md` and keep the directory.

## E2E / integration placement

User-facing behavior shipped in PR N must include its integration or E2E coverage **in the
same PR** or explicitly in the immediately following PR — never deferred to cleanup without
stating why.

Stable test selectors (`data-testid`, `role`, etc.) belong in the UI PR; the E2E PR
verifies they exist, not introduces them.

## Seed / fixture data

Fold fixture changes into the PR that needs them (usually the first backend PR). A
separate seed-data PR is rarely justified.

## Multi-repo ordering

When a ticket spans repositories:

1. Land **contract / schema / shared library** PRs first (often a dedicated repo).
2. Consumer repos depend on those merges — reflect in **Depends on**.
3. PRs in **different repos** with the same satisfied dependencies may be **Parallel**.
4. Avoid one PR that edits unrelated repos unless the change is truly atomic.

See [multi-repo.md](multi-repo.md) for checkout discovery and exploration protocol.

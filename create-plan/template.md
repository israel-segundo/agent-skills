# TICKET-XXX: Title

## Status

- Overall: **NOT STARTED**
- Last updated: YYYY-MM-DD
- Issue: <URL or "none — use TICKET-XXX placeholder">
- Primary repo: `<path or name of repo where this plan was authored>`
- Plan store: `<absolute path to plan store directory>`

## PR map

<!--
  At-a-glance rollout for humans. One row per PR. Keep in sync with ### PR N: headings.
  Conventions: references/pr-map.md

  Status tokens: PENDING | IN PROGRESS | IN REVIEW | COMPLETED | MERGED | DEFERRED
  Compound allowed: COMPLETED / IN REVIEW

  Depends on = PRs that must be MERGED first (or —)
  Parallel = PRs that may run concurrently once dependencies are met (or —)
-->

| PR | Status | Scope | Repo(s) | Depends on | Parallel |
|----|--------|-------|---------|------------|----------|
| 1 | PENDING | [one-line deliverable] | `primary-repo` | — | — |
| 2 | PENDING | [one-line deliverable] | `primary-repo` | 1 | — |
| 3 | PENDING | [one-line deliverable] | `primary-repo` | 2 | — |
| N | PENDING | Cleanup + plan archive | `primary-repo` | 3 | — |

## Repositories

<!--
  Include when the ticket spans multiple repos. Omit for single-repo plans (primary repo
  in Status is enough). Conventions: references/multi-repo.md

  Explore each repo on its default branch after git fetch && pull.
-->

| Slug | Path | Remote (optional) | Default branch |
|------|------|-------------------|----------------|
| `primary-repo` | `/absolute/path/to/repo` | `github.com/org/repo` | `main` |

## Context

<!-- Business need, current state, how this fits the broader system. 1–3 paragraphs. -->

[Business context and motivation]

[Current state of the codebase relevant to this feature]

**Dependencies:**

- TICKET-YYY — short description (status)

**Out of scope:**

- Item 1

**Acceptance criteria traceability** (recommended when the issue lists ACs):

| AC (short) | PR(s) | Notes |
|------------|-------|-------|
| AC1 … | PR 1 | |
| AC2 … | PR 2 | |

## Implementation Plan

<!--
  Break work into independently mergeable PRs. Each PR needs one behavioral check.
  See references/pr-shape.md for ordering and cleanup variants.
  PR map (above) must stay in sync with these headings.

  Conventions:
  - Overall (## Status): NOT STARTED | IN PROGRESS | COMPLETED
  - PR map Status column: same vocabulary as PR heading markers
  - PR heading: PENDING | IN PROGRESS | COMPLETED | MERGED | IN REVIEW | DEFERRED
  - Task lines: PENDING | COMPLETED
  - Checkboxes: [ ] pending, [x] done
  - Reference files: `path/to/file` — description (prefix with repo slug when multi-repo)
-->

This feature is implemented across N PRs:

### PR 1: [Scope description] — **PENDING**

**Repo:** `primary-repo` — `/absolute/path` *(omit path when same as planning repo)*

[1–2 sentence summary.]

**TDD evidence** (when this PR changes behavior covered by tests):

1. **Red** — failing test output before implementation
2. **Green** — passing output after minimal implementation
3. **Refactor** — optional cleanup with tests still green

*State `N/A — <reason>` for non-behavior changes (docs, rename-only).*

Reference files discovered:

- `path/to/pattern.ts` — pattern to follow

Tasks:

- [ ] `path/to/new/file.ts` (new) — description — **PENDING**
- [ ] `path/to/existing/file.ts` — description — **PENDING**

#### Verification

1. `<repo verify command>` passes (discover from CONTRIBUTING.md / package.json / Makefile)
2. **Behavioral check (planned):** `<command or manual step>` → expected output. Use `N/A — no runtime behavior` for docs-only slices.
3. **Behavioral check (executed):** *(execute-plan fills after implementation)*

### PR 2: [Scope description] — **PENDING**

**Repo:** `primary-repo`

[Summary, tasks, verification — same structure as PR 1]

### PR N: Cleanup — **PENDING**

**Repo:** `primary-repo` *(list all repos if cleanup touches multiple)*

<!--
  Pick cleanup variant from references/pr-shape.md.
  Last task: delete plan directory (or only PLAN.md if directory is permanent).
-->

Tasks:

- [ ] Confirm prior PRs marked COMPLETED — **PENDING**
- [ ] Delete plan directory (or only `PLAN.md` if permanent deliverables remain) — **PENDING**

#### Verification

1. Behavioral check or `N/A — no runtime behavior`
2. **Behavioral check (executed):** *(execute-plan)*

## Architecture Notes

<!--
  Key technical decisions: data model, API shape, auth boundaries, event flow,
  cross-repo contracts, alternatives considered, diagram list.
-->

- **Data model:** …
- **API / service pattern:** …
- **Auth / trust boundary:** …
- **Cross-repo contracts:** which repo owns the contract; merge order if relevant
- **Architecture decision record:** `Not required — <rationale>` OR `Required — <trigger + rationale>`
- **Diagram(s):** list `.mmd` files or `None — prose sufficient`

## Risks & Mitigations

| Risk | Likelihood | Mitigation | Backed by |
|------|-----------|------------|-----------|
| … | Low/Med/High | Actionable mitigation text | PR N — task name |

Every action mitigation must map to a checkbox task. Use `N/A` when no action is needed.

## Rollout

<!-- Optional: deployment order, feature flags, backward compatibility, cross-repo merge sequence -->

## To Be Clarified

<!-- Open questions. Remove when resolved. -->

## How to Update This Plan

When working on a PR:

1. Update the **PR map** row (Status, and PR link when opened)
2. Set PR heading to match the map; update **Overall** under Status if needed
3. Fill **Reference files discovered** with actual paths (include repo slug when multi-repo)
4. Mark tasks **COMPLETED** and check boxes `[x]` as done
5. Add notes for deviations under the PR or in Architecture Notes
6. Set PR heading to **COMPLETED** or **MERGED** when appropriate; sync the map
7. Update **Last updated** date
8. Rewrite remaining PENDING PR text if this slice discovered new facts (types, auth, APIs)

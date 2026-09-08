# Plan series position — "PR X out of N"

When a PR ships one slice of a **create-plan** breakdown, the review request can say
`PR 2 out of 4` so reviewers know how much of the ticket remains.

**Standalone PRs omit the phrase** — never invent a position.

## 1 — Ticket key

Extract from the PR's **head branch** (`headRefName`), not necessarily the current checkout:

```sh
# Common patterns: PROJ-123, ABC-456 (adapt regex to your tracker)
printf '%s\n' "$headRefName" | grep -oiE '[A-Z][A-Z0-9]+-[0-9]+' | head -1
```

If no key is found, treat as standalone.

## 2 — Resolve plan store

Use the same rules as **create-plan** [plan-store.md](../../create-plan/references/plan-store.md):

1. `PLANS_DIR` environment variable
2. `.plan-store` in the repository root
3. Default: `<repo-root>/docs/plans`

Plans may live **outside the repository**.

## 3 — Find the plan file

Search `plans_dir` for the ticket key:

```sh
KEY=PROJ-123
find "$PLANS_DIR" -maxdepth 2 \( -name 'PLAN.md' -o -name '*plan*.md' \) 2>/dev/null \
  | rg "$KEY"
```

**If nothing in the checkout**, check the default branch before concluding standalone:

```sh
DEFAULT="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
git fetch -q origin "$DEFAULT"
git ls-tree -r --name-only "origin/$DEFAULT" -- "$PLANS_DIR" 2>/dev/null | rg "$KEY"
```

- Absent locally **and** on `origin/$DEFAULT` → standalone
- Absent locally but present on default branch → **ask** (often a cleanup PR deleted the
  plan from the branch); read the plan from `git show origin/$DEFAULT:<exact-path>`

Never pass globs to `git show` — list exact paths first.

## 4 — Resolve X and N

### Preferred: PR map table

If the plan has a **## PR map** section (create-plan template), parse its markdown table:

- **N** = number of data rows (each planned PR slice)
- **X** = the **PR** column value of the first row whose **Status** is still to ship

**Still to ship** (status starts with or contains): `PENDING`, `IN PROGRESS`, `IN REVIEW`,
`READY TO PUSH`, `READY FOR REVIEW`, `COMPLETED` (not yet merged).

**Done** (skip when finding X): `MERGED`, `COMPLETED` when clearly merged, `DONE`,
`IMPLEMENTED`, `CODE COMPLETE`.

**Not shipping** (count in N, skip for X): `DEFERRED`.

Compound statuses like `COMPLETED / IN REVIEW` → still to ship.

If every row is done/deferred while a PR is being announced → **ask** the human for X.

### Fallback: `### PR N:` headings

For plans without a PR map, count `^### PR ` headings for **N**. Classify the status marker
at the end of each heading (after `--` or `—`):

| Class | Markers |
|-------|---------|
| Done | `COMPLETED`, `DONE`, `IMPLEMENTED`, `CODE COMPLETE`, `MERGED` |
| Still to ship | `PENDING`, `IN PROGRESS`, `IN REVIEW`, `READY TO PUSH`, `READY FOR REVIEW` |
| Not shipping | `DEFERRED` |

**X** = number (or ordinal position) of the first *still to ship* heading.

**Ambiguous** — ask when: multiple candidate plans, more than one bold status span on a
heading, non-integer PR numbers, or unrecognized markers.

## 5 — Confirm in preview

The send confirmation (SKILL.md Step 7) must show what was resolved:

```
Plan: /path/to/PROJ-123-feature/PLAN.md → PR 2 out of 4 (first slice still to ship)
```

or:

```
No plan for PROJ-456 in checkout or on origin/main — standalone
```

Do not require the plan's `Branch:` line to match the PR head branch — match on ticket key.

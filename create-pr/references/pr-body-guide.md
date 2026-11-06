# PR body authoring guide

Section-by-section guidance for Step 9 of `create-pr`, with worked examples. Read this
before drafting the body.

The governing rule for all of it: **a reviewer should be able to read the description and
know what to look for in the diff.** Every sentence that doesn't help with that is noise.

---

## Ticket link

One line, at the very top, only when Step 5 found both a key and a host:

```markdown
**Ticket:** https://<discovered-host>/browse/PROJ-310
```

For a GitHub-issues repo, use the closing keyword instead — it wires the issue to the PR:

```markdown
Closes #123
```

Use `Refs #123` when the PR advances the issue without closing it. Found no key? Omit the
line. Do not write "no ticket" and do not ask for one.

---

## Changelog line

Only when Step 3 found the repo actually has this convention — a `Changelog:` trailer
consumed by a release job, a changesets directory, a documented style guide. Follow the
repo's format exactly; a release job that parses this line will not tolerate a variant.

Where the repo has the convention but no documented wording rules, this maps well:

| Title type | Entry |
|---|---|
| `chore`, `refactor`, `test`, `ci`, `build`, `docs`, `style`, `revert` | the repo's "no entry" form |
| `feat` | `Added - <one sentence>.` |
| `fix` | `Fixed - <one sentence>.` |
| `perf` | `Changed - <one sentence>.` if user-visible; the "no entry" form if not |

Voice: present tense, from the user's point of view, no ticket IDs, no commit scopes, ends
with a period.

- Good: `Added - Users can filter the order list by fulfillment status.`
- Bad: `Added - PROJ-310: implement OrderStatusFilter component in app/orders.`

A change that merges behind an off flag is usually "no entry" — the PR that turns the flag
on carries the entry. Follow the repo's flag/changelog rule if it has one rather than
restating this.

---

## Context & Summary

One or two sentences on what the PR introduces and why, then bullets **grouped by logical
change**. Bold the area, not the file path. Hard limit: **eight bullets**, no matter how
many files changed. If you're over, you're describing files.

The test: ask "what are the three-to-six things this PR does?" — not "what did each file
change?"

**Good:**

```markdown
Adds the routing engine with a strategy pattern and the dispatch pipeline behind it:

- **Routing engine** — strategy-based evaluator with region, priority and capacity matchers
- **Dispatch pipeline** — atomic job creation with exception tracking in one transaction
- **Types & constants** — new outcome types, priority enums, shared interfaces
- **Tests** — unit tests per strategy, plus an integration test for the full pipeline
```

**Bad — one bullet per file:**

```markdown
- **`toleranceEvaluator.ts`** — added tolerance evaluator
- **`quantityEvaluator.ts`** — added quantity evaluator
- **`priceEvaluator.ts`** — added price evaluator
- ... (30 more)
```

Where the change is a fix, say what was broken and what the user saw — the symptom is what
the reviewer will check against.

---

## Deployment & Rollout

Include only when Step 6 detected something. Signals worth including:

- a migration, backfill, or maintenance script, added or changed — someone has to run it
- a database index or schema definition whose build must finish before dependent code is safe
- authorization or security rules that need a coordinated deploy
- seed, reference, or global config data
- a new secret or environment variable that must exist before the code starts
- a feature-flag flip that has to happen on a particular side of the deploy
- a rollout step described by a plan file in the diff

Each bullet carries four things — **when it runs**, the **exact command in backticks** (so
tooling can extract it rather than parse prose), the **target environment**, and an explicit
**Expected outcome** the operator can check:

```markdown
- **Before the deploy** — run `npx tsx scripts/backfill-status.ts --execute --env production`
  on every target environment — **Expected outcome:** every existing document carries the
  new field; the script reports 0 remaining.
- **After the deploy** — enable the `order-status-filter` flag in production —
  **Expected outcome:** the filter row is visible to targeted orgs.
```

Timing vocabulary, when the repo has none of its own: *before release* (before any artifact
is cut — secrets, external provisioning), *staging*, *with the deploy* (backfills, index
builds), *after deploy* (flag flips, verification runs). When unsure, "with the deploy" is
the safe default for prep work and "after deploy" for follow-up.

**Never invent an action to fill this section.** If a repo requires the section
unconditionally, its own skill or template will say so — and will usually specify an exact
sentinel line for the empty case, which you must reproduce verbatim.

---

## Screenshots

An author placeholder, not a question:

```markdown
> **Author:** please attach screenshots or a screen recording on this PR.
```

You cannot take them; asking the user mid-run for them stalls the create. Leave the line and
mention it in the Step 11 report.

---

## Feature flag

Only for repos that have a flag mechanism at all. Advisory — it does not block the PR.

```markdown
> **Author (advisory, not a merge gate):** confirm this change's flag posture.
>
> - **Flag:** the key this ships behind, or **none** and why one isn't warranted.
> - **Rollout intent:** default state, target environments, staged rollout plan. Leave
>   percentages and targeting to the flag platform; don't invent one.
> - **Cleanup:** when this PR *removes* a flag, note that it removes the rollout mechanism
>   only — the soak window and platform archive are separate follow-up work.
```

Cross-reference the repo's flag and changelog docs by link; do not restate their rules here.

---

## System Diagrams

Only when a diagram genuinely helps. Prefer Mermaid — GitHub renders it natively, so no
image hosting is involved.

Two constraints worth remembering:

- In **sequence** diagrams, `<br/>` is not valid in participant labels or message text.
  Rewrite the label to fit on one line.
- In **flowchart** node labels, `<br/>` works (Mermaid 10+).
- Never write a literal `\n` into a label to get a line break. It renders as the two
  characters.

Skip the section entirely for a change a reader can follow from the bullets.

---

## Services & Core Functions / Utility Functions

Two tables, one line per row, and both are **selective**:

- **Services** — only new or heavily modified modules. A one-line edit to an existing
  service is not a row.
- **Utilities** — only genuinely reusable helpers. Not every private function.

```markdown
| Service / Module | Function | Description |
|---|---|---|
| `RoutingEngine` | `evaluate()` | Runs the strategy chain and returns the outcome. |
```

If neither has anything worth listing, drop the section rather than emitting an empty table.

---

## Tests

Open with the verification line — one line saying how the change was observed working,
naming the command and what was seen:

```markdown
**Verification:** ran `npm test -- routing` — 42 passing; manually routed a job in
the local UI and saw the dispatch created.
```

When it wasn't run, say so plainly — `deferred — not executed` or `N/A — no runtime
behaviour`. A vague claim here is worse than an honest gap; the reviewer will assume it was
verified.

Then the table, grouped by area rather than listing test names. Three to five rows is
usually right.

```markdown
| Area | Type | Summary |
|---|---|---|
| `RoutingEngine` | Unit | Each strategy's match, near-match and reject paths. |
| Dispatch pipeline | Integration | Full pipeline including the transaction rollback path. |
```

---

## Future Tasks

Everything deliberately not done here, so it doesn't get re-raised in every review round.
Three sources:

1. `TODO` / `FIXME` / `HACK` / `XXX` added by this diff,
2. follow-ups named by a plan or task file in the branch,
3. the Step 7 deferrals, each labelled: **won't fix here**, **accepted risk**, or
   **follow-up ticket** with its key.

```markdown
- **Follow-up ticket** — pagination for the jobs list (PROJ-412).
- **Accepted risk** — the backfill is single-threaded; ~4 min on production volume.
- **Won't fix here** — the legacy router stays until its callers migrate.
```

Nothing to list? One line: `No pending future tasks identified.`

---

## Things that break the body

- **`--body "..."`** — escapes backticks, GitHub stores the backslashes, every code fence
  and Mermaid block breaks. Always `--body-file`.
- **Escaped fences** (`` \`\`\` ``) — use real triple backticks.
- **Leaving the guidance comments in.** The `<!-- ... -->` notes in the skeleton are
  instructions for the author, not content. Strip them all.
- **Literal `\n` in a Mermaid label** — renders as two characters, not a line break.
- **A section full of "N/A"** — drop the section instead.
- **Hard-wrapping prose at a column.** Write one line per paragraph and one line per list
  item, however long it runs, and let the renderer wrap. Newlines inserted mid-sentence to
  keep source lines near 80/100 chars are a source-code habit that does not belong in a PR
  body: the reader sees a ragged, oddly-broken block, and every later `gh pr edit` has to
  re-flow the whole paragraph to change a word. The exceptions are the places where a line
  break is content — fenced code, Mermaid, table rows, and a deliberate two-space or `<br>`
  break — which stay exactly as written.

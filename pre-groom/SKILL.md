---
name: pre-groom
description: >-
  Pre-groom Jira tickets by checking completeness, cross-referencing codebases (including
  sibling repos and linked tickets when needed), proposing Fibonacci story-point estimates,
  and writing results back to Jira after engineer review at each step. Use when preparing
  tickets for grooming or refinement sessions, or when the user asks to pre-groom, estimate,
  or readiness-check Jira issues before planning.
license: Unlicense
metadata:
  version: "1.1.1"
  portability: >-
    Written to the Agent Skills open standard. Body uses portable shell (git, rg, jira/acli)
    rather than host-specific tools or OS-specific config conventions (no XDG). Prefers a
    Jira/Atlassian MCP when present in the session, then falls back to CLIs. Settings live
    only in $HOME/.pre-groom/ (or PRE_GROOM_CONFIG_DIR) — never written into repositories.
when_to_use: >-
  Use when preparing one or more Jira tickets for a grooming/refinement session: completeness
  check, codebase impact, clarifying questions, Fibonacci estimate, and a reviewed Jira
  comment. Not for implementing work (execute-plan) or opening PRs (create-pr).
argument-hint: "[TICKET-123 ...] | filter=<id>"
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# Pre-groom Jira tickets

Walk through preparing Jira tickets for grooming: completeness, codebase impact (any
relevant checkout — including sibling repos), clarifying questions, Fibonacci estimate, and
a reviewed write-back to Jira.

**Interactive throughout.** Process **one ticket at a time**. Wait for the engineer at every
step. Never post to Jira without an explicit yes for that ticket.

References: [config.md](references/config.md) · [global-registry.md](references/global-registry.md) ·
[jira-transport.md](references/jira-transport.md) · [codebase-review.md](references/codebase-review.md) ·
[estimate.md](references/estimate.md) · [comment-template.md](references/comment-template.md)

### Guardrails

- **Never post or edit Jira without explicit approval** for each ticket (including reassign).
- **Never move to the next step** without waiting for engineer input.
- **Never check priority** in the completeness check.
- **Never write config or artifacts into a repository.** Settings live only under `$CFG`
  (`$HOME/.pre-groom` or `PRE_GROOM_CONFIG_DIR`). Session drafts and diagrams live under
  `$WORK` (a temp dir), never inside a checkout.
- **Never invent repo paths or tenants.** Discover or ask; skip codebase analysis when
  unresolved and say so.
- **Exploring other repos and linked tickets is allowed** when the ticket depends on them.
- Fibonacci only: **1, 2, 3, 5, 8, 13**.
- Keep each step scannable in under a minute.

---

## Parse arguments

Read the invocation arguments and choose a mode:

| Input | Action |
|-------|--------|
| Ticket keys (e.g. `PROJ-481 PROJ-476`) | Fetch each key |
| `filter=<id>` (e.g. `filter=11169`) | Query Jira with JQL `filter = <id>` |
| No arguments | Ask for ticket keys or a filter ID |

## Step 0 — Preflight and config

```sh
command -v git
command -v rg                         # preferred search; fall back to grep
command -v jira acli                  # optional Jira CLIs (fallback when no MCP)
# Portable home-relative store — no XDG / OS-specific config roots
CFG="${PRE_GROOM_CONFIG_DIR:-$HOME/.pre-groom}"
mkdir -p "$CFG"
WORK=$(mktemp -d)                     # drafts / diagrams for this session (OS temp)
```

**Also probe for a Jira / Atlassian MCP** (preferred over any CLI when usable):

1. Inspect this host's available MCP servers / tool namespaces for names matching
   `jira`, `atlassian`, or `rovo` (case-insensitive). Read tool schemas before calling.
2. Optionally confirm a server is configured on disk (skip missing files):

```sh
rg -ni 'jira|atlassian|rovo' \
  "$HOME/.cursor/mcp.json" \
  "$HOME/.mcp.json" \
  "$HOME/.claude.json" \
  "$HOME/.codex/config.toml" \
  "$HOME/.gemini/settings.json" \
  2>/dev/null | head -20
```

A hit in config alone is not enough — the MCP must actually expose issue read/write tools
in this session. If the server appears in config but tools are missing or need auth, say so
and fall through to CLI.

1. Resolve Jira site, cloud id (if the write transport needs it), story-points field, and
   transports — see [jira-transport.md](references/jira-transport.md) and
   [config.md](references/config.md).
2. Note which model and version you are — disclosure on the Jira comment needs it.
3. **Report the transport preference** you will use this session (MCP > `jira` CLI > `acli` >
   none). Say which transports you found:
   - **Jira/Atlassian MCP available** → use it for all reads and writes; do not use the CLI
     unless the MCP cannot perform a needed operation (then say what failed and fall back).
   - **No write** → Step 5 degrades to paste-ready comment + commands; analysis continues.
   - **No read** → ask the engineer to paste ticket fields (or an export) and continue
     Steps 1–4 with verification limits stated ([jira-transport.md](references/jira-transport.md)).

## Introduce the skill

Print this **once** at the start of the session, before processing tickets:

```
── Pre-Groom ───────────────────────────────────

This skill walks you through preparing Jira tickets
for grooming. For each ticket, we'll go through:

  1. Ticket overview    — metadata, completeness, requirements summary
  2. Codebase review    — affected files, project standards, system diagram
  3. Questions          — clarifying questions and decisions needed
  4. Estimate           — Fibonacci story points with rationale
  5. Jira comment       — draft, review, and post to the ticket

Each step is interactive — I'll wait for your input before moving on.
```

## Fetch tickets

Fetch via the available transport ([jira-transport.md](references/jira-transport.md)).
If none can read, use the paste path there.

For each ticket, load at least: `summary`, `description`, `status`, `issuetype`, `assignee`,
`reporter`, `labels`, `issuelinks`, `attachment`, `parent`, `fixVersions`, and the configured
**story points** field.

Prefer markdown (or equivalent readable) description bodies.

## Prioritize tickets

Sort before processing:

1. **Assigned to the current user** (match account ID / email from the transport's "who am I")
2. **No story points set**
3. **Everything else** — preserve original Jira order

## Resolve repo context (per ticket)

Map the ticket's **project key** to one or more local checkouts using
[global-registry.md](references/global-registry.md). Session overrides and engineer answers
win over the registry.

- Primary checkout → `REPO_PATH` (may be CWD when already inside a mapped repo).
- Additional checkouts when the ticket, links, or exploration imply sibling systems →
  `EXTRA_REPO_PATHS[]`. Exploring them is expected, not exceptional.
- If no path resolves: **skip codebase analysis** for that ticket and note it in the output.
  Ask whether to **save** the mapping to `$CFG/projects.ini` or keep it **session-only**.
  **Never** create files inside those repos.

Also fetch **linked / blocked-by / blocks / relates-to** tickets when they affect scope or
estimate — summarize them briefly; do not fully pre-groom them unless the engineer asks.

---

## Process each ticket sequentially

For each ticket, run the five-step flow below. **One ticket at a time.**

### Step 1: Ticket overview & requirements summary

**Goal:** Confirm understanding and surface completeness gaps.

Present the header, then **always** a markdown metadata table — no exceptions.

```
── PROJ-XXX (Type) ─────────────────────────────
Summary text here
```

| | |
|---|---|
| **Jira** | https://\<site\>/browse/PROJ-XXX |
| **Assignee** | Name (or "⚠ Unassigned" / "⚠ Assigned to someone else: Name") |
| **Reporter** | Name |
| **Epic** | PROJ-YYY — Epic title (or "None") |
| **Fix version** | Version name — release date (or "None") |

**Assignee check:** If unassigned or assigned to someone else, ask:

> This ticket is assigned to [Name], not you. Would you like to: (1) continue pre-grooming
> it as-is, (2) reassign it to yourself first, or (3) pick a different ticket?

- **(2) Reassign** → show the intended assignee update, wait for an explicit yes, then apply
  via [jira-transport.md](references/jira-transport.md#reassign). If no write transport,
  print the exact command / UI steps and continue only after the engineer confirms they did
  it (or chooses continue-as-is).
- **(1) Continue** → proceed without changing assignee
- **(3) Different ticket** → ask for a new key

Wait for a response.

**1a. Completeness** — always a markdown table. Do **not** check priority.

| Field | Status | Notes |
|-------|--------|-------|
| Description | ✓ or ✗ | Present and substantive — not just restating the summary. Min ~2 sentences or structured sections. |
| Acceptance criteria | ✓ or ✗ | "AC", "Acceptance Criteria", "Expected", Given/When/Then, checklists, or a clear Expected section. |
| Story points | ✓ or ✗ | Configured story-points field is not empty |
| Issue links | ✓ or ✗ | Non-empty `issuelinks`, or a parent/epic is set |
| Attachments / designs | ✓ or ✗ | Attachments present or description references design links. Only for Stories and Bugs — skip for Tasks and Spikes. |

**1b. Requirements summary** — two parts:

1. A concise 3–5 sentence natural-language summary (problem, proposed solution, what it involves).
2. A structured breakdown:

```
Why:  [1 sentence — the problem or motivation in your own words]

What:
  • [deliverable 1]
  • [deliverable 2]
  • [deliverable 3]

Implicit scope (not stated but likely needed):
  • [inferred item]
  • [inferred item]
```

Ask: **"Does this match your understanding? Anything you'd like to clarify?"** Wait.

### Step 2: Codebase & standards review

**Skip entirely if no `REPO_PATH` (and no `EXTRA_REPO_PATHS`) resolved.**

Follow [codebase-review.md](references/codebase-review.md). Do **not** present findings as
definitive — hedge ("likely affected", "worth confirming").

Order of presentation:

1. Affected files **grouped by layer** (omit empty groups)
2. Project-standards / constitution flags (only principles that directly apply)
3. Optional system diagram (HTML under `$WORK/pre-groom-<KEY>.html`, then open in the browser)

Ask: **"Does this look right? Any files I missed or flagged incorrectly?"** Wait.

### Security review checkpoint (conditional)

Trigger only when Step 2 found **high-blast-radius** surfaces for this repo family — e.g.
authz/security rules, admin-privileged entrypoints that bypass normal access control, or the
ticket explicitly proposes those. Details and callout templates:
[codebase-review.md](references/codebase-review.md#security-review-checkpoint).

If none apply, skip and go to Step 3.

Ask: **"Are you comfortable with the security scope here? Should we flag this for additional
review during grooming?"** Wait.

### Step 3: Questions & decisions

**Goal:** Surface questions **and** decisions that need to be made before or during grooming.

**3a. Clarifying questions** — unknowns that affect scope or approach. Look for:

- Contradictions between the ticket description and what was found in the codebase
- Linked PRs/issues that may indicate partial completion
- Files, symbols, or APIs named in the ticket that do not exist (or were renamed/moved)
- Missing information needed to estimate accurately
- Dependencies on other tickets or external systems
- Edge cases in AC that seem underspecified
- Whether the ticket should be split

**3b. Decisions needed** — choices that must be made before implementation can start:

- Architecture (where does the change live; which module owns it)
- Scope (include backfill / migration / only new writes; in or out of this ticket)
- Tradeoffs (e.g. denormalize for reads vs keep normalized for writes)
- Sequencing (should a risky authz/schema change ship separately)

Categorize each item so ownership is clear:

- **Engineering** — implementation approach, architecture, technical tradeoffs
- **Product** — scope, behavior, user-facing changes, priority

For **product** items, draft a ready-to-send message:

```
Decision for product:
  ? [the decision or question]
  Options: [Option A] vs [Option B] (and tradeoffs if known)
  Context: [1 sentence on why this matters for scope/estimate]
  Draft message: "@product — Re PROJ-XXX: [question phrased for a non-technical audience]. This affects [scope impact]. Can you weigh in before grooming?"
```

**Always** use this structure (omit empty sections):

```
Engineering questions:
  1. [question]
  2. [question]

Engineering decisions:
  1. [decision] — Options: [A] vs [B]
  2. [decision] — Options: [A] vs [B]

Product questions:
  1. [question]
     Draft message: "@product — Re PROJ-XXX: ..."

Product decisions:
  1. [decision] — Options: [A] vs [B]
     Draft message: "@product — Re PROJ-XXX: ..."
```

Walk through items interactively. For engineering items, discuss and resolve together. For
product items, confirm the draft messages. Track resolved vs open — open items carry into
Step 5. If nothing remains after Steps 1–2, say "No outstanding questions or decisions" and
move on. Wait before proceeding.

### Step 4: Story point estimate

Propose a Fibonacci estimate using [estimate.md](references/estimate.md).

**Always** use:

```
Suggested estimate: N points

Rationale:
  • [factor from earlier steps]
  • [factor]
  • [factor]

Adjustments applied:
  • [+N for reason] or [−N for reason]
```

If splitting is warranted, propose sub-tickets (do **not** create them). Ask whether to
split or keep one ticket. If splitting, carry the proposal into Step 5's
**Follow-ups / split proposal** section.

Ask: **"Accept N points, adjust, or skip?"**

- Accept → Step 5 with N
- Different number → use it (nudge non-Fibonacci to nearest)
- Skip → next ticket without write-back

### Step 5: Jira comment draft & write-back

Compose the comment from [comment-template.md](references/comment-template.md),
incorporating engineer feedback (resolved → Decisions made; open → Open questions /
Decisions needed; agreed splits → Follow-ups / split proposal; omit empty sections).

Ask: **"Post this comment and set story points to N? (yes / edit / skip)"**

| Answer | Action |
|--------|--------|
| **yes** | Update story points, then post the comment (transport in [jira-transport.md](references/jira-transport.md)) |
| **edit** | Change what they ask, re-show, re-confirm |
| **skip** | Next ticket; nothing written |

Show the **full** comment before posting. After success (or degrade-to-paste), confirm and
move to the next ticket.

---

## Rules

- **NEVER** post to Jira without explicit engineer approval for **each** ticket
- **NEVER** check priority in the completeness check
- **NEVER** advance a step without waiting for engineer input
- **ALWAYS** show the full comment text before posting
- **ALWAYS** process tickets one at a time — do not batch approvals
- **ALWAYS** keep settings under `$CFG` (`$HOME/.pre-groom` or `PRE_GROOM_CONFIG_DIR`) — never create skill config inside repos
- If story points already exist, show them and ask before re-estimating
- If codebase search finds nothing relevant, say so rather than guessing
- Fibonacci only: 1, 2, 3, 5, 8, 13
- Keep output concise

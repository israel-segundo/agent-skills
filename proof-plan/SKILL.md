---
name: proof-plan
description: >-
  Proof an existing implementation plan (PLAN.md) against the latest code on the target
  repo's remote default branch, then fix the plan until it holds. Fetches the remote and reads
  origin/<default> without checking it out or touching the user's worktree. Runs an
  adversarial review round that verifies every path, line number, helper, identifier,
  permission, test name, command and dated pre-check the plan cites, ranks findings by
  severity with file:line evidence, then fixes every finding in the plan (Must Fix, Should
  Fix and Nits; nothing deferred, no tickets), repeating review then fix until a round comes
  back clean. Restamps the plan's date and explored commit and re-renders a sibling
  PLAN.html. Use when a plan has aged, before execute-plan starts a slice, or when asked to
  proof, re-verify, refresh or review a plan against main. Edits only the plan.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git, rg) rather than
    host-specific tools, and degrades gracefully when a capability is absent. Plans resolve
    from the same configurable plan store as create-plan and execute-plan.
when_to_use: >-
  Use on an existing PLAN.md (from create-plan or hand-written) before implementing it, or
  whenever the default branch has moved since the plan was written. Not for writing a plan
  (create-plan), implementing one (execute-plan), or reviewing code changes (pr-review-fix,
  pr-code-review). If a repo ships its own proof-plan skill, that one wins.
argument-hint: "[path/to/PLAN.md | TICKET-123] [--max-rounds N] [--ref <remote>/<branch>]"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Task
---

# Proof a plan against the latest default branch

A plan is a set of claims about code: *this file exists, this helper does X, this line holds
Y, this test will go red, this command verifies it*. Code moves after the plan is written.
This skill checks every claim against the **remote** default branch as it is right now, then
rewrites the plan until a review round finds nothing left to fix.

It is two skills' discipline applied to a document instead of a diff:

1. **A code-review round** — adversarial and evidence-first. A claim the reviewer cannot
   confirm at `$REF` is a finding, with the `path:line` that disproves it.
2. **A pr-review-fix round** — every finding is fixed in the plan. Must Fix, Should Fix and
   Nits alike. Nothing is deferred, ticketed, or handed back as "your call".

Rounds repeat until one returns **zero findings** or the cap is reached.

**Related:** `create-plan` writes plans and owns the plan format; `execute-plan` implements
them; `pr-review-fix` is the same fix-everything loop for code.

### Reference files (load at the step that needs them)

- `references/plan-store.md` — Step 0a: resolve a ticket key to a plan
- `references/plan-review-checklist.md` — Step 2a: what the reviewer verifies, and the finding format
- `references/html-render.md` — Step 4b: re-rendering a sibling `PLAN.html`

---

## Rules that always hold

- **Edit only the plan** (and its sibling `PLAN.html` and diagrams). Never edit code, tests,
  or config in any repo.
- **Never mutate the user's checkout.** No `checkout`, `switch`, `reset`, `stash`, `pull`,
  `rebase` or `merge` in it. `git fetch` is the only write, and it touches only
  remote-tracking refs. Read code with `git show`, `git grep` and `git ls-tree` at `$REF`.
- **Never commit, push, or file tickets.** Plans often live outside any repo; when one is
  tracked in a repo, leave the edit uncommitted and say so.
- **Never download packages or start services** to proof a plan. A claim that needs a running
  system to confirm is reported as *unverified*, with the reason.
- **Repo rules win.** Read the target repo's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` at
  `$REF`. A plan that breaks a documented repo rule has a finding.
- **Never use `cd`.** Absolute paths, or `git -C "$REPO"`.

---

## Step 0 — Resolve the plan and the code it describes

Print what you resolve; the run must be auditable.

### 0a — The plan

| Input | Action |
|---|---|
| Path to a plan file | Use it. |
| Ticket key or slug | Resolve via `references/plan-store.md`. Several candidates → list them and stop. |
| Nothing | Search the plan store for plans whose key matches the current branch name; one hit → use it, else stop and ask. |

Set `PLAN` (absolute path) and `PLAN_DIR`. If `$PLAN_DIR/PLAN.html` (or an `.html` with the
plan's basename) exists, set `PLAN_HTML`.

### 0b — The repositories

Read the plan's **Status** (`Primary repo`) and, when present, its **Repositories** table.
For each repo the plan modifies, resolve a local checkout (the path in the plan, else the
current repo, else ask), then:

```sh
REPO=/abs/path/to/checkout
REMOTE=$(git -C "$REPO" remote | grep -x origin || git -C "$REPO" remote | head -1)
git -C "$REPO" remote set-head "$REMOTE" -a >/dev/null 2>&1 || true
DEFAULT=$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" | sed "s|^$REMOTE/||")
[ -n "$DEFAULT" ] || DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main)
git -C "$REPO" fetch --quiet "$REMOTE" "$DEFAULT"
REF="$REMOTE/$DEFAULT"                       # or the --ref argument
REF_SHA=$(git -C "$REPO" rev-parse --short "$REF")
```

A fetch failure is a hard stop: proofing against a stale ref is the failure this skill exists
to prevent.

Read code at the ref, never from the working tree (it may be a feature branch or dirty):

```sh
git -C "$REPO" show "$REF:path/to/file" | sed -n '120,160p'   # a cited range
git -C "$REPO" grep -n 'functionName' "$REF" -- 'src/**'      # does it exist, where
git -C "$REPO" ls-tree -r --name-only "$REF" | rg 'pattern'   # does the path exist
git -C "$REPO" log --oneline "$PLANNED_SHA..$REF" -- <path>   # what moved since the plan
```

Record `PLANNED_SHA` if the plan names the commit it was explored on. The commits between it
and `$REF` that touch cited paths are the first places to look.

**Running a command** (to prove a verification command exists or a test name resolves) is
optional. Do it only in a throwaway detached worktree, and only for read-only commands such as
`--listTests` or `--help`; never a suite that needs services:

```sh
TMP=$(mktemp -d); git -C "$REPO" worktree add --detach --quiet "$TMP/wt" "$REF"
# … read-only probe …
git -C "$REPO" worktree remove --force "$TMP/wt"
```

### 0c — Snapshot

Copy the plan before the first edit so the final summary can diff it:

```sh
WORK=$(mktemp -d); cp "$PLAN" "$WORK/PLAN.before.md"
```

---

## Step 1 — Read the plan as claims

Read the whole plan once. Note the sections the checklist keys off: Status, PR map,
Repositories, Context, Acceptance criteria, each `### PR N:` block (Reference files, Tasks,
Verification), Architecture Notes, Risks & Mitigations, To Be Clarified. A plan without some
of these is not a finding by itself; a plan whose sections contradict each other is.

---

## Step 2 — The round loop

Default cap: **3 rounds** (`--max-rounds N` to change). Repeat 2a–2d until Step 3 ends the run.

### 2a — Review round (the code-review half)

Run the review in a **fresh subagent** when the host has one; from round 2 on, the main session
wrote the edits under review and is biased toward "looks fine". With no subagent capability,
review inline and say so in the summary.

Give the reviewer: `PLAN`, each repo with its `$REF` and `$REF_SHA`, the read-only git
commands above, `references/plan-review-checklist.md`, the repo rules files, and the **fix
ledger** (every finding fixed in earlier rounds, with its id and the plan edit). A fixed
finding may be raised again only if the fix did not hold.

The reviewer returns a JSON array in the checklist's finding format. **An empty array is a
valid and expected answer.** Every finding returned will be applied to the plan, so an
invented one costs a real edit; a finding without `$REF` evidence is not a finding.

### 2b — Fix round (the pr-review-fix half)

Fix **every** finding, highest severity first. One finding, one focused plan edit:

- Correct the claim to what `$REF` says: path, line range, identifier, command, test name.
- When a task's premise no longer holds (helper already exists, dead code already removed,
  bug already fixed upstream), rewrite or drop the task and leave a dated note saying why:
  `*(re-verified YYYY-MM-DD at <sha>: already removed by <commit>)*`.
- When a fix changes scope, update every place that depends on it in the same edit: PR map
  row, `### PR N:` heading, acceptance-criteria table, Risks table, Verification.
- Refresh a dated pre-check you re-verified: keep the claim, update the date and commit.
- Do not rewrite prose the reviewer did not flag. A longer plan gives the next round more to
  disagree with; that is how this loop fails to converge.

**Not a defect** is allowed only with evidence in the cell (the `$REF:path:line` that shows the
plan was right). **BLOCKED** applies when a fix needs a decision only a human holds, such as a
scope change the ticket does not settle or two valid designs the plan must choose between.
Stop the loop, report it, and on an interactive host ask one question. Do not park it in To Be
Clarified and carry on: that is deferral.

### 2c — Self-check the edit

Re-read the edited sections and confirm: PR map rows match `### PR N:` headings and statuses;
no task still cites a path or identifier the round proved wrong; every Risks mitigation still
maps to a task; markdown tables still render (same column count per row).

### 2d — Report the round (every round, including a clean one)

```
#### Round N — <k> findings   (ref: origin/main @ 1a2b3c4)

| ID | Severity | Plan location | Finding (evidence at ref) | Disposition |
|---|---|---|---|---|
| P1-01 | Must Fix | PR 1 › Tasks | `src/auth.ts:88` cited; helper moved to `src/auth/session.ts:41` | Fixed |
| P1-02 | Nit | Status | explored-commit stamp predates 14 commits touching cited paths | Fixed |
```

Disposition: `Fixed`, `Fixed, scope changed — <what>`, `Not a defect — <evidence>`, or
`Unfixed — <Step 3 condition>`.

---

## Step 3 — Termination

**DONE**: a round returns zero findings.

**BLOCKED**: any of:

- a finding needs a human decision (Step 2b);
- the same finding (same plan location and claim) survives two fix attempts;
- the round cap is reached with findings outstanding;
- the fetch failed or a repo the plan modifies has no reachable checkout.

Both outcomes run Step 4 if the plan was edited, then Step 5.

---

## Step 4 — Restamp and re-render

### 4a — Stamp

In **Status**: set `Last updated` to today, and set or add the explored-commit stamp, e.g.
`explored on origin/main at 1a2b3c4 (proofed YYYY-MM-DD)`. Multi-repo plans stamp each row
of the Repositories table. Change nothing else in Status unless a finding required it.

### 4b — HTML sibling

If `PLAN_HTML` exists, re-render it from the edited plan following
`references/html-render.md`. If no renderer is available locally, do not download one: say
the HTML is stale and give the command that would refresh it.

---

## Step 5 — Summary

```
## /proof-plan — <DONE | BLOCKED: reason>

Plan: <abs path>   (HTML: re-rendered | stale | none)
Proofed against: <repo> origin/<default> @ <sha> (was <planned sha or "unstamped">, <n> commits behind)

| Round | Findings | Must Fix | Should Fix | Nit | Fixed |
|-------|----------|----------|------------|-----|-------|
| 1     | 6        | 2        | 3          | 1   | 6     |
| 2     | 0        | 0        | 0          | 0   | 0     |

### What changed in the plan
- <section> — <one line per substantive change>   (from diff of $WORK/PLAN.before.md)

### Unverified claims
- <claim> — <why it could not be checked statically>

### Unfixed (BLOCKED only)
- <id> — <finding> — stopped because <condition>
```

Emit the last two sections only when non-empty. If round 1 was clean, say the plan holds at
`<sha>`; the only edit is the stamp. The plan is left uncommitted wherever it lives.

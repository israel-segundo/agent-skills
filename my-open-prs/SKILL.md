---
name: my-open-prs
description: >-
  List all open GitHub pull requests authored by the authenticated user, classify each
  one's review/merge status and the action needed (awaiting review, feedback received,
  changes requested, approved, draft, conflicted), detect stack and mention dependencies,
  and present a single triage table ordered oldest / no-dependencies first. Uses the gh
  CLI only. Use when the user wants a morning summary of their open PRs, to triage what
  to act on next, or asks "what are my open PRs?" / "PR status" / "PRs I opened".
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (gh, jq) rather than
    host-specific tools. Classification lives in scripts/fetch.sh so weaker models get
    the same answer as frontier ones.
when_to_use: >-
  Daily or ad-hoc triage of PRs you authored that are still open. Not for reviewing
  other people's PRs (list-prs-awaiting-review / pr-code-review), not for opening a PR
  (create-pr), and not for addressing feedback on one specific PR (pr-address-feedback).
argument-hint: "[--owner ORG]"
allowed-tools:
  - Bash
  - Read
---

# My open PRs (daily triage)

Answer **"what should I do about the PRs I opened?"** — one table, action-oriented,
oldest and unblocked first.

This skill is **read-only**. It never comments, pushes, merges, or requests reviewers.

References: [status-rules.md](references/status-rules.md)

## Argument

- **No argument** → every open PR authored by the authenticated `gh` user, across all
  orgs/repos the token can see.
- **`--owner ORG`** (optional) → after fetch, keep only PRs whose `repo` starts with
  `ORG/`. Useful when you want the morning view scoped to one org.

## Guardrails

- **Read-only.** Do not `gh pr comment`, `gh pr merge`, `gh pr edit`, or push.
- **Do not invent status.** Every row comes from `scripts/fetch.sh` JSON. If a field is
  missing, say so — do not guess review state from memory or chat history.
- **Work quietly.** No play-by-play of API calls. The first substantive reply is the
  summary (or a preflight failure).
- **One table.** Do not split by repo unless the user asks. Ordering already encodes
  priority (deps + age).

---

## Step 0 — Preflight

```sh
command -v gh
command -v jq
gh auth status
```

Any failure → **stop**. Say which of `gh` / `jq` / auth is missing and how to fix it
(`gh auth login`, install `jq`). Do not fall back to scraping the GitHub website or
calling REST by hand.

Resolve the skill root (directory that contains this `SKILL.md`) and keep artifacts
there:

```sh
SKILL_DIR="<directory containing this SKILL.md>"
WORK="${TMPDIR:-/tmp}/my-open-prs-$$"; mkdir -p "$WORK"
```

---

## Step 1 — Fetch and classify

Run the bundled script. It paginates GraphQL, classifies status/action, detects
dependencies, and sorts:

```sh
"$SKILL_DIR/scripts/fetch.sh" >"$WORK/prs.json"
```

If the script exits non-zero, print its stderr and **stop**.

Optional owner filter:

```sh
# only if the user passed --owner ORG
ORG="<org>"
jq --arg o "$ORG" '.prs |= [.[] | select(.repo | startswith($o + "/"))] | .count = (.prs | length)' \
  "$WORK/prs.json" >"$WORK/prs.filtered.json"
mv "$WORK/prs.filtered.json" "$WORK/prs.json"
```

---

## Step 2 — Render the summary

Read `$WORK/prs.json`. Emit markdown (chat-portable — no host-specific Artifact unless
the user asks for HTML).

### Empty set

If `count == 0`:

> No open PRs authored by **\<me\>**. You're clear.

Then stop.

### Header

One line:

`Open PRs by **<me>** · <count> · fetched <fetchedAt> UTC`

### Table

Columns, in this order:

| Repo | PR | Title | Age | Status | Action needed | Depends on |
|---|---|---|---|---|---|---|
| `owner/repo` | `[#N](url)` | title (untruncated unless absurdly long) | `Nd` from `ageDays` | `status` | `action` | `dependsOnSummary` |

Row order = array order in `prs` (already: no open deps first, oldest first).

### Attention callouts (after the table)

Only when relevant — skip a bullet if zero PRs match:

1. **Act now** — status in `{Conflicted, Changes requested, Feedback received}` **or**
   action starts with `Fix failing` **or** action is `Ready to merge`.
2. **Blocked on deps** — `dependsOn` non-empty **and** at least one entry has a
   `number` (an open PR you still own).
3. **Stale awaiting review** — status `Awaiting review` and `ageDays >= 3`.

Each bullet: count + a short comma-separated list of `repo#N` links.

### Footer

One line: `N open · A need action · B awaiting review · C approved`.

Counts:

- **need action** = Act now set above
- **awaiting review** = `status == "Awaiting review"`
- **approved** = `status == "Approved"`

---

## Step 3 — Stop

Do not offer to merge, nudge, or open the PRs unless the user asks. The deliverable is
the summary.

---

## Status legend (short)

Full rules: [status-rules.md](references/status-rules.md).

| Status | Meaning |
|---|---|
| Draft | Still a draft |
| Conflicted | Merge conflicts with base |
| Changes requested | Reviewer requested changes |
| Feedback received | Reviewer comments since your last push |
| Approved | Approved (action says merge / fix CI / wait) |
| Awaiting review | Open, waiting on reviewers |

---

## Failure modes

| Symptom | What to say |
|---|---|
| `gh` missing / not authed | Install GitHub CLI and run `gh auth login` |
| `jq` missing | Install `jq` |
| GraphQL errors from script | Paste the script's stderr; usually a scope or outage issue |
| Token can't see private repos | Re-auth with `repo` scope |

Never partially invent rows for repos the script did not return.

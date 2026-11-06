---
name: deslopify
description: >-
  Strips AI slop, corporate filler, passive jargon, and bloated descriptions from Jira
  tickets, Slack messages, emails, and specs — replacing them with direct, high-density,
  action-oriented summaries with extracted scope and dependencies. Use when the user asks
  to deslopify, de-slop, clean up, or clarify bloated text; when a ticket or message needs
  tightening before grooming or posting; or when scope and subtasks are buried in prose.
license: Unlicense
metadata:
  version: "1.1.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses portable shell (jira/acli) rather
    than host-specific tools. Home-relative config only ($HOME/.deslopify or
    DESLOPIFY_CONFIG_DIR) — no XDG or OS-specific config roots. Prefers a Jira/Atlassian
    MCP when present in the session, then falls back to CLIs. Settings live only in
    $HOME/.deslopify/ (or DESLOPIFY_CONFIG_DIR) — never written into repositories.
when_to_use: >-
  Use on raw ticket text, Slack threads, emails, or specs that are verbose, AI-generated,
  or hard to act on. For Jira issues, optionally replace summary and description after
  archiving the originals in a comment. Not for implementing work or posting status updates
  (jira-update-issue).
argument-hint: "[TICKET-123 | pasted text] [--jira | --slack | --auto]"
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# Deslopify

Transform bloated, AI-generated, or jargon-heavy text into direct, actionable summaries.
Extract buried scope, subtasks, and dependencies. For Jira, optionally rewrite the issue
after archiving the original.

**Interactive for writes.** Always show the deslopified output first. For Jira field edits,
wait for an explicit yes before posting the archive comment or updating summary/description.

References: [config.md](references/config.md) · [description-template.md](references/description-template.md) ·
[jira-transport.md](references/jira-transport.md) · [examples.md](references/examples.md)

### Guardrails

- **Never edit Jira without explicit approval** for that issue.
- **Never guess the Jira site** — discover or ask ([jira-transport.md](references/jira-transport.md)).
- **Never invent scope, dependencies, or deliverables** not supported by the input. You may
  rephrase or surface items **explicitly stated or clearly implied** in the source; anything
  beyond that must be tagged `(inferred)` or moved to an **Open questions** section.
- **Preserve facts** — dates, names, ticket keys, URLs, metrics, and acceptance criteria
  survive the rewrite; only the prose changes.
- **Archive before replace.** When updating a Jira issue, post the original summary and
  description as a comment *before* overwriting fields.
- **Never write config or session artifacts into a repository.** Settings live only under
  `$CFG` (`$HOME/.deslopify` or `DESLOPIFY_CONFIG_DIR`). Drafts live under `$WORK` (a temp
  dir), never inside a checkout.

---

## Parse arguments

| Input | Action |
|-------|--------|
| Issue key (e.g. `PROJ-123`) | Fetch live from Jira; use summary + description as input |
| Pasted text | Use as-is |
| `--jira` / `--slack` / `--auto` | Force output format; default `--auto` |
| Nothing | Ask for text or an issue key |

## Step 0 — Preflight

```sh
CFG="${DESLOPIFY_CONFIG_DIR:-$HOME/.deslopify}"
mkdir -p "$CFG"
WORK=$(mktemp -d)
command -v jira acli                  # optional Jira CLIs (fallback when no MCP)
```

Probe transports per [jira-transport.md](references/jira-transport.md) (MCP catalog first, then
`jira`, then `acli`). Resolve site and cloud id when a fetch or write-back is likely. **State
the chosen transport** before fetching or editing.

## Step 1 — Resolve input and format

1. **Gather text** — from paste or Jira fetch ([jira-transport.md](references/jira-transport.md)).
2. **Confirm the issue** (issue keys only) — show key, browse URL, and current summary. If
   fetch fails, the key looks wrong, or multiple issues match, stop and ask for a paste rather
   than proceeding silently.
3. **Choose format:**
   - `--jira` → Format A
   - `--slack` → Format B
   - `--auto` → Jira/spec if the input is a ticket, technical spec, or issue key; otherwise
     Format B (Slack/email/general prose)
4. Save originals to `$WORK/original.md` (summary + description for Jira; full paste otherwise).

## Step 2 — Extract core intent

Identify the primary action: what is being built, changed, communicated, or decided.

## Step 3 — Deconstruct scope

Split into candidate subtasks or sub-stories when multiple components, teams, or phases are
buried in one block. Surface hidden scope creep.

## Step 4 — Identify critical dependencies

Isolate blocking tickets, external teams, approvals, feature flags, migrations, or
preconditions.

## Step 5 — Apply the De-Slop Rules

1. **Lead with the 'So What?':** State what is actually changing, who is affected, and why
   it matters in sentence 1.
2. **De-silo Scope & Extract Sub-components:** Identify buried subtasks, hidden dependencies,
   and scope creep.
3. **Strip Fluff & Passive Jargon:** Remove phrases like "in order to ensure," "serves as a
   middle layer to synthesize," "leverage," and repeating contextual background.
4. **Standardize Layout:** Force output into short bullet points and explicit metadata blocks.

## Step 6 — Format output

Full Jira template and disclaimer rules: [description-template.md](references/description-template.md).

### Format A: Jira / Technical Spec

Also draft a **deslopified summary** (≤80 chars when possible; imperative, no filler).

Use the template in [description-template.md](references/description-template.md). For chat
preview before write-back, use the disclaimer placeholder link
`{archive comment — linked after approval}`.

### Format B: Slack / Email / General Prose

When the output **replaces or updates** a posted Slack message, lead with the disclaimer
(same wording as Jira; link to the source message permalink when available):

```markdown
> This text was **deslopified** with `/deslopify`. To consult the original text: [original text]({original_link})

**Action Required:** [Yes/No - What needs to be done]
**Core Message:** [1-2 sentence direct summary]
**Key Points:**
* [Point 1]
* [Point 2]
```

For email or general prose that is not replacing a live message, omit the disclaimer unless
the user asks to include it.

## Step 7 — Show the result

Present the formatted output. For Jira input, also show:

- **Proposed summary:** `<deslopified title>`
- **Proposed description:** the Format A body (wiki/markdown per transport)

Ask whether to apply changes to Jira (issue keys only) or stop at the summary.

## Step 8 — Jira write-back (optional, issue keys only)

Offer explicitly:

> Replace the issue summary and description with the deslopified versions? The current
> summary and description will be saved as a comment first. (yes / edit / no)

| Response | Action |
|----------|--------|
| **edit** | Revise from feedback, re-show, ask again |
| **no** | Done — output stays in chat only |
| **yes** | Archive comment → update summary → update description |

### 8a — Archive comment (required before field edits)

Write the archive body to `$WORK/archive-comment.md`. **Match markup to the transport**
([jira-transport.md](references/jira-transport.md)):

**Markdown** (host integration, `acli`):

```markdown
## Original issue text (archived before deslopify)

**Summary:** <original summary>

**Description:**

<original description, verbatim>

_Archived before deslopify (`<model + version>`) — reviewed by `<user>`._
```

**Wiki markup** (`jira` CLI — comments are not auto-converted):

```text
h3. Original issue text (archived before deslopify)

*Summary:* <original summary>

*Description:*

<original description, verbatim>

_Archived before deslopify (<model + version>) — reviewed by <user>._
```

Post via [jira-transport.md](references/jira-transport.md).

### 8b — Prepare and apply description

1. Capture the **archive comment URL** from the transport response (e.g.
   `{jira_site}/browse/{KEY}?focusedCommentId={id}`).
2. Write the Format A body to `$WORK/description.md` per
   [description-template.md](references/description-template.md), with the disclaimer at the
   top and `{original_link}` set to the archive comment URL.
3. Set **summary** to the proposed deslopified title.
4. Set **description** from `$WORK/description.md` (MCP/`acli`/host integration: markdown as-is;
   `jira` CLI: pass via stdin or `--body` — the CLI converts markdown on edit).

Confirm: issue key, browse URL, archive comment link, and what fields changed.

**No write transport:** print the archive comment, proposed summary, proposed description, and
exact CLI commands. Say clearly that nothing was posted or edited.

---

## Principles

- **So what first.** Every output opens with change, audience, and why it matters.
- **Facts in, fluff out.** Names, numbers, links, and AC stay; filler goes.
- **Extract what is there.** Surface subtasks and dependencies the source states or clearly
  implies; tag anything else `(inferred)` or park it under **Open questions**.
- **Archive before replace.** Jira edits never overwrite without saving the original in a
  comment.
- **Disclaimer on replace.** Every Jira description or Slack message that supersedes posted
  content leads with the deslopify disclaimer and a working link to the original.
- **Show, then write.** No Jira mutation without an explicit yes.
- **Match markup to transport.** Markdown through integrations; wiki markup through `jira` CLI.

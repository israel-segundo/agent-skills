---
name: jira-update-issue
description: >-
  Post a plain-language status update to the Jira issue behind the current branch, written
  for the people who read the ticket rather than the diff. Resolves the issue key from the
  branch's pull request or the branch name, discovers the Jira site from the repo's own docs
  or the local CLI config instead of assuming one, then summarizes what was done, what it
  affects, and what happens next — no jargon, three short sections. Probes for whichever
  Jira transport exists (the jira CLI, acli, a host integration) and, when none does, prints
  the finished comment plus the exact command to post it. Use when you want the ticket to
  reflect the work without writing the update yourself. Shows the comment and waits for
  confirmation before posting, and never transitions the issue or edits its description.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git/gh/jira) rather than
    host-specific tools, and degrades gracefully when a capability is absent. If your
    host has no skill support, read this file top to bottom and follow it directly.
when_to_use: >-
  Use at the end of a work session, or when a PR goes up, to leave a non-technical progress
  note on the ticket — the kind of update a product manager can read without asking a
  follow-up question. If a repo ships its own jira-update-issue skill, that one wins: it
  knows the project's site, conventions, and audience.
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# Jira update issue (plain-language status comment)

Work out which ticket this branch belongs to, read what actually happened on it, and leave
one short comment that a non-engineer can act on. One comment, one time, nothing else
touched.

**The defining stance: the audience is not you.** The ticket is read by whoever is planning
the sprint, answering the customer, or deciding whether to test it — not by someone who will
open the diff. So no "rebased onto main", no "refactored the reducer", no "fixed the lint
errors". Say what changed for a user of the product and what has to happen next.

**Plain language and short.** Your reader is a colleague, not a linter. Three sections, one
to three sentences each, everyday words. Concrete beats abstract: "users can now save a draft
and come back to it" lands where "persistence was added to the editing workflow" doesn't. If
a sentence has three qualifiers stacked up, cut two.

### Guardrails (they apply throughout)

- **Never post without explicit confirmation.** Show the finished comment and wait. Not all
  hosts prompt before running commands — assume none do.
- **Never transition the issue, reassign it, change its fields, or edit its description.**
  This skill adds one comment. That's the whole mandate.
- **Never guess the Jira site.** If discovery comes up empty, ask. Posting to the wrong
  tenant is not recoverable by you.
- **Never invent progress.** If the branch has two commits that fix a typo, the update says
  that. An honest small update is useful; an inflated one gets someone's plan wrong.
- **Disclose the assist in one sentence.** Anything posted outward says which model helped
  and that a human reviewed it. Name the model and version — never "an AI".

---

## Step 0 — Set up and probe what you can do

```sh
command -v git                        # required
command -v gh                         # optional: lets Step 2 find the PR
command -v jira acli                  # Jira transports, in order of preference
REPO=$(git rev-parse --show-toplevel) || exit
WORK=$(mktemp -d)                     # the comment draft lives here
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
```

Also note whether this host exposes a Jira or Atlassian integration of its own, and **which
model and version you are running as** — the disclosure line names it. If you don't know,
ask before posting.

Say which transports you have. A missing one changes only the last step, never whether the
comment gets written.

## Step 1 — Check the branch

Resolve the default branch rather than assuming `main`:

```sh
UPSTREAM=$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
REMOTE=${UPSTREAM%%/*}; REMOTE=${REMOTE:-$(git -C "$REPO" remote | head -1)}
git -C "$REPO" remote set-head "$REMOTE" -a >/dev/null 2>&1 || true
DEFAULT=$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s|^$REMOTE/||")
[ -n "$DEFAULT" ] || DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
```

If `$BRANCH` is `$DEFAULT`, stop: this runs from a feature branch, since that's what carries
the ticket key.

## Step 2 — Find the pull request, if there is one

```sh
gh pr list --head "$BRANCH" --json number,title,body,url,state --limit 5
```

- Exactly one result → use it. Keep the URL, title, and body.
- Several → show them and ask which.
- None, or no `gh` → fine. Carry on from the branch alone.

## Step 3 — Resolve the issue key

Look for `[A-Z][A-Z0-9]+-[0-9]+` in this order, first match wins, uppercased:

1. the PR body — a browse link or a bare key,
2. the PR title,
3. the branch name — handles `<anything>/<KEY>-<slug>`, `<KEY>-<slug>`, and a bare `<KEY>`
   anywhere in the name.

```sh
printf '%s\n' "$BRANCH" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1
```

Branch names are often lower-case, so match case-insensitively and then upper-case the
result. Watch for false positives — a key-shaped fragment in a slug (`UTF-8`, `SHA-256`) is
not a ticket. If the only candidate looks like that, treat it as no match.

No key from any source → stop and say the ticket can't be determined, and ask for it.

## Step 4 — Discover the Jira site

**Never hardcode a tenant.** Try, in order, and say which one worked:

```sh
grep -rhoE 'https://[A-Za-z0-9-]+\.atlassian\.net' \
  CLAUDE.md AGENTS.md CONTRIBUTING.md README.md .github/ docs/ 2>/dev/null | sort -u
jira me 2>/dev/null                                    # jira-cli, if configured
grep -hoE 'https://[A-Za-z0-9-]+\.atlassian\.net' ~/.config/.jira/.config.yml 2>/dev/null
```

Then the PR body's own browse link. Self-hosted Jira won't match `atlassian.net` — widen the
search to any host followed by `/browse/` before concluding there's nothing.

If more than one site turns up, or none does, **ask**. Don't pick.

## Step 5 — Confirm the issue exists

Cheap, and it catches a mis-parsed key before you write a comment about the wrong ticket:

```sh
jira issue view "$KEY" 2>/dev/null                       # jira-cli
acli jira workitem view --key "$KEY" 2>/dev/null         # Atlassian CLI
```

Or the host's Jira integration if that's what you have. Keep the summary and status — the
summary tells you whether the key you parsed is really the ticket this work belongs to.

If no transport can read the issue, say the key is unverified and carry on. The comment still
gets written; the user posts it.

## Step 6 — Read what actually happened

**With a PR:** its title and body are the primary source. `gh pr diff --name-only` gives you
scope.

**Without one:**

```sh
git -C "$REPO" log --oneline "$REMOTE/$DEFAULT..HEAD"
git -C "$REPO" diff --name-only "$REMOTE/$DEFAULT..HEAD"
```

Read the changed paths for what part of the product moved — a directory name usually says
more about user-facing scope than the commit subjects do. If both the commits and the PR body
are thin, infer from the paths and say the update is based on file scope.

## Step 7 — Write the comment

Three sections, one to three sentences each. Translate as you go — "updated the settings
screen", not "refactored the settings container"; "fixed a case where saving failed", not
"resolved a null dereference".

```
🔄 Development update

What was done: <what changed, from a user's point of view>

Scope: <which part of the product this affects>

Next steps: <ready for QA / waiting on review / follow-up work needed on X>

Pull request: <url>
```

With no PR, the last line becomes `Branch: <branch> (no pull request opened yet)`.

Then the disclosure, **one sentence**, as the last line:

> Written with <model + version> from the branch's commits and pull request, and reviewed by
> me before posting.

**Match the markup to the transport** — this is the detail that makes the comment render
correctly, and it differs by route:

| Transport | Bold a label | Heading |
|---|---|---|
| host Jira integration, or REST with markdown conversion | `**What was done:**` | `## …` |
| `acli` | `**What was done:**` | `## …` |
| `jira` CLI (takes Jira wiki markup, not markdown) | `*What was done:*` | `h3. …` |
| plain text fallback | leave the labels unstyled | — |

In wiki markup, never use `#` for a bullet or a heading — it renders as an enormous heading.
Bullets are `*`, and `{{monospace}}` wraps identifiers.

Write it to `$WORK/comment.md` so the next step posts a file rather than an inline string.

## Step 8 — Show it, then post on confirmation

Show the user the rendered comment, the issue key with its browse URL, and which transport
you'd use. **Wait for an explicit yes.**

```sh
jira issue comment add "$KEY" --template "$WORK/comment.md" --no-input
acli jira workitem comment --key "$KEY" --body-file "$WORK/comment.md"
```

Or the host's integration, passing the body as markdown.

`jira`-cli hangs on interactive prompts, so `--no-input` with a template file is the only
reliable shape — never a heredoc or a `-b "$(cat …)"` substitution.

**With no transport at all,** that's the degrade path, and it's a normal outcome: print the
comment and the exact command, and say plainly that nothing was posted.

## Step 9 — Confirm

Two or three lines: the issue key and its URL, the PR link or branch name, the transport
used, and the comment as posted. If you skipped verification in Step 5 or fell back to
printing, say so here rather than leaving it implied.

---

## Principles

- **The audience is not you.** The ticket is read by someone planning, testing, or answering
  a customer. Translate every engineering word or cut it.
- **Three short sections beats one thorough paragraph.** What was done, what it affects,
  what's next. One to three sentences each, and nobody reads the fourth.
- **Never guess the tenant.** Discover the site from the repo's docs or the local config,
  and ask when discovery is ambiguous.
- **Probe the transport, then degrade out loud.** No CLI and no integration is a supported
  outcome: the comment still gets written, the user posts it.
- **Markup follows the transport.** Markdown through an integration, wiki markup through
  `jira`-cli. The same text posted the wrong way reads as garbage.
- **Never post without confirmation, and never transition the issue.** One comment, shown
  first, nothing else touched.
- **Don't inflate.** A small honest update is useful. An impressive one gets someone's plan
  wrong.
- **Name the model.** One sentence, the exact model and version, and that a human reviewed
  it.
- **Plain language, always — and short.** If it reads like a generated report, rewrite it
  before showing the user, and certainly before posting it.

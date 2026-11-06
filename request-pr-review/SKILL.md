---
name: request-pr-review
description: >-
  Post a PR review request to a configured Slack channel and mention the PR's reviewers.
  Defaults to the current branch's open PR; accepts an optional PR number or URL. When the
  PR has no reviewers, lists assignable users, sets them on the PR, then mentions them.
  Detects an existing request in the channel and replies in-thread instead of re-announcing.
  Optionally states plan series position ("PR 2 out of 4") from create-plan PLAN.md files.
  Use when the user wants to request review, ping reviewers on Slack, or announce a PR for
  review. Not for opening PRs (create-pr) or performing code review (pr-code-review).
license: Unlicense
metadata:
  version: "1.1.1"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git, gh) rather than
    host-specific tools. Slack posting probes MCP/CLI and degrades to a paste-ready message
    when no transport is available. Channel ID is remembered per repo in
    ~/.config/pr-review-request/repos.ini only — never writes config into repositories.
when_to_use: >-
  Use when an open PR needs human reviewers notified on Slack. Not for creating PRs,
  addressing review feedback, or adversarial review. If a repo ships its own
  request-pr-review skill, that one wins for team-specific channel and voice.
argument-hint: "[pr-number | pr-url]"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Request PR review

Announce an open PR in a **configured Slack channel** and ping its reviewers.

**Paths:**

- PR already has reviewers → map to Slack and post.
- PR has no reviewers → pick from assignable users, `gh pr edit --add-reviewer`, then post.

Reviewers are mentioned in **alphabetical order** (by display name).

References: [config.md](references/config.md) · [global-registry.md](references/global-registry.md) ·
[slack-transport.md](references/slack-transport.md) ·
[message-format.md](references/message-format.md) · [plan-series.md](references/plan-series.md)

## Argument

- **No argument** → resolve PR from the **current branch** (must not be the default branch).
- **PR number** (`1296`) or **PR URL** → target that PR directly; current branch is irrelevant.

## Guardrails

- **Confirm before posting** — Slack pings real people; show exact text and wait for approval.
- **Never guess a Slack user ID** — use the map, search, then ask.
- **One-liner** when `integration_threads_context=true` — do not duplicate bot-threaded context.
- **De-dupe** — if the channel already has a request for this PR, **thread a reply**; never
  post a second top-level announcement or use broadcast-reply.
- **No link previews** — never enable unfurling (`unfurl_app_links`, `unfurl_links`,
  `unfurl_media`). The channel's GitHub/Jira bots already thread the PR context; an inline
  preview duplicates it and inflates a one-line ping. See
  [slack-transport.md](references/slack-transport.md).
- **Series position only from a real plan** — see [plan-series.md](references/plan-series.md);
  standalone PRs omit `PR X out of N`.
- **Never create repo config files** — do not add `.pr-review-request` to a repository unless
  the user explicitly asks for a committed team config. Default save path is the
  [global registry](references/global-registry.md) only.
- **Never modify source code** — only PR reviewer metadata, the global registry, and Slack
  messages.

---

## Step 0 — Preflight

Fail fast with a clear message. Do not partial-workaround.

```sh
git rev-parse --is-inside-work-tree   # 1. inside a git repo
gh auth status                        # 2. gh installed + authenticated
gh repo view --json nameWithOwner -q .nameWithOwner   # 3. repo reachable
```

4. **Resolve config** — [references/config.md](references/config.md). Read
   `~/.config/pr-review-request/repos.ini` for the current `owner/repo`
   ([global-registry.md](references/global-registry.md)). If missing, ask for the Slack
   channel ID (or `#name` to resolve), then **save only to the global registry** — never
   create `.pr-review-request` in the repo.

5. **Slack transport** — [references/slack-transport.md](references/slack-transport.md).
   If no transport can post, continue in **manual mode** (compose + print for paste).

Only when checks 1–3 pass (and channel is known), continue.

---

## Step 1 — Resolve the PR

**1a. Fetch PR metadata**

```sh
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# With argument <N> or URL-derived N:
gh pr view <N> --repo "$REPO" \
  --json number,url,title,state,isDraft,reviewRequests,headRefName

# No argument (current branch):
BRANCH=$(git branch --show-current)
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
# abort if BRANCH == DEFAULT
gh pr view --json number,url,title,state,isDraft,reviewRequests,headRefName
```

Save `PR_NUMBER`, `PR_URL`, `PR_TITLE`, `state`, `isDraft`, `headRefName`, `reviewRequests`.

No open PR for branch → abort: "No open PR for this branch. Open one first (create-pr), or
pass a PR number/URL."

**1b. Gate on state**

- `OPEN` (draft or ready) → continue
- `MERGED` → abort: already merged
- `CLOSED` → abort: reopen first

### Step 1c — De-dupe (existing request)

Search the configured channel for `pull/<PR_NUMBER>` (see slack-transport.md).

- **Found** → show permalink/date; compose a **threaded** follow-up per
  [message-format.md](references/message-format.md); confirm; send; **done** (skip Steps 2–7).
- **Not found** / search unavailable → ask human if unsure; else continue.

---

## Step 2 — Determine reviewers

**Non-empty `reviewRequests`** → collect GitHub logins → Step 4.

**Empty** → Step 3.

---

## Step 3 — Pick and set reviewers

```sh
OWNER=$(gh repo view --json owner -q .owner.login)
NAME=$(gh repo view --json name -q .name)
gh api graphql -f query="
  { repository(owner:\"$OWNER\", name:\"$NAME\") {
      assignableUsers(first:100) { nodes { login name } }
  }}" --jq '.data.repository.assignableUsers.nodes[] | "\(.login)\t\(.name // "")"'
```

Present the list; ask the human who to request (multi-select). Resolve every pick to a
**GitHub login**.

```sh
gh pr edit <PR_NUMBER> --repo "$REPO" --add-reviewer <login1> --add-reviewer <login2> ...
```

Report failures per login (not a collaborator, already requested); continue with successes.

---

## Step 4 — Map GitHub logins → Slack mentions

Load `github_slack_map` from config ([config.md](references/config.md)).

For each login:

1. Cache hit in JSON map → `<@slack_id|display_name>`
2. Else `gh api users/<login> --jq '.name // .login'` + Slack user search → confirm if ambiguous
3. Never invent an ID

Sort mentions alphabetically by display name.

---

## Step 5 — Compose the message

Follow [message-format.md](references/message-format.md).

**5a. Series position (optional)**

[references/plan-series.md](references/plan-series.md) — ticket key from `headRefName`, plan
from plan store (`.plan-store` / `PLANS_DIR`), **PR map** preferred, `### PR` headings as
fallback. Yields `PR <X> out of <N>` or standalone.

**5b. One-liner**

- Plan-backed: `<mentions> Please review PR X out of N: [#N](PR_URL) - <clause>. Thank you!`
- Standalone: `<mentions> Please review PR [#N](PR_URL) - <clause>. Thank you!`

Clause = one line from PR title/scope. PR link = markdown `[#N](url)`.

---

## Step 6 — Confirm

Show:

- Exact message text
- Target channel (name + ID if known)
- Plan resolution line (from plan-series.md) or standalone note
- Reviewers added in Step 3 (if any)

Ask: **send**, **edit**, or **cancel**. Wait for explicit approval.

---

## Step 7 — Send

**Slack transport available** → post per [slack-transport.md](references/slack-transport.md)
with unfurling **off**; report message link.

**Manual mode** → print fenced block for copy-paste into the channel.

If reviewers were set in Step 3, note which logins were added.

---

## Related skills

| Skill | Role |
|-------|------|
| **create-pr** | Opens the PR before review is requested |
| **create-plan** | Authors PLAN.md / PR map used for series position |
| **execute-plan** | Implements a plan slice before review |
| **pr-code-review** | Interactive adversarial review — not an announcement |
| **pr-code-review-batch** | Unattended CI/batch review of the same PR (findings only) |

## Skill layout

```
request-pr-review/
├── SKILL.md
├── examples/
│   ├── pr-review-request.example.ini
│   └── github-slack.json
└── references/
    ├── config.md
    ├── global-registry.md
    ├── slack-transport.md
    ├── message-format.md
    └── plan-series.md
```

# Review-request message format

## One-liner rule

When `integration_threads_context=true` in config (default), the Slack message is a **single
line**. Linked GitHub/Jira bots often auto-thread issue context — do not duplicate Jira
links, changelogs, or bullet lists in the message.

Set `integration_threads_context=false` when your channel has no such integration and the
team expects more context inline (still keep it short).

## PR link — markdown form

Use standard markdown links in the message body:

```markdown
[#42](https://github.com/org/repo/pull/42)
```

**Do not** write `https://github.com/org/repo/pull/42|#42` — Slack percent-encodes the pipe.

If your transport requires Slack autolink syntax instead, wrap the whole token:
`<https://github.com/org/repo/pull/42|#42>`.

Discover `org/repo` from `gh repo view --json nameWithOwner`.

## Templates

Sort reviewer mentions **alphabetically by display name**.

**Standalone:**

```
<mentions> Please review PR [#N](PR_URL) - <one clause from PR title/scope>. Thank you!
```

**Plan-backed:**

```
<mentions> Please review PR <X> out of <N>: [#PR_NUM](PR_URL) - <one clause>. Thank you!
```

**Threaded follow-up** (prior request exists — no series position):

```
Updated — ready for another review round. Thank you!
```

Optionally re-mention reviewers. Keep it brief.

## Voice

- Concise, friendly, ends with "Thank you!" or "Thanks!"
- Optional urgency: "For tomorrow, please."
- One clause describing scope — derived from PR title, not a paragraph
- No fabricated context the PR does not support

## Reviewer mentions

Build from the GitHub → Slack map ([config.md](config.md)). Format:
`<@SLACK_ID|Display Name>`.

When no reviewers are set on the PR, the skill adds them via `gh pr edit --add-reviewer`
after the human picks from assignable users.

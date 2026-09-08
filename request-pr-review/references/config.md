# Review-request configuration

Configuration lives **outside repositories** by default. Nothing is written into a repo's
working tree and **no `.gitignore` entry is required**.

**Default store:** [global-registry.md](global-registry.md) —
`~/.config/pr-review-request/repos.ini` (one section per `owner/repo`).

## Resolution order

| Priority | Source | Written to repo? |
|----------|--------|------------------|
| 1 | Session override from the user | No |
| 2 | **`SLACK_REVIEW_CHANNEL_ID`** env var | No |
| 3 | **`SLACK_REVIEW_CHANNEL`** env var | No |
| 4 | **`~/.config/pr-review-request/repos.ini`** | No |
| 5 | **Ask once → save to global registry** | No |
| 6 | **`.pr-review-request` in repo root** *(read only)* | Only if someone else committed it |

Step 6 is a **read-only fallback** for repos that already ship team config. The skill
**never creates** `.pr-review-request` in a repository unless you explicitly ask for a
committed team file.

## Global registry (default)

See [global-registry.md](global-registry.md). Section keys use `owner/repo` from
`gh repo view`.

```ini
[acme/api-service]
slack_channel_id=C0123456789
github_slack_map=/home/you/.config/pr-review-request/github-slack.json
integration_threads_context=true
updated=2026-09-07
```

Example file: [examples/repos.ini.example](../examples/repos.ini.example).

Shared GitHub → Slack map (optional, one file for all repos):

```text
~/.config/pr-review-request/github-slack.json
```

See [examples/github-slack.json](../examples/github-slack.json).

## Repo-local file (opt-in only — usually avoid)

If a team **chooses** to commit shared config, they may add `.pr-review-request` at the repo
root themselves. The skill will **read** it when present but will **not** create or modify
it by default.

```ini
slack_channel_id=C0123456789
github_slack_map=.github/github-slack.json
integration_threads_context=true
```

That path is for teams who want config in git — not the default workflow.

## GitHub → Slack map

When a reviewer login is missing from the map, resolve via your Slack transport's user search
(by display name from `gh api users/<login>`), then ask the human to confirm before
mentioning. **Never guess a Slack user ID.**

## Repository context

```sh
gh repo view --json nameWithOwner -q .nameWithOwner
```

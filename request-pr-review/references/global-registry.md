# Global registry — per-repo memory (user-level)

The **only** place the skill writes configuration by default. Stores Slack channel IDs per
`owner/repo` on your machine — **not inside any git repository**.

No `.pr-review-request` file in repos. No `.gitignore` changes needed.

## Location

```text
~/.config/pr-review-request/repos.ini
```

Fallback if `~/.config` does not exist: `~/.pr-review-request/repos.ini`

```sh
mkdir -p ~/.config/pr-review-request
```

Optional shared map for all repos:

```text
~/.config/pr-review-request/github-slack.json
```

## Format

INI file. One section per GitHub repository:

```ini
# ~/.config/pr-review-request/repos.ini

[acme/api-service]
slack_channel_id=C0123456789
github_slack_map=/home/you/.config/pr-review-request/github-slack.json
integration_threads_context=true
updated=2026-09-07

[acme/web-app]
slack_channel_id=C0987654321
integration_threads_context=true
updated=2026-09-07
```

Paths in `github_slack_map` should be **absolute** when stored here.

## Resolution order

| Priority | Source |
|----------|--------|
| 1 | User override this session |
| 2 | `SLACK_REVIEW_CHANNEL_ID` / `SLACK_REVIEW_CHANNEL` env |
| 3 | **`~/.config/pr-review-request/repos.ini`** |
| 4 | Ask once → write to (3) |
| 5 | Read `.pr-review-request` in repo **only if it already exists** (never create) |

## First-time flow

When `owner/repo` has no section in `repos.ini`:

1. Ask: "Which Slack channel should review requests for **owner/repo** go to?"
2. Resolve channel ID if the user gives `#name` only.
3. Append or update the `[owner/repo]` section in `repos.ini`.
4. **Do not** create `.pr-review-request` in the repository.

Report:

```
Saved for acme/api-service → ~/.config/pr-review-request/repos.ini (slack_channel_id=C012…)
```

## Updating or forgetting

- Provide a new channel when prompted → overwrites that repo's section.
- Delete the `[owner/repo]` section → prompted again next time.
- Edit `repos.ini` directly anytime.

## Reading a repo's section

```sh
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
REGISTRY="${XDG_CONFIG_HOME:-$HOME/.config}/pr-review-request/repos.ini"
[ -f "$REGISTRY" ] || REGISTRY="$HOME/.pr-review-request/repos.ini"

awk -v section="[$REPO]" '
  $0 == section { found=1; next }
  /^\[/ { found=0 }
  found && /^slack_channel_id=/ { print substr($0, index($0,"=")+1); exit }
' "$REGISTRY" 2>/dev/null
```

## Not Cursor chat memory

This is a file on disk — predictable, editable, and portable across agent hosts.

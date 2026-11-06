# Slack transport — posting review requests

The skill ends in a **public Slack message**. Probe what is available; degrade explicitly
when posting is not possible.

## Capability probe (run in order)

```sh
command -v slack          # Slack CLI, if installed
gh auth status            # already required for PR resolution
```

Then check whether the host exposes Slack messaging tools (MCP or built-in). Read the tool
schema before calling — names vary (`slack_send_message`, `chat.postMessage`, etc.).

| Transport | When to use |
|-----------|-------------|
| **Slack MCP / host tools** | Schema available and authenticated |
| **`slack` CLI** | `slack chat send --channel … --text …` (confirm exact flags from `slack help`) |
| **Manual fallback** | Neither works — print the composed message, channel, and thread instructions |

If Slack is unavailable, **do not** fail silently. Output:

```
--- paste into #your-channel ---
<message text>
--- end ---
```

## Channel targeting

Use `slack_channel_id` from config when present; otherwise resolve `slack_channel_name`.

## Link previews — keep them off

The message is a one-line ping, and the channel's GitHub/Jira integrations already unfurl the
PR into a thread. A second preview rendered inline turns a one-liner into a card several times
its height and duplicates context the bot is about to post anyway.

So **do not enable unfurling**. Concretely:

| Transport | What to do |
|-----------|------------|
| Slack MCP / host tools | Leave `unfurl_app_links` **unset or `false`**. Pass `unfurl_links: false` and `unfurl_media: false` when the schema exposes them. |
| `chat.postMessage` directly | `unfurl_links=false`, `unfurl_media=false`. |
| `slack` CLI | Check `slack help` — omit any `--unfurl` flag. |

Read the tool's schema before calling: a parameter that sounds like it merely *permits* a
preview (`unfurl_app_links`) usually *requests* one. Enabling it is the failure mode here, not
the default.

This holds for the threaded follow-up too, where the parent already carries the unfurl.

## Threaded reply (de-dupe)

When a prior review request exists for the same PR (see SKILL.md Step 2c), post a **plain
thread reply** — never `reply_broadcast` (that re-announces to the channel).

## Mention format

Slack user mentions: `<@SLACK_USER_ID|Display Name>` (mrkdwn).

Sort mentions **alphabetically by display name** before composing the message.

## Search for prior requests

When your transport supports channel search, look for the PR's `pull/<number>` token in the
configured channel. Ignore bot auto-thread noise from GitHub/Jira integrations — match the
human top-level "please review" message.

If search is unavailable, ask the human whether a prior announcement exists before posting a
new top-level message.

# Jira transport — discover, fetch, write

Never hardcode a tenant, cloud id, or story-points field. Discover, then remember in
`$CFG/config.ini` ([config.md](config.md)).

```sh
CFG="${PRE_GROOM_CONFIG_DIR:-$HOME/.pre-groom}"
mkdir -p "$CFG"
```

## Probe transports (in order)

Say which ones exist. Prefer the first that can both **read** and **write** when available.
**Jira/Atlassian MCP always outranks the CLIs** when its tools are actually callable in this
session.

1. **Jira / Atlassian MCP** (preferred) — inspect the host's MCP/tool catalog for namespaces
   or tools matching `jira`, `atlassian`, or `rovo`. Typical capabilities: get issue, search
   by JQL / filter, edit fields (story points, assignee), add comment, current user.
   Read schemas before calling. Optional disk probe (not sufficient alone):

```sh
rg -ni 'jira|atlassian|rovo' \
  "$HOME/.cursor/mcp.json" \
  "$HOME/.mcp.json" \
  "$HOME/.claude.json" \
  "$HOME/.codex/config.toml" \
  "$HOME/.gemini/settings.json" \
  2>/dev/null | head -20
```

   If MCP is present and authenticated → use it for fetch, reassign, and write-back. Only
   fall back to a CLI for a specific operation the MCP cannot do, and say so.

2. **`jira` CLI** (`command -v jira`) — fallback when no usable MCP
3. **`acli`** (`command -v acli`) — fallback after `jira`
4. **None** — use the degrade paths below

Report the chosen transport explicitly at preflight, e.g.
`Transport: Atlassian MCP (preferred)` or `Transport: jira CLI (no MCP in session)`.

## Discover the site

Try, in order; say which worked:

```sh
# 1. Saved config
grep -E '^jira_site=' "$CFG/config.ini" 2>/dev/null

# 2. Env
printf '%s\n' "${PRE_GROOM_JIRA_SITE:-}"

# 3. Docs in the current checkout (read-only)
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$ROOT" ]; then
  grep -rhoE 'https://[A-Za-z0-9-]+\.atlassian\.net' \
    "$ROOT/CLAUDE.md" "$ROOT/AGENTS.md" "$ROOT/CONTRIBUTING.md" "$ROOT/README.md" \
    "$ROOT/.github" "$ROOT/docs" 2>/dev/null | sort -u
fi

# 4. Local jira-cli config (common locations — skip missing files)
for f in \
  "$HOME/.jira.d/config.yml" \
  "$HOME/.config/.jira/.config.yml" \
  "$HOME/.jira/config.yml"
do
  [ -f "$f" ] && grep -hoE 'https://[A-Za-z0-9-]+\.atlassian\.net' "$f" 2>/dev/null
done
```

Widen to any host followed by `/browse/` for self-hosted Jira. If zero or multiple sites,
**ask**. Do not pick silently. After the engineer confirms, save `jira_site=` to
`$CFG/config.ini`.

## Cloud id (host MCP / REST)

Some host integrations require a cloud id (often the site hostname, sometimes a UUID). Resolve
**non-empty** values only:

1. `PRE_GROOM_JIRA_CLOUD_ID`
2. `jira_cloud_id=` in `$CFG/config.ini`
3. Ask once → save

CLIs that do not need a cloud id may skip this. Never invent one.

## Story points field

**Never guess a field id** (including `customfield_10016`). Resolve **non-empty** values only;
missing and blank count as unset and fall through:

1. `PRE_GROOM_STORY_POINTS_FIELD` (non-empty)
2. `story_points_field=` in `$CFG/config.ini` (non-empty)
3. Ask once → save to `$CFG/config.ini`

Refuse any story-points **write** until a field id is confirmed. The display name "Story Points"
alone is not enough for API writes — store the field **id**.

## Who am I (for assignee prioritization)

```sh
jira me 2>/dev/null
acli jira auth status 2>/dev/null
# Or the host integration's current-user equivalent
```

Keep `accountId` and display name when available.

## Fetch

**By keys** — one issue at a time or batch, depending on the transport.

**By filter** — JQL `filter = <id>` (numeric filter id from Jira).

Required fields conceptually: summary, description, status, issuetype, assignee, reporter,
labels, issuelinks, attachment, parent, fixVersions, story points.

Examples (shapes vary by CLI version — adjust flags after `jira --help` / `acli jira --help`):

```sh
jira issue view PROJ-123 --plain 2>/dev/null
acli jira workitem view --key PROJ-123 2>/dev/null
jira issue list -q 'filter = 11169' --plain 2>/dev/null
```

Host integrations: use search-by-JQL or get-issue equivalents with markdown/readable
description when offered.

Also open **linked issues** (blocks / is blocked by / relates to) when they change scope —
fetch summaries; full pre-groom only if asked.

### No read transport (paste path)

If nothing can fetch issues:

1. Ask the engineer to paste, per ticket: key, type, summary, description, AC (if any),
   assignee, reporter, epic/parent, links, attachments/design links, current story points.
2. Continue Steps 1–4 on that paste.
3. State clearly that the ticket was **not live-verified** against Jira.
4. Step 5 still drafts the comment; posting requires a write transport or the command
   degrade path.

## Browse URL

```text
{jira_site}/browse/{KEY}
```

## Reassign

Only after an explicit yes in Step 1. Set assignee to the current user's account id (or the
CLI's equivalent "me" assignee form).

```sh
# Illustrative — match your CLI's real flags
jira issue assign PROJ-123 "$(jira me --plain 2>/dev/null)" --no-input
acli jira workitem edit --key PROJ-123 --assignee "$(whoami)"   # prefer accountId when known
```

Host integration: edit-issue with the assignee/accountId field.

**No write transport:** print the browse URL and exact CLI/UI steps; do not claim the
reassign happened. Continue only after the engineer confirms they reassigned, or chooses
continue-as-is.

## Write-back (only after explicit yes)

1. Set story points on the configured field (field id must be non-empty — see above).
2. Add the approved comment body.

Pass `jira_cloud_id` when the host integration requires it.

```sh
# Illustrative — match your CLI's real flags
jira issue edit PROJ-123 -custom "$FIELD=$N" --no-input
jira issue comment add PROJ-123 --template "$WORK/comment.md" --no-input

acli jira workitem edit --key PROJ-123 --field "$FIELD=$N"
acli jira workitem comment --key PROJ-123 --body-file "$WORK/comment.md"
```

Host integration: edit-issue + add-comment with markdown when supported.

**`jira` CLI** often hangs on interactive prompts — prefer `--no-input` and template/body
files over heredocs.

## Markup

| Transport | Prefer |
|-----------|--------|
| Host integration / REST markdown | Markdown (`##`, `**`, `-`) |
| `acli` | Markdown |
| `jira` CLI (wiki markup) | `h3.`, `*bold*`, `*` bullets — never `#` headings |

## Degrade path (no write)

Show the full comment, the story-points value, browse URL, and exact commands. Say clearly
that nothing was posted.

# Jira transport — discover, fetch, edit

Never hardcode a tenant or cloud id. Discover, then remember in `$CFG/config.ini`
([config.md](config.md)).

```sh
CFG="${DESLOPIFY_CONFIG_DIR:-$HOME/.deslopify}"
mkdir -p "$CFG"
```

## Probe transports (in order)

Say which ones exist. Prefer the first that can **read and write** issue fields.
**Jira/Atlassian MCP always outranks the CLIs** when its tools are actually callable in this
session.

1. **Jira / Atlassian MCP** — inspect the host's tool catalog for namespaces or tools
   matching `jira`, `atlassian`, or `rovo`. Read schemas before calling. Optional disk probe
   (not sufficient alone):

```sh
rg -ni 'jira|atlassian|rovo' \
  "$HOME/.cursor/mcp.json" \
  "$HOME/.mcp.json" \
  "$HOME/.claude.json" \
  "$HOME/.codex/config.toml" \
  "$HOME/.gemini/settings.json" \
  2>/dev/null | head -20
```

   If MCP is present and authenticated → use it for fetch and write-back. Only fall back to a
   CLI for a specific operation the MCP cannot do, and say so.

2. **`jira` CLI** (`command -v jira`) — fallback when no usable MCP
3. **`acli`** (`command -v acli`) — fallback after `jira`
4. **None** — degrade path (print commands; no edits)

Report the chosen transport explicitly at preflight, e.g.
`Transport: Atlassian MCP (preferred)` or `Transport: jira CLI (no MCP in session)`.

## Discover the site

Try, in order; say which worked:

```sh
grep -E '^jira_site=' "$CFG/config.ini" 2>/dev/null
printf '%s\n' "${DESLOPIFY_JIRA_SITE:-}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$ROOT" ]; then
  grep -rhoE 'https://[A-Za-z0-9-]+\.atlassian\.net' \
    "$ROOT/CLAUDE.md" "$ROOT/AGENTS.md" "$ROOT/CONTRIBUTING.md" "$ROOT/README.md" \
    "$ROOT/.github" "$ROOT/docs" 2>/dev/null | sort -u
fi

for f in \
  "$HOME/.jira.d/config.yml" \
  "$HOME/.config/.jira/.config.yml" \
  "$HOME/.jira/config.yml"
do
  [ -f "$f" ] && grep -hoE 'https://[A-Za-z0-9-]+\.atlassian\.net' "$f" 2>/dev/null
done
```

Widen to any host followed by `/browse/` for self-hosted Jira. Zero or multiple sites →
**ask**. After confirm, save `jira_site=` to `$CFG/config.ini`.

## Cloud id (host MCP / REST)

Resolve non-empty values only:

1. `DESLOPIFY_JIRA_CLOUD_ID`
2. `jira_cloud_id=` in `$CFG/config.ini`
3. Ask once → save

## Fetch issue

Required: **summary**, **description** (and key for browse URL).

```sh
jira issue view PROJ-123 --plain 2>/dev/null
acli jira workitem view --key PROJ-123 2>/dev/null
```

Host integration: get-issue with readable/markdown description when offered.

**No read transport:** ask for key, summary, and description paste. State the issue was not
live-verified.

Browse URL: `{jira_site}/browse/{KEY}`

## Write-back (only after explicit yes)

Order matters:

1. **Add archive comment** (`$WORK/archive-comment.md`) — **capture the comment URL or id**
   from the response for the description disclaimer
2. **Edit summary** (deslopified title)
3. **Edit description** (Format A body from `$WORK/description.md`, disclaimer linking to
   step 1 — see [description-template.md](description-template.md))

```sh
# Illustrative — match your CLI's real flags
jira issue comment add PROJ-123 --template "$WORK/archive-comment.md" --no-input
jira issue edit PROJ-123 --summary "Deslopified title" --no-input
jira issue edit PROJ-123 --no-input < "$WORK/description.md"

acli jira workitem comment --key PROJ-123 --body-file "$WORK/archive-comment.md"
acli jira workitem edit --key PROJ-123 --summary "Deslopified title"
acli jira workitem edit --key PROJ-123 --description-file "$WORK/description.md"
```

Host integration: add-comment then edit-issue (summary + description). Pass `jira_cloud_id`
when required.

**`jira` CLI** — prefer `--no-input` and template/body files for comments; never heredocs on
the command line. Description edits use stdin or `-b`/`--body` (not `--description` or
`--body-file`). The CLI converts markdown bodies on edit.

## Markup

| Transport | Comments | Description edits |
|-----------|----------|-------------------|
| Host integration / REST markdown | Markdown (`##`, `**`, `-`) | Markdown |
| `acli` | Markdown | Markdown |
| `jira` CLI | Wiki markup (`h3.`, `*bold*`, `*` bullets — never `#`) | Markdown in `$WORK/description.md` (CLI converts on edit) |

For `jira` CLI **comments** (including the archive comment), write a wiki-markup variant to
`$WORK/archive-comment.md` — see Step 8a in `SKILL.md`. Do not post markdown through
`jira issue comment add --template`; it is not converted.

## Degrade path (no write)

Show archive comment, proposed summary, proposed description, browse URL, and exact commands.
Say clearly that nothing was posted or edited.

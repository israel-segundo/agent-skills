# Pre-groom configuration

Configuration lives **outside repositories**. The skill never creates or modifies files
inside a git working tree for its own settings. Session drafts and diagrams use `$WORK`
from `mktemp -d` (the OS temp directory), never a checkout.

**Default store:** [global-registry.md](global-registry.md) under `$HOME/.pre-groom/`.

Paths are home-relative and intentionally **not** tied to XDG, `%APPDATA%`, or other
OS-specific config conventions. Override with `PRE_GROOM_CONFIG_DIR` when needed.

## Files

| File | Purpose |
|------|---------|
| `$HOME/.pre-groom/config.ini` | Jira site, cloud id, story-points field id |
| `$HOME/.pre-groom/projects.ini` | Project key → local checkout path(s) |

```sh
CFG="${PRE_GROOM_CONFIG_DIR:-$HOME/.pre-groom}"
mkdir -p "$CFG"
```

`$HOME` is assumed (macOS, Linux, WSL, Git Bash). If it is unset, ask for an absolute
`PRE_GROOM_CONFIG_DIR` before writing anything.

## Resolution order (Jira site)

| Priority | Source | Written to repo? |
|----------|--------|------------------|
| 1 | Session override from the user | No |
| 2 | Env: `PRE_GROOM_JIRA_SITE` | No |
| 3 | `$CFG/config.ini` → `jira_site=` | No |
| 4 | Discovery from current checkout docs / local Jira CLI config (read-only) | No |
| 5 | Ask once → save `jira_site=` to `$CFG/config.ini` | No |

## Resolution order (story-points field id)

| Priority | Source | Written to repo? |
|----------|--------|------------------|
| 1 | Session override | No |
| 2 | Env: `PRE_GROOM_STORY_POINTS_FIELD` (**non-empty** only) | No |
| 3 | `$CFG/config.ini` → `story_points_field=` (**non-empty** only) | No |
| 4 | Ask once → save to `$CFG/config.ini` | No |

**Never guess** a field id. Missing and blank values are unset — fall through. Story-points
ids are **not** discovered from repo docs. See [jira-transport.md](jira-transport.md).

## Resolution order (cloud id, when the transport needs it)

| Priority | Source |
|----------|--------|
| 1 | Session override / `PRE_GROOM_JIRA_CLOUD_ID` (**non-empty**) |
| 2 | `$CFG/config.ini` → `jira_cloud_id=` (**non-empty**) |
| 3 | Ask once → save (host MCP/REST often needs this; many CLIs do not) |

## Resolution order (project → repo paths)

| Priority | Source | Written to repo? |
|----------|--------|------------------|
| 1 | Session override / engineer answer this run | No |
| 2 | `$CFG/projects.ini` for the ticket's project key | No |
| 3 | CWD if it is already a git root and the engineer confirms it | No |
| 4 | Ask → **save to `$CFG/projects.ini` or session-only** (engineer chooses) | No |

**Never** invent a path. **Never** write skill config into a repository. Settings live only
under `$CFG`.

## `config.ini` keys

```ini
# $HOME/.pre-groom/config.ini
jira_site=https://example.atlassian.net
# Required by some host MCP/REST writes; leave blank if unused
jira_cloud_id=
# Required before any story-points write — ask if unset (no silent default)
story_points_field=
updated=2026-09-08
```

Example: [examples/config.ini.example](../examples/config.ini.example).

## `projects.ini` keys

One section per Jira **project key** (not GitHub `owner/repo`):

```ini
# $HOME/.pre-groom/projects.ini
[PROJ]
primary=/absolute/path/to/product-api
extra=/absolute/path/to/product-web,/absolute/path/to/product-contracts
notes=API is primary; web + contracts when tickets mention UI or shared types
updated=2026-09-08
```

- `primary` — main checkout for codebase review (`REPO_PATH`)
- `extra` — optional comma-separated absolute paths (`EXTRA_REPO_PATHS`)
- Store **absolute** paths

Example: [examples/projects.ini.example](../examples/projects.ini.example).

## Env overrides

```sh
export PRE_GROOM_JIRA_SITE=https://example.atlassian.net
export PRE_GROOM_JIRA_CLOUD_ID=example.atlassian.net
export PRE_GROOM_STORY_POINTS_FIELD=customfield_10016   # example id only
export PRE_GROOM_CONFIG_DIR=/absolute/path/to/alt-config
```

When `PRE_GROOM_CONFIG_DIR` is set, read/write `config.ini` and `projects.ini` there instead
of `$HOME/.pre-groom/`.

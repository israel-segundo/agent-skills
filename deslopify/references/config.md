# Deslopify configuration

Configuration lives **outside repositories**. The skill never creates or modifies files
inside a git working tree for its own settings. Session drafts use `$WORK` from `mktemp -d`
(the OS temp directory), never a checkout.

**Default store:** `$HOME/.deslopify/`.

Paths are home-relative and intentionally **not** tied to XDG, `%APPDATA%`, or other
OS-specific config conventions. Override with `DESLOPIFY_CONFIG_DIR` when needed.

## Files

| File | Purpose |
|------|---------|
| `$HOME/.deslopify/config.ini` | Jira site, cloud id |

```sh
CFG="${DESLOPIFY_CONFIG_DIR:-$HOME/.deslopify}"
mkdir -p "$CFG"
```

`$HOME` is assumed (macOS, Linux, WSL, Git Bash). If it is unset, ask for an absolute
`DESLOPIFY_CONFIG_DIR` before writing anything.

## Resolution order (Jira site)

| Priority | Source | Written to repo? |
|----------|--------|------------------|
| 1 | Session override from the user | No |
| 2 | Env: `DESLOPIFY_JIRA_SITE` | No |
| 3 | `$CFG/config.ini` → `jira_site=` | No |
| 4 | Discovery from current checkout docs / local Jira CLI config (read-only) | No |
| 5 | Ask once → save `jira_site=` to `$CFG/config.ini` | No |

## Resolution order (cloud id, when the transport needs it)

| Priority | Source |
|----------|--------|
| 1 | Session override / `DESLOPIFY_JIRA_CLOUD_ID` (**non-empty**) |
| 2 | `$CFG/config.ini` → `jira_cloud_id=` (**non-empty**) |
| 3 | Ask once → save (host MCP/REST often needs this; many CLIs do not) |

**Never guess** a tenant or cloud id. See [jira-transport.md](jira-transport.md).

## `config.ini` keys

```ini
# $HOME/.deslopify/config.ini
jira_site=https://example.atlassian.net
# Required by some host MCP/REST writes; leave blank if unused
jira_cloud_id=
updated=2026-09-08
```

Example: [examples/config.ini.example](../examples/config.ini.example).

## Env overrides

```sh
export DESLOPIFY_JIRA_SITE=https://example.atlassian.net
export DESLOPIFY_JIRA_CLOUD_ID=example.atlassian.net
export DESLOPIFY_CONFIG_DIR=/absolute/path/to/alt-config
```

When `DESLOPIFY_CONFIG_DIR` is set, read/write `config.ini` there instead of
`$HOME/.deslopify/`.

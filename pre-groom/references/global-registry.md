# Global registry — project → checkout memory (user-level)

The **only** place this skill writes configuration by default. Maps Jira project keys to
local absolute paths on your machine — **not inside any git repository**.

## Location

```text
$HOME/.pre-groom/projects.ini
$HOME/.pre-groom/config.ini
```

Override root with `PRE_GROOM_CONFIG_DIR` when set. No XDG / OS-specific config roots.

```sh
CFG="${PRE_GROOM_CONFIG_DIR:-$HOME/.pre-groom}"
mkdir -p "$CFG"
```

## Format (`projects.ini`)

```ini
# $HOME/.pre-groom/projects.ini

[PROJ]
primary=/absolute/path/to/product-api
extra=/absolute/path/to/product-web
updated=2026-09-08

[OPS]
primary=/absolute/path/to/ops-tooling
updated=2026-09-08
```

## First-time flow

When a ticket's project key has no section:

1. Ask which local path(s) to analyze for this project (primary, and any extras).
2. Verify each path exists and is a git root (`git -C "$path" rev-parse --show-toplevel`).
3. Ask: **save to `$CFG/projects.ini` for next time, or keep session-only?**
4. Only on **save**, append or update the `[PROJECTKEY]` section.
5. **Do not** create any config file inside those repositories.

Report when saved:

```
Saved PROJ → $CFG/projects.ini (primary=/absolute/path/…)
```

## Multi-repo tickets

Some tickets need more than one checkout (API + client, contracts + service, etc.). That is
allowed:

1. Prefer `extra=` paths already registered for the project.
2. If the ticket text, issue links, or search imply another system, ask for that path and
   either use it for this session only or offer to append it to `extra=` (after save
   confirmation).
3. Explore each resolved path with the same hedging rules as the primary
   ([codebase-review.md](codebase-review.md)).

Sibling discovery (hints only — still confirm with the engineer before saving):

```sh
PRIMARY="$(git rev-parse --show-toplevel 2>/dev/null || true)"
PARENT="$(dirname "${PRIMARY:-$PWD}")"
ls -d "$PARENT"/*/ 2>/dev/null
```

## Reading a project section

```sh
KEY=PROJ   # from the ticket key prefix
CFG="${PRE_GROOM_CONFIG_DIR:-$HOME/.pre-groom}"
REGISTRY="$CFG/projects.ini"

awk -v section="[$KEY]" '
  $0 == section { found=1; next }
  /^\[/ { found=0 }
  found && /^primary=/ { print "primary=" substr($0, index($0,"=")+1) }
  found && /^extra=/ { print "extra=" substr($0, index($0,"=")+1) }
' "$REGISTRY" 2>/dev/null
```

## Updating or forgetting

- New path when prompted → overwrite that project's section fields (after save confirmation).
- Delete the `[KEY]` section → prompted again next time.
- Edit the ini files directly anytime.

## Not chat memory

These are files on disk — editable, portable across agent hosts and OSes, and independent of
any repository clone.

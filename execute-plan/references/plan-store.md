# Plan store — directory resolution

> Keep in sync with `create-plan/references/plan-store.md` (canonical).

Both **create-plan** and **execute-plan** read plans from a single configurable
**plan store directory**. Plans are not required to live inside the repository.

## Resolution order

Apply the first match:

| Priority | Source | Example |
|----------|--------|---------|
| 1 | **Explicit path** from the user in this session | `/home/me/plans/acme/PROJ-42-auth/PLAN.md` |
| 2 | **`PLANS_DIR` environment variable** | `export PLANS_DIR=/home/me/plans/acme` |
| 3 | **`.plan-store` in the repository root** | `plans_dir=/home/me/plans/acme` |
| 4 | **Ask once, then write `.plan-store`** | First **create-plan** run with no config |
| 5 | **Default** | `<repo-root>/docs/plans` |

Relative paths in `.plan-store` or `PLANS_DIR` resolve from the **repository root**
(`git rev-parse --show-toplevel`).

## `.plan-store` format

Plain key=value, one setting per line. Comments start with `#`.

```ini
# Plan store for this repository (written by create-plan)
plans_dir=/home/me/plans/my-project
```

**At first plan creation** when no config exists: ask the user where plans should live.
Accept an absolute path or a repo-relative path. Create the directory if missing, then write
`.plan-store`. Ask whether to add `.plan-store` to `.gitignore` when the path is
machine-specific.

## Discovering a plan

Given a ticket key (`PROJ-42`) or slug, search under `plans_dir`:

1. **Preferred:** `{plans_dir}/{KEY}-{slug}/PLAN.md`
2. **Alternate:** `{plans_dir}/{KEY}-{slug}/` with `*plan*.md` or `*implementation-plan*.md`
3. **Legacy flat file:** `{plans_dir}/{KEY}-*.md`

Ignore directories that contain only diagrams or artifacts with no plan prose.

List candidates when ambiguous; do not guess.

## Shell helpers

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Resolve plans_dir
if [ -n "${PLANS_DIR:-}" ]; then
  PLANS_DIR="$(cd "$REPO_ROOT" && cd "$PLANS_DIR" && pwd)"
elif [ -f "$REPO_ROOT/.plan-store" ]; then
  PLANS_DIR="$(grep -E '^plans_dir=' "$REPO_ROOT/.plan-store" | head -1 | cut -d= -f2-)"
  case "$PLANS_DIR" in
    /*) ;;
    *) PLANS_DIR="$REPO_ROOT/$PLANS_DIR" ;;
  esac
else
  PLANS_DIR="$REPO_ROOT/docs/plans"
fi

mkdir -p "$PLANS_DIR"
echo "$PLANS_DIR"
```

## Plan directory layout

```
{plans_dir}/
  {TICKET-or-slug}-{short-description}/
    PLAN.md              # authoritative plan
    *.mmd                # optional diagrams during implementation
```

The plan store may live entirely outside the repo; only `.plan-store` (or `PLANS_DIR`)
ties the repo to that location.

# Plan store — directory resolution

Both **create-plan** and **execute-plan** read plans from a single configurable
**plan store directory**. Plans are not required to live inside the repository.

## Resolution order

Apply the first match:

| Priority | Source | Example |
|----------|--------|---------|
| 1 | **Explicit path** from the user in this session | `/home/me/plans/acme/PROJ-42-auth/PLAN.md` |
| 2 | **`PLANS_DIR` environment variable** (may contain `{repo}`) | `export PLANS_DIR=/home/me/plans/{repo}` |
| 3 | **`.plan-store` in the repository root** | `plans_dir=/home/me/plans/acme` |
| 4 | **Ask once, then write `.plan-store`** | First **create-plan** run with no config |
| 5 | **Default** | `<repo-root>/docs/plans` |

Relative paths in `.plan-store` or `PLANS_DIR` resolve from the **repository root**
(`git rev-parse --show-toplevel`).

**`{repo}`** in `PLANS_DIR` or `plans_dir` expands to the repository's directory name (the
main checkout's name, also from inside a linked worktree), so one setting covers every repo:
`PLANS_DIR=~/notes/plans/{repo}` → `~/notes/plans/acme-api` when run in `acme-api`.

**`PLANS_ROOT`** (optional) is a wider tree that is only **searched**, never written to.
Plans for this repo might also live in project folders or `completed*` folders elsewhere
under it. Discovery by ticket key checks `plans_dir` first, then `PLANS_ROOT` recursively.

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
4. **Inside the repo:** when `plans_dir` came from `PLANS_DIR` or `.plan-store` (so it isn't
   the repo default) and 1–3 found nothing, also check the repo's own plan folders: the
   default `<repo-root>/docs/plans`, then any `*plan*.md` tracked in the repo whose path
   contains the key (`git ls-files | grep -i "$KEY" | grep -i plan`). Teams commit plans
   there even when your personal store lives elsewhere.
5. **Wider search:** when `PLANS_ROOT` is set and 1–4 found nothing, every `*plan*.md` under
   it whose path contains the key, case-insensitively:
   `find "$PLANS_ROOT" -iname '*plan*.md' | grep -i "$KEY"`. Prefer a match outside any
   `completed*` folder.

Ignore directories that contain only diagrams or artifacts with no plan prose.

List candidates when ambiguous; do not guess.

## Shell helpers

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Resolve plans_dir ({repo} = the main checkout's directory name)
REPO_NAME="$(basename "$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')")"
if [ -n "${PLANS_DIR:-}" ]; then
  PLANS_DIR="${PLANS_DIR//\{repo\}/$REPO_NAME}"
  case "$PLANS_DIR" in
    /*) ;;
    *) PLANS_DIR="$REPO_ROOT/$PLANS_DIR" ;;
  esac
elif [ -f "$REPO_ROOT/.plan-store" ]; then
  PLANS_DIR="$(grep -E '^plans_dir=' "$REPO_ROOT/.plan-store" | head -1 | cut -d= -f2-)"
  case "$PLANS_DIR" in
    /*) ;;
    *) PLANS_DIR="$REPO_ROOT/$PLANS_DIR" ;;
  esac
  PLANS_DIR="${PLANS_DIR//\{repo\}/$REPO_NAME}"
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
ties the repo to that location. With `PLANS_DIR` set (for example in the shell profile), no
`.plan-store` file is ever written into the repo and no question is asked.

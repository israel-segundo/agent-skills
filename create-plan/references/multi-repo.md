# Multi-repository plans

Tickets often span more than one repository (shared contracts, API + client, infra + app).
Plans must name every involved repo and explore each on an up-to-date default branch.

## When to use

- The ticket mentions multiple services, repos, or deployables.
- Exploration finds imports, protos, or APIs owned by another checkout.
- Rollout requires coordinated merges across repos.

Single-repo plans still list one row in **## Repositories** (the planning repo).

## Repository registry

Add **## Repositories** after **## PR map** when more than one repo is involved (for
single-repo plans, a one-line note under Status is enough).

| Slug | Path | Remote (optional) | Default branch |
|------|------|-------------------|----------------|
| `contracts` | `/home/me/repos/acme-contracts` | `github.com/acme/contracts` | `main` |
| `api` | `/home/me/repos/acme-api` | `github.com/acme/api` | `main` |
| `web` | `/home/me/repos/acme-web` | `github.com/acme/web` | `main` |

**Slug** is what the PR map **Repo(s)** column uses. **Path** is the local absolute path.

## Discovering local checkouts

Probe in order:

1. **User-provided coordinates** — ask when the ticket names sibling repos or the plan
   cannot verify a path.
2. **Sibling directories** — common layout next to the planning repo:

```sh
PLANNING_ROOT="$(git rev-parse --show-toplevel)"
PARENT="$(dirname "$PLANNING_ROOT")"
ls -d "$PARENT"/*/ 2>/dev/null
```

3. **Search by remote or folder name**:

```sh
# Example: find a checkout whose origin URL contains "acme/contracts"
for d in "$HOME/repos"/* "$PARENT"/*; do
  [ -d "$d/.git" ] && git -C "$d" remote get-url origin 2>/dev/null | rg -q 'acme/contracts' && echo "$d"
done
```

4. **Document unknowns** under **To Be Clarified** — do not invent paths.

Record confirmed paths in **## Repositories** before writing PR tasks that reference them.

## Exploration protocol (every repo)

Before reading code in a sibling repo, sync its default branch:

```sh
REPO_PATH="/path/to/sibling"
DEFAULT="$(git -C "$REPO_PATH" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
  | sed 's@^refs/remotes/origin/@@')"
: "${DEFAULT:=main}"

git -C "$REPO_PATH" fetch origin
git -C "$REPO_PATH" checkout "$DEFAULT"
git -C "$REPO_PATH" pull --ff-only origin "$DEFAULT"
```

Then explore **that** branch — not a stale feature branch unless the plan explicitly
targets one.

If `fetch`/`pull` fails (offline, auth, dirty worktree), note the limitation in the plan
and ask the human before proceeding.

## PR map integration

- Each PR map row lists every repo it touches in **Repo(s)**.
- **Depends on** reflects **cross-repo merge order** when contracts must land first.
- **Parallel** is valid when PRs target **different repos** and share no blocking contract
  dependency — e.g. `api` PR 2 and `web` PR 3 both depend on `contracts` PR 1 merged, then
  may run in parallel.

## execute-plan notes

- Phase 2 branch setup runs in the **target repo** for the current PR (change directory or
  open a worktree — do not implement `api` changes from the `web` tree).
- Verification commands are per-repo (read each repo's `CONTRIBUTING.md`).
- Phase 9 updates the PR map row and, when a PR merges, sets status to `MERGED`.

## Planning anti-patterns

- Assuming sibling repo layout without verifying `git remote`.
- Planning against a feature branch while `main` has diverged.
- One PR map row with multiple repos when the work should split (harder to parallelize and
  review) — split unless the change is truly atomic across repos.

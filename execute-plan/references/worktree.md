# Branch and worktree setup (Phase 2)

Each PR slice gets its own branch **and its own worktree**, created from the latest default
branch. One worktree per PR is what lets pr-launch, pr-shepherd, pr-land and pr-runner work on
several PRs at once without stepping on each other (their locks and state live in the
worktree's git dir).

## 1. Resolve the basics

```sh
TARGET_REPO=<path from ## Repositories, or the planning repo>
REMOTE=$(git -C "$TARGET_REPO" remote | head -1); REMOTE=${REMOTE:-origin}
git -C "$TARGET_REPO" remote set-head "$REMOTE" -a >/dev/null 2>&1 || true
DEFAULT=$(git -C "$TARGET_REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" | sed "s|^$REMOTE/||")
REPO_NAME=$(basename "$(git -C "$TARGET_REPO" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')")
ME=$(gh api user -q .login 2>/dev/null || git -C "$TARGET_REPO" config user.name | tr ' A-Z' '-a-z')
```

`KEY` comes from the plan (ticket key), `N` is the PR slice number, `SLUG` is 2–5 lowercase
words from the slice's scope line (`a-z0-9-` only). `TYPE` is the conventional-commit type
that fits the slice (`feat`, `fix`, `chore`, `refactor`, `test`, `docs`).

## 2. Branch name, first match wins

1. **Repo docs** (`CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`, `docs/`) state a convention →
   follow it exactly.
2. **Your own recent branches** show one:
   ```sh
   git -C "$TARGET_REPO" for-each-ref --sort=-committerdate --count=30 \
     --format='%(refname:short)' "refs/remotes/$REMOTE/$ME/" "refs/remotes/$REMOTE/"
   ```
   Infer the shape from the branches that carry a ticket key (for example
   `<login>/<type>/<key-lower>-<slug>[-pr<N>]`) and reuse it, including key case and any
   `-pr<N>` suffix.
3. **Default:** `<login>/<type>/<key-lower>-<slug>-pr<N>`.

Multi-PR plans always carry the slice number somewhere in the name (`-pr<N>`) so pr-land can
match a branch back to its PR-map row.

## 3. Worktree path

```sh
BASE_DIR=${WORKTREES_DIR:-"$(dirname "$TARGET_REPO")/$REPO_NAME-worktrees"}
BASE_DIR=${BASE_DIR//\{repo\}/$REPO_NAME}
WT="$BASE_DIR/$(printf '%s' "$BRANCH" | tr '/' '-')"
```

`WORKTREES_DIR` may contain `{repo}` (for example `~/.worktrees/{repo}`).

## 4. Create, or reuse

```sh
git -C "$TARGET_REPO" fetch "$REMOTE" "$DEFAULT"
git -C "$TARGET_REPO" worktree list --porcelain     # is $BRANCH already checked out somewhere?
```

- **Branch already has a worktree** → reuse it if `git -C "$that" status --porcelain` is empty
  and it isn't behind its own upstream; otherwise **stop** (interactive: ask; unattended:
  BLOCKED). Never reset someone's work.
- **Branch exists, no worktree** → `git -C "$TARGET_REPO" worktree add "$WT" "$BRANCH"`.
- **Neither** → `git -C "$TARGET_REPO" worktree add -b "$BRANCH" "$WT" "$REMOTE/$DEFAULT"`.

Interactive mode shows the branch name and path and asks before creating. Unattended mode
creates them without asking.

If the repo needs per-worktree setup (dependency install, env files copied from the main
checkout, generated code), follow the repo's documented worktree or setup steps once, inside
`$WT`. Never copy secrets that the docs don't say to copy.

## 5. Take the worktree's lock

One implementation run per worktree. Take the lock as soon as the worktree is known, before
any edit, in both modes:

```sh
LOCK="$(git -C "$WT" rev-parse --absolute-git-dir)/execute-plan/lock"
mkdir -p "$(dirname "$LOCK")"
if mkdir "$LOCK" 2>/dev/null; then
  date +%s > "$LOCK/started"
elif [ $(( $(date +%s) - $(cat "$LOCK/started" 2>/dev/null || echo 0) )) -gt 21600 ]; then
  rm -rf "$LOCK" && mkdir "$LOCK" && date +%s > "$LOCK/started"   # stale (>6h): take over
else
  echo "RESULT: NOOP (another execute-plan run is active in $WT)"; exit 0
fi
```

Interactive mode says the same thing in words and stops. **Every exit path removes `$LOCK`**,
including BLOCKED. It lives in the worktree's git dir, so nothing shows up in `git status`,
and pr-runner treats a worktree holding it as busy. Multi-repo slices lock each target
worktree they edit.

## 6. Work there

From here on every command takes `-C "$WT"` or an absolute path under `$WT`. Don't rely on
changing the shell's directory; some hosts reset it and some users' shells hook it.

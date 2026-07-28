---
name: git-rebase
description: >-
  Bring the current branch up to date with the repository's default branch, end to end:
  resolve which remote and which default branch the repo actually uses, stash whatever is
  uncommitted, fetch, rebase, resolve the conflicts that come up, fall back to a merge when
  the rebase turns into a cascade, restore the stash, and report what happened. Resolves
  lockfile conflicts by regenerating the lockfile rather than hand-merging it. Use when a
  branch has fallen behind and you want it synced and conflict-free in one pass, before
  opening or updating a pull request. Only ever updates the local branch — never pushes,
  never force-pushes, and stops rather than guessing when it cannot tell which side of a
  conflict is correct.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git) rather than
    host-specific tools, and degrades gracefully when a capability is absent. If your
    host has no skill support, read this file top to bottom and follow it directly.
when_to_use: >-
  Use when the current feature branch is behind the default branch and you want it caught
  up, including conflict resolution, without thinking about the mechanics. Not for
  rewriting a shared branch and not for squashing history. If a repo ships its own
  git-rebase skill, that one wins: it knows which files in that repo are generated and
  which conflicts have a house rule.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
---

# Git rebase (sync the current branch with the default branch)

Replay this branch's commits on top of the latest default branch, resolving whatever
conflicts that surfaces, and leave the working tree exactly as dirty as it started.

**The defining stance: a rebase you can't finish is worse than a merge you can.** Halfway
through a cascade, with three files re-conflicting on every `--continue`, the honest move is
`--abort` and a merge commit — not another round of guessing. Step 4 names the exact
condition that triggers the switch, so the decision isn't left to stamina.

**Plain language and short.** Your reader is a colleague, not a linter. Say "the lockfile
conflicted, so I regenerated it from the merged manifest" rather than "dependency graph
resolution was reconciled via canonical regeneration". If a sentence has three qualifiers
stacked up, cut two.

### Guardrails (they apply throughout)

- **Never push, and never force-push.** A rebase rewrites this branch's commits, so the
  eventual push needs `--force-with-lease` — say so and let the user run it. Not all hosts
  prompt before running commands; assume none do.
- **Never rebase the default branch itself,** and never rebase a branch that other people
  are working on without explicit confirmation. Rewriting commits someone else has pulled
  is their problem to accept, not yours to create.
- **Resolve conflicts, don't erase them.** Picking a side wholesale to make the error go
  away is how a feature silently loses half of itself. When you genuinely can't tell which
  side is right, stop and ask — that's a supported outcome, not a failure.
- **Never drop a stash.** `git stash pop` on a conflict leaves the stash in place on
  purpose. Don't `git stash drop` to tidy up.
- **Don't touch anything you weren't asked to touch.** No amending, no branch deletion, no
  garbage collection, no config changes.
- **Every git call carries `-C "$REPO"`,** so nothing depends on the shell's working
  directory and the skill behaves the same however the host invokes it.

---

## Step 0 — Set up and resolve what "up to date" means here

```sh
command -v git                                   # required; without it, stop
REPO=$(git rev-parse --show-toplevel) || exit    # not a work tree → stop and say so
WORK=$(mktemp -d)                                # notes and conflict lists live here
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
```

**Never assume `origin` or `main`.** Resolve both:

```sh
UPSTREAM=$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
REMOTE=${UPSTREAM%%/*}; REMOTE=${REMOTE:-$(git -C "$REPO" remote | head -1)}
git -C "$REPO" remote set-head "$REMOTE" -a >/dev/null 2>&1 || true   # populate the ref if missing
DEFAULT=$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s|^$REMOTE/||")
[ -n "$DEFAULT" ] || DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
```

If neither route yields a default branch, **ask the user which branch to sync against** — do
not fall back to a guess. If there's no remote at all, say so and stop.

Also note whether the repo has a package manager whose lockfile you may need to regenerate
in Step 4 (`ls` for `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `Cargo.lock`,
`poetry.lock`, `uv.lock`, `Gemfile.lock`, `go.sum`, `composer.lock`).

## Step 1 — Pre-flight

```sh
git -C "$REPO" status --porcelain
```

- If `$BRANCH` is `$DEFAULT`, stop: "you're already on the default branch — nothing to
  rebase."
- If a rebase, merge, cherry-pick, or bisect is already in progress, stop and explain.
  Finish or abort it first; starting another operation on top corrupts both.
- If HEAD is detached, stop and say so.
- Record whether there are uncommitted changes. Step 2 and Step 6 both depend on it — write
  the answer to `$WORK/had-changes` so it survives however the host runs the later steps.

## Step 2 — Stash, if the tree is dirty

```sh
git -C "$REPO" stash push -u -m "git-rebase skill: auto-stash before sync"
git -C "$REPO" stash list | head -3           # confirm it landed, and note the stash ref
```

`-u` includes untracked files, which is usually what the user means by "my changes" — but it
also means an untracked build directory gets stashed. Mention what went in.

If the stash command reports nothing to stash, treat the tree as clean and carry on.

## Step 3 — Fetch

```sh
git -C "$REPO" fetch "$REMOTE" "$DEFAULT"
git -C "$REPO" log --oneline "HEAD..$REMOTE/$DEFAULT" | head -20     # what's coming in
git -C "$REPO" log --oneline "$REMOTE/$DEFAULT..HEAD" | head -20     # what's being replayed
```

If nothing is coming in, the branch is already current — skip to Step 6 and say so.

## Step 4 — Rebase

```sh
git -C "$REPO" rebase "$REMOTE/$DEFAULT"
```

**If it succeeds,** go to Step 6.

**If it stops on conflicts,** work the loop:

1. List what's conflicted:
   ```sh
   git -C "$REPO" diff --name-only --diff-filter=U
   ```
2. Open each conflicted file and read the markers — use whatever file-reading the host
   provides; `git -C "$REPO" diff --diff-filter=U` and `cat` are the portable fallback.
3. Resolve it. The heuristics, in order of how much they're worth:
   - **Lockfiles: don't hand-merge.** Reset the file to the version from `$DEFAULT`, then
     regenerate it from the merged manifest with the repo's own package manager (`npm
     install --package-lock-only`, `pnpm install --lockfile-only`, `cargo
     generate-lockfile`, `poetry lock --no-update`, `go mod tidy`, `bundle lock`). A
     hand-merged lockfile resolves cleanly and installs wrong.
     ```sh
     git -C "$REPO" checkout --ours -- <lockfile>     # mid-rebase, --ours is $DEFAULT
     ```
     **Mind the inversion.** Mid-rebase, `--ours` is the branch you're replaying *onto*
     (`$DEFAULT`) and `--theirs` is your own commit. In a merge (Step 5) it's the other way
     round. It reads backwards and catches everyone once — check which operation you're in
     before you pick a side.
   - **Generated or vendored files** — regenerate rather than merge, same reasoning.
   - **Your feature's own code** — keep your side, but re-apply any API change that arrived
     from `$DEFAULT`. This is the case where a wholesale side-pick quietly breaks things.
   - **A file both sides genuinely edited** — merge by hand, keeping both intents.
4. Stage each resolved file by name: `git -C "$REPO" add -- <file>`.
5. Continue — and **suppress the editor**, or this is where the skill hangs:
   ```sh
   git -C "$REPO" -c core.editor=true rebase --continue
   ```
   `rebase --continue` opens the commit-message editor after a conflict resolution. With no
   terminal to answer it, git waits forever. `-c core.editor=true` accepts the existing
   message and moves on.
6. New conflicts → back to 1.

**Switch to a merge when any of these is true** — these are the stop conditions, so you
don't grind:

- the same file conflicts on three consecutive `--continue` steps,
- you can't tell which side is correct and there's no rule above that decides it,
- or the resolution would mean rewriting logic rather than reconciling two edits.

```sh
git -C "$REPO" rebase --abort          # back to exactly where Step 4 started
```

Then go to Step 5. Say plainly why you switched — "six commits each re-conflicting in the
same file, so a merge is the honest outcome here" is a fine reason.

## Step 5 — Merge fallback (only after an abort)

```sh
git -C "$REPO" merge --no-edit "$REMOTE/$DEFAULT"
```

Resolve any conflicts exactly as in Step 4 — except the sides are no longer inverted here:
`--ours` is your branch, `--theirs` is `$DEFAULT`. Then continue, editor suppressed for the
same reason as Step 4:

```sh
git -C "$REPO" -c core.editor=true merge --continue
```

Accept the default merge commit message; don't author a custom one.

## Step 6 — Restore the stash

Only if Step 1 recorded uncommitted changes:

```sh
git -C "$REPO" stash pop
```

If the pop conflicts, resolve it the same way, stage the files, and **leave the stash
entry alone** — git keeps it precisely because the pop didn't fully apply. Tell the user the
stash is still there and how to drop it once they're happy.

## Step 7 — Report

```sh
git -C "$REPO" status
git -C "$REPO" log --oneline -8
```

A few lines, plain: rebase or merge and why, how many conflicts you resolved and in which
files, anything you regenerated, whether the stash came back cleanly, and where the branch
sits relative to `$REMOTE/$DEFAULT`.

Then state the push and stop: a rebased branch needs
`git push --force-with-lease "$REMOTE" "$BRANCH"`, never a bare `--force`. A merged branch
needs an ordinary push. **Don't run either.**

---

## Principles

- **A finishable merge beats an unfinishable rebase.** Abort on the named stop conditions
  instead of grinding, and say why you switched.
- **Never assume `origin` or `main`.** Resolve the remote and the default branch, and ask
  rather than guess when they can't be resolved.
- **Regenerate what's generated.** Lockfiles and build output get rebuilt from the merged
  source, never hand-merged — a hand-merged lockfile resolves cleanly and installs wrong.
- **`--ours` and `--theirs` invert mid-rebase.** Check which operation you're in before
  picking a side; this catches everyone once.
- **Suppress the editor on every `--continue`.** Git opens one after a conflict resolution,
  and with no terminal to answer it the whole skill hangs. `-c core.editor=true`.
- **Don't pick a side to make the error go away.** That's how a feature loses half of
  itself. If no rule decides it, stop and ask.
- **The tree ends as dirty as it started.** Stash on the way in, pop on the way out, never
  drop a stash that didn't fully apply.
- **Never push.** The skill's job ends at the local branch; name the push it needs.
- **Plain language, always — and short.** Say what conflicted and what you did about it. If
  it reads like a generated report, rewrite it.
- **Stop on anything unexpected.** Detached HEAD, an operation already in progress, dirty
  submodules, no remote — explain the situation instead of working around it.

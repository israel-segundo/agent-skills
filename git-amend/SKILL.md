---
name: git-amend
description: >-
  Fold the current working-tree changes into the most recent commit, so an iterative review
  cycle ends as one clean commit instead of a trail of "address review comment" commits.
  Stages only the files that belong — by name, never `git add -A` — leaves generated output
  alone, refuses to stage anything that looks like a secret, then rewrites the commit
  message with an `## Amendments` round listing each file and what changed in it. Fetches and
  checks whether the commit is already published — and whether it is still the tip of its own
  remote branch — before rewriting it, and says what the next push will need. Use when you have just made review fixes on top of a commit you own and want
  them absorbed into it rather than stacked on top of it. Never pushes, never force-pushes,
  and stops to ask before rewriting a commit that anyone else could already have pulled.
license: Unlicense
metadata:
  version: "1.1.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git) rather than
    host-specific tools, and degrades gracefully when a capability is absent. If your
    host has no skill support, read this file top to bottom and follow it directly.
when_to_use: >-
  Use during a review cycle on a branch you own, when the fixes belong inside the previous
  commit rather than after it. Not for squashing several commits together (that's an
  interactive rebase) and not for anything on a shared or default branch. If a repo ships
  its own git-amend skill, that one wins: it knows the repo's commit conventions.
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# Git amend (fold review fixes into the last commit)

Take what's in the working tree and absorb it into `HEAD`, then update that commit's message
to record what moved. The point is a readable history: one commit that says what it does,
rather than that commit followed by four commits called "fix review comment".

**The defining stance: an amend rewrites history, so know whose history you're rewriting
before you do it.** On an unpushed commit it's free. On a commit that's already on your own
feature branch upstream it costs a `--force-with-lease`. On a commit anyone else may have
pulled it costs them a conflict, and you don't get to make that call for them. And on a
commit that *isn't the tip of its own remote branch*, the force-push costs you every remote
commit after it — silently, with nothing conflicting. Step 0 establishes which case you're
in, and everything after it is conditional on the answer.

**Plain language and short.** Your reader is a colleague, not a linter. The per-file
summaries you write into the commit message are ten words each, in everyday words — "fix
typo in error message", not "remediate lexical defect in diagnostic output". If a sentence
has three qualifiers stacked up, cut two.

### Guardrails (they apply throughout)

- **Never push, and never force-push.** This skill only ever rewrites the local commit. It
  tells the user what push the amend will need and stops there.
- **Never amend a commit on the default branch, or one that's on a remote branch other than
  this branch's own upstream, without explicit confirmation.** Not all hosts prompt before
  running commands — assume none do.
- **Never `git add .` or `git add -A`.** Stage by name, every time. A blanket add is how an
  unrelated file, a build artifact, or a credential ends up in someone's history.
- **Never stage anything that looks like a secret**, even if the user asks. `.env*`,
  `*.pem`, `*.key`, `*_rsa`, `credentials*`, `*.p12`, `*.keystore`. Say you skipped it.
- **Don't touch anything you weren't asked to touch.** No rebase, no reset, no branch
  changes, no stash. If the tree isn't in a state you can amend from, stop and explain it.
- **Every git call carries `-C "$REPO"`,** so nothing depends on the shell's working
  directory and the skill behaves the same however the host invokes it.

---

## Step 0 — Set up, and find out whose history this is

```sh
command -v git                                   # required; without it, stop
REPO=$(git rev-parse --show-toplevel) || exit    # not a work tree → stop and say so
WORK=$(mktemp -d)                                # commit message drafts live here
git -C "$REPO" rev-parse --verify HEAD           # no commit yet → nothing to amend, stop
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
```

Then resolve the remote and the default branch — **never assume `origin` or `main`:**

```sh
UPSTREAM=$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
REMOTE=${UPSTREAM%%/*}; REMOTE=${REMOTE:-$(git -C "$REPO" remote | head -1)}
git -C "$REPO" remote set-head "$REMOTE" -a >/dev/null 2>&1 || true   # populate the ref if missing
DEFAULT=$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s|^$REMOTE/||")
[ -n "$DEFAULT" ] || DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
git -C "$REPO" fetch "$REMOTE" "$BRANCH" 2>/dev/null || true   # may not exist on the remote yet
TRACKING=${UPSTREAM:-$REMOTE/$BRANCH}
git -C "$REPO" branch -r --contains HEAD          # which remote branches already have this commit
git -C "$REPO" rev-parse --verify --quiet "refs/remotes/$TRACKING" >/dev/null \
  && git -C "$REPO" rev-list --left-right --count "HEAD...$TRACKING"   # prints "<ahead> <behind>"
```

**Fetch before you judge any of this.** Remote-tracking refs are only as fresh as the last
fetch, and this worktree may never have fetched since the branch was pushed from somewhere
else. Without it, "nothing contains this commit — unpushed, amend freely" is a conclusion
drawn from a stale ref about a commit that has been on the remote for days.

**`--contains` answers "is it *in* the branch", not "is it the *tip*".** That difference is
the whole hazard: a commit two behind the tip is still "contained by `$TRACKING`", which
reads as the ordinary review-cycle case — so you amend it and force-push, and the two newer
remote commits are gone. The `rev-list` counts are what separate the two, so read them
before deciding.

Decide from all three outputs, and say out loud which case you're in:

- **behind > 0 — `HEAD` is not the branch tip. Stop.** The remote branch has commits your
  local branch doesn't, so `HEAD` is not the commit a reviewer is looking at, and the
  force-push an amend requires would delete everything after it. Don't amend, and don't move
  the branch yourself — that's outside this skill. Show what's missing and hand it back:
  ```sh
  git -C "$REPO" log --oneline "HEAD..$TRACKING"     # what the local branch is missing
  ```
  If local is *strictly* behind (ahead = 0), the fix is usually `git -C "$REPO" merge
  --ff-only "$TRACKING"` and then re-running this skill — the commit they meant to amend is
  the tip they don't have yet. If it's **diverged** (ahead > 0 and behind > 0), say so and
  stop there; sorting out a diverged branch is `/git-rebase`'s job, not this one.
- **Nothing contains it** (and not behind) — unpushed. Amend freely; the next push is an
  ordinary one.
- **Only `$TRACKING` contains it, and `HEAD` is its tip** — normal review-cycle case. Amend,
  and tell the user the next push needs `--force-with-lease`.
- **`$REMOTE/$DEFAULT` contains it, or any branch that isn't `$TRACKING`** — **stop.** This
  is shared history. Explain that amending would rewrite a commit other people may have
  pulled, and offer a new commit on top instead. Only proceed on explicit confirmation.

If `$DEFAULT` can't be resolved and there's no `gh`, say so and treat the commit as shared —
the cautious reading, not the convenient one.

## Step 1 — Check there's something to amend

```sh
git -C "$REPO" status --porcelain
```

Empty output → stop with "nothing to amend — the working tree is clean". If everything is
already staged and nothing is unstaged, skip to Step 3.

Also stop if a merge, rebase, cherry-pick, or bisect is in progress (`git -C "$REPO"
status` says so plainly). Amending mid-operation corrupts the operation; finish or abort it
first.

## Step 2 — Stage the files that belong

Read the porcelain output and pick the files by hand. Everything in `.gitignore` is already
absent from that list, so the real risks are the two things ignore rules miss: a **tracked**
file that's actually generated, and an **untracked build directory nobody ignored yet**.

Leave out, and say which you left out:

- dependency and build output — `node_modules/`, `vendor/`, `target/`, `dist/`, `build/`,
  `out/`, `bin/`, `obj/`, `.next/`, `_build/`, `__pycache__/`, `*.pyc`, `*.class`, `*.o`
- caches and incremental state — `.cache/`, `.turbo/`, `.gradle/`, `.pytest_cache/`,
  `*.tsbuildinfo`, `coverage/`
- logs, dumps, editor and OS noise — `*.log`, `*.tmp`, `.DS_Store`, `*.swp`
- **anything matching a secret pattern** (see Guardrails) — refuse these outright

A lockfile is a judgment call: stage it when this change moved dependencies, leave it when
it drifted in from something else. Say which you decided and why.

```sh
git -C "$REPO" add -- path/to/one.ext path/to/two.ext      # by name, always
```

If nothing survives the filter, stop with "no meaningful changes to amend — only generated
files in the tree".

## Step 3 — Read the current message

```sh
git -C "$REPO" log -1 --format=%B > "$WORK/original-msg"
```

Split it into the **subject** (first line) and the **body** (everything after the first
blank line). The subject is never touched.

## Step 4 — Build the new message

For each staged file, look at what actually changed and write it up in ten words or fewer:

```sh
git -C "$REPO" diff --cached --stat
git -C "$REPO" diff --cached -- path/to/one.ext
```

Write the full message to a file — state crosses steps through disk, not through context:

```
<original subject, unchanged>

<original body, if there was one>

## Amendments

### Round 1
- `path/to/one.ext` — short description of what changed
- `path/to/two.ext` — short description of what changed
```

If an `## Amendments` section already exists, keep it and append the next `### Round N`
below the last one. Never renumber or rewrite an earlier round.

## Step 5 — Amend

```sh
git -C "$REPO" commit --amend -F "$WORK/new-msg"
```

Pass the message with `-F` and a real file. Don't build it inline: a heredoc inside command
substitution is the most fragile construct in this whole skill, and it breaks differently on
every host.

If a commit hook rejects the amend, report the hook's output verbatim and stop — don't retry
with the hook disabled.

## Step 6 — Confirm, and hand the push back

```sh
git -C "$REPO" log -1 --stat
```

Report, in a few lines: how many files were folded in, which files you deliberately left
out, and the new message. Then state the push the user will need, and don't run it:

- unpushed commit → `git push "$REMOTE" "$BRANCH"`
- already on its upstream → `git push --force-with-lease "$REMOTE" "$BRANCH"`, never a bare
  `--force`

`--force-with-lease` is not a safety net against the Step 0 hazard, so don't present it as
one: its lease is the remote-tracking ref, and if you fetched in Step 0 that ref already
matches the remote, so the push proceeds and takes the newer commits with it. Step 0 is the
only thing standing between an amend and that outcome.

Mention `$WORK` if they might want the drafts; otherwise leave it for the OS to clean up.

---

## Principles

- **Know whose history you're rewriting.** Unpushed is free, your own upstream costs a
  `--force-with-lease`, shared costs someone else a conflict — and that one isn't yours to
  decide.
- **Amend the tip, or don't amend.** Fetch first, then confirm `HEAD` *is* the tip of its
  remote branch, not merely contained by it. `--contains` says yes to a commit ten behind the
  tip, and the force-push that follows deletes those ten. `--force-with-lease` won't stop it.
- **Stage by name.** `git add -A` is how artifacts and credentials get into history.
  Explicit paths make the mistake visible before it's permanent.
- **Say what you left out.** A file you silently skipped looks identical to a file you
  forgot. Name them.
- **Never push.** The skill's job ends at the commit; tell the user which push it needs.
- **Subjects are stable, bodies accumulate.** The subject line still describes the commit;
  the `## Amendments` rounds are the audit trail of how it got there.
- **Write the message to a file.** Inline multi-line messages break across hosts; `-F`
  never does.
- **Plain language, always — and short.** Ten words per file, everyday words. If it reads
  like a generated report, rewrite it.
- **Stop on anything unexpected.** Mid-rebase, detached HEAD, a rejecting hook, an
  unresolvable default branch — explain the situation instead of working around it.

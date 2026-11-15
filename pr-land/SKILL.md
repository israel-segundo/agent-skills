---
name: pr-land
description: >-
  Land your own approved PR and close out after it, unattended: confirm it is approved,
  green and mergeable with no feedback newer than the approval, merge it the way the repo
  merges (merge queue, or its allowed method), wait until it is actually merged, mark the
  slice MERGED in a local plan, move the ticket to Done when it was the plan's last slice,
  remove the worktree and branch, and print which plan slice is now unblocked. Invoking it
  authorizes that run's merge, cleanup, plan edit and ticket update. Never uses admin
  overrides. Stops to ask only on a blocker. Ends with parseable NEXT and RESULT lines. Use
  when a PR you authored has been approved and should merge without you clicking anything.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git/gh/jq) rather than
    host-specific tools. Depends on the sibling skills pr-checks-green (its wait-checks.sh),
    jira-transition and jira-update-issue; if your host has no skill support, read each
    SKILL.md where this file says to and follow it with the overrides stated here.
when_to_use: >-
  Use in the worktree of a PR you authored once reviewers approved it, by hand or from
  pr-runner. Not for PRs that still have feedback (pr-shepherd), not for someone else's PR,
  and never to bypass required reviews or checks.
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
---

# PR land (approved → merged → cleaned up)

One run: preflight → merge → wait for merged → plan → ticket → cleanup → report.

**Merging is the one step here that can't be taken back, so the preflight is strict.** Every
condition must hold on the live PR, read in this run. Anything short of that is a NOOP (come
back later) or a BLOCKED (a human must look), never a workaround.

**Plain language and short** in every comment and report line.

### What invoking this skill authorizes (for this run, on this PR only)

- merging the PR, or adding it to the repo's merge queue, with the repo's own method
- updating a behind branch with its base through GitHub (`gh pr update-branch`), when the
  repo has no merge queue
- deleting the PR's branch (remote, via the merge; and local) and removing its worktree
- editing the branch's plan when it lives outside the repo
- one Jira transition to done, and one short Jira comment, only when this was the last slice

It does **not** cover: `--admin` or any bypass of required reviews/checks, force pushes,
merging any other PR, editing an in-repo plan (its PR already carried the update), filing
tickets, or reopening/transitioning anything backwards.

### Blockers

`RESULT: BLOCKED` (release the lock, leave everything as is) for:

- the merge queue rejects the PR, or a merge attempt fails for a reason that isn't "not yet"
- the PR is still not merged after `PR_LAND_TIMEOUT` minutes (default 90)
- the worktree has uncommitted changes when cleanup starts (merge stands; cleanup skipped)

### Progress checklist

Stages: 1 Preflight · 2 Merging · 3 Waiting for merge · 4 Updating the plan · 5 Updating the
ticket · 6 Cleaning up. Same rules as pr-shepherd's checklist: one `in_progress` at a time,
live detail in the label, skipped stages `completed` with the reason, a blocked stage stays
`in_progress` with `(BLOCKED: …)`. Headless: one line per transition.

`$SKILL_DIR` is the directory this file was loaded from (fallbacks
`~/.agents/skills/pr-land` or the host's own skills directory). Sibling skills live at
`$SKILL_DIR/../<name>/`.

---

## Step 0: Lock and preflight (read-only)

```sh
command -v git gh jq && gh auth status >/dev/null
REPO=$(git rev-parse --show-toplevel) || exit
STATE="$(git -C "$REPO" rev-parse --absolute-git-dir)/pr-land"
mkdir -p "$STATE"; LOCK="$STATE/lock"
mkdir "$LOCK" 2>/dev/null || { echo "RESULT: NOOP (another pr-land run is active here)"; exit 0; }
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
ME=$(gh api user -q .login)
gh pr view --json number,url,state,isDraft,author,reviewDecision,mergeStateStatus,mergeable,headRefOid,baseRefName > "$STATE/pr.json"
PR=$(jq -r .number "$STATE/pr.json"); HEAD_OID=$(jq -r .headRefOid "$STATE/pr.json"); BASE=$(jq -r .baseRefName "$STATE/pr.json")
```

Every exit removes `$LOCK`. Then, in order, the first that fails decides:

| Check | Fails → |
|---|---|
| an open PR for `$BRANCH`, authored by `$ME` | none open, but a **merged** PR of yours for this branch (`gh pr list --head "$BRANCH" --state merged --author @me`) → it was merged by hand: skip to **Step 3** (plan, ticket, cleanup only). Neither → `NOOP (no open PR of yours on this branch)` |
| `isInMergeQueue` (from the activity query below) is true | skip to Step 2 (already queued; just wait) |
| not a draft | `NOOP (draft)` |
| `reviewDecision == APPROVED` | `NOOP (not approved yet)` |
| no human feedback newer than the latest approval (below) | `NOOP (new feedback after approval; pr-shepherd)` |
| checks green on `headRefOid` (below) | pending → `NOOP (checks still running)`; failing → `NOOP (checks failing; pr-shepherd)` |
| `mergeStateStatus` in `CLEAN`, `HAS_HOOKS`, `UNSTABLE` with only non-required checks failing | `BEHIND` → with a merge queue, carry on (the queue tests against the latest base); without one, `gh pr update-branch "$PR"` and `NOOP (updated with base; checks rerunning)`. `DIRTY` → `NOOP (conflicts; pr-shepherd)`. `BLOCKED` → `NOOP (GitHub reports merge blocked: required review, conversation or check)`. `UNKNOWN` → `NOOP (GitHub still computing mergeability)` |

**Feedback newer than the approval:**

```sh
gh api graphql -F owner='{owner}' -F name='{repo}' -F n="$PR" -f query='
query($owner:String!,$name:String!,$n:Int!){ repository(owner:$owner,name:$name){
  pullRequest(number:$n){
    isInMergeQueue
    reviews(last:50){ nodes{ state submittedAt author{ login __typename } } }
    comments(last:50){ nodes{ createdAt author{ login __typename } } }
    reviewThreads(last:100){ nodes{ comments(last:1){ nodes{ createdAt author{ login __typename } } } } }
}}}' > "$STATE/activity.json"
```

`APPROVED_AT` = the newest `APPROVED` review's `submittedAt`. Any review, comment or thread
comment after it whose author is not `$ME` and not a bot (`__typename == "Bot"` or a login
ending in `[bot]`) counts as new feedback.

**Checks:** one bounded call, no fixing:

```sh
"$SKILL_DIR/../pr-checks-green/scripts/wait-checks.sh" "$HEAD_OID" --pr "$PR" --max-wait 60 --grace 30
```

Exit 0 or 3 (no CI) → green. 8 → pending. 1 → failing. 4 → `NOOP (PR head moved)`.

## Step 1: Merge

▸ **Stage 2.** Learn how this repo merges, first match wins:

1. **Merge queue on the base branch:**
   ```sh
   gh api graphql -F owner='{owner}' -F name='{repo}' -F b="$BASE" \
     -f query='query($owner:String!,$name:String!,$b:String!){repository(owner:$owner,name:$name){mergeQueue(branch:$b){id}}}' \
     -q '.data.repository.mergeQueue.id'
   ```
   Non-empty → `gh pr merge "$PR"` (enqueues; the queue owns the method). Add
   `--delete-branch` only if the repo doesn't auto-delete head branches.
2. **Repo docs** (`CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`, the PR template) naming a
   method → use it.
3. **The only allowed method:**
   `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge`.
   Several allowed and no docs → `--squash`.

`gh pr merge "$PR" --<method> [--delete-branch]`. Never `--admin`. A refusal that says
"not yet" (checks or reviews still pending) → `NOOP`; anything else → **BLOCKED** with the
message.

## Step 2: Wait until merged

▸ **Stage 3.** Poll in bounded calls (≤ ~9 minutes each, every 30 seconds), up to
`PR_LAND_TIMEOUT` minutes in total:

```sh
gh api graphql -F owner='{owner}' -F name='{repo}' -F n="$PR" \
  -f query='query($owner:String!,$name:String!,$n:Int!){repository(owner:$owner,name:$name){pullRequest(number:$n){state mergedAt isInMergeQueue mergeCommit{oid}}}}' \
  -q '.data.repository.pullRequest'
```

- `state == MERGED` → record `mergedAt` and the merge commit; go on.
- `OPEN` and not in the queue after it was enqueued → the queue dropped it. Find the failing
  run (`gh run list --event merge_group -L 5 --json conclusion,url,headBranch,createdAt`) →
  **BLOCKED** with its link.
- Timeout → **BLOCKED** (still queued/pending, with the queue position if shown).

## Step 3: Plan

▸ **Stage 4.** Find the branch's plan the way pr-shepherd's Step 5 does (ticket key from the
branch; in-repo plan doc, then `$PLANS_DIR` with `{repo}` expanded, then `$PLANS_ROOT`
recursively, then `.plan-store`, then any plan location the user's agent instructions name;
prefer a path containing the key and not under a completed folder).

- **In-repo plan** → touch nothing. Its PR already set this row to `MERGED` (option b), and
  that change is now on the default branch.
- **Plan outside the repo** → in the PR map, find this slice's row (the one whose PR link is
  this PR's URL; else the row whose number matches the branch's `pr<N>` suffix; a plan with no
  PR map keeps the status in its `### PR N: … -- **STATUS**` heading instead). Set Status
  `MERGED`, keep the PR link, and update the plan's **Last updated**. If no row is left
  `PENDING`, `IN PROGRESS`, `IN REVIEW` or `COMPLETED` (ignoring `DEFERRED`), set Overall to
  complete, and if the plan's parent folder has a sibling folder whose name starts with
  `completed` (any case), move the plan's own folder (or the file, when it isn't in a
  per-ticket folder) into it.
- No plan, or ambiguous → skip and say so.

Record `LAST_SLICE=1` when no row is left to ship, and compute **NEXT**: the lowest-numbered
`PENDING` row whose **Depends on** rows are all `MERGED` (or `—`). Read an in-repo plan from
the default branch's new head (`git -C "$REPO" fetch` then `git show <remote>/<base>:<path>`).

## Step 4: Ticket

▸ **Stage 5.** Only when `LAST_SLICE=1`, or when there's no plan and the ticket has no other
open PR (`gh pr list --search "<KEY> in:title,body" --state open`):

1. Write a two-line comment to a file: what merged (PR link, one clause), and that the
   ticket is done.
2. Run **jira-transition** with `--to done --comment-file <file>`; this run authorizes it.
   NOOP or a missing transport is fine, note it.

Otherwise skip: other slices are still coming.

## Step 5: Cleanup

▸ **Stage 6.** Last, because it removes the directory this run started in.

```sh
MAIN=$(git -C "$REPO" worktree list --porcelain | awk '/^worktree /{print $2; exit}')
WT=$(git -C "$REPO" rev-parse --show-toplevel)
```

- `$WT == $MAIN` (not a linked worktree) → `git -C "$MAIN" switch <base>`,
  `git -C "$MAIN" pull --ff-only`, then delete the branch.
- Linked worktree, clean (`status --porcelain` empty) →
  `git -C "$MAIN" worktree remove "$WT"`, then `git -C "$MAIN" branch -D "$BRANCH"` (safe:
  GitHub says the PR is merged, and squash merges aren't ancestors), then
  `git -C "$MAIN" fetch --prune`.
- Dirty → leave it, say which files, and finish as **BLOCKED** (the merge itself stands).

## Step 6: Report and release

A few plain lines: merge link and method (or queue), plan change (path) or why skipped,
ticket transition, cleanup. Remove `$LOCK` (it lived in the removed worktree's git dir, so
removing that is fine). The last two lines are always:

```
NEXT: <plan path> PR <n>        (or: NEXT: none)
RESULT: DONE | NOOP (<why>) | BLOCKED (<what you need>)
```

## Principles

- **Strict preflight, no overrides.** Approved, green, mergeable, nothing new since the
  approval. GitHub's own merge state is the judge of required reviews and conversations.
- **Merge the repo's way.** Queue if there is one, the repo's method otherwise.
- **Merged means GitHub says MERGED.** Never clean up on a merge that hasn't happened.
- **In-repo plans travel with their PR.** Only plans outside the repo are edited here.
- **Done only when the last slice lands.** Earlier slices leave the ticket alone.
- **Clean up last, and only what's clean.**

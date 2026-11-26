# Closeout after the merge (Steps 6–8)

Runs only once GitHub reports the PR `MERGED`. Never on a merge that hasn't happened.

## Step 6: Plan

Find the branch's plan the way pr-shepherd's Step 5 does: the ticket key from the branch;
in-repo plan doc, then `$PLANS_DIR` with `{repo}` expanded, then `$PLANS_ROOT` recursively,
then `.plan-store`, then any plan location the user's agent instructions name. Prefer a path
that contains the key and isn't under a completed folder.

- **In-repo plan** → touch nothing. Its PR already set this slice's row to `MERGED`
  (pr-launch's in-repo rule), and that change is now on the default branch.
- **Plan outside the repo** → in the PR map, find this slice's row: the one whose PR link is
  this PR's URL; else the row whose number matches the branch's `pr<N>` suffix. A plan with
  no PR map keeps the status in its `### PR N: … -- **STATUS**` heading instead. Set the
  status to `MERGED`, keep the PR link, and update the plan's **Last updated**.
  - If no row is left `PENDING`, `IN PROGRESS`, `IN REVIEW` or `COMPLETED` (ignoring
    `DEFERRED`), set Overall to complete. If the plan's parent folder has a sibling folder
    whose name starts with `completed` (any case), move the plan's own folder (or the file,
    when it isn't in a per-ticket folder) into it.
- **No plan, ambiguous, or no row for this PR** (a follow-up PR the plan never listed) →
  skip and say so. Don't add rows to someone's plan.

Record `LAST_SLICE=1` when no row is left to ship, and compute **NEXT**: the lowest-numbered
`PENDING` row whose **Depends on** rows are all `MERGED` (or `—`). Read an in-repo plan from
the default branch's new head (`git fetch`, then `git show <remote>/<base>:<path>`).

## Step 7: Ticket

Only when `LAST_SLICE=1`, or when there's no plan and the ticket has no other open PR
(`gh pr list --repo "$NWO" --search "<KEY> in:title,body" --state open`):

1. Write a two-line comment to a file: what merged (PR link, one clause), and that the
   ticket is done.
2. Run **jira-transition** with `--to done --comment-file <file>`; this run authorizes it.
   A NOOP (for example the ticket sits in a testing status the workflow won't skip) or a
   missing Jira transport is fine; note it.

Otherwise skip: other slices are still coming.

## Step 8: Cleanup

Only when this run is inside a local checkout of the PR's repository, and only for the PR's
own head branch. Last, because it can remove the directory the run started in. Skip all of it
with `--no-cleanup`.

```sh
REPO=$(git rev-parse --show-toplevel 2>/dev/null) || REPO=""
MAIN=$(git -C "$REPO" worktree list --porcelain | awk '/^worktree /{print $2; exit}')
HEAD_BRANCH=$(jq -r .headRefName "$RUN/start.json")
WT=$(git -C "$MAIN" worktree list --porcelain | awk -v b="refs/heads/$HEAD_BRANCH" '
  /^worktree /{ p=substr($0,10) } $0 == "branch " b { print p; exit }')
```

- No local checkout of the PR's repo, or no local branch named `$HEAD_BRANCH` → skip, say so.
- The branch is checked out in the **main** checkout (`$WT == $MAIN`) → if `status --porcelain`
  is empty: `git -C "$MAIN" switch <base>`, `git -C "$MAIN" pull --ff-only`, then
  `git -C "$MAIN" branch -D "$HEAD_BRANCH"`.
- The branch is checked out in a **linked worktree**, clean →
  `git -C "$MAIN" worktree remove "$WT"`, then `git -C "$MAIN" branch -D "$HEAD_BRANCH"`.
- The branch exists but isn't checked out → `git -C "$MAIN" branch -D "$HEAD_BRANCH"`.
- Then `git -C "$MAIN" fetch --prune`.
- **Dirty** (uncommitted changes to tracked files) → leave it, name the files, and finish as
  `BLOCKED (merged; cleanup skipped: <worktree> has uncommitted changes)`. The merge stands.

`branch -D` is safe here because GitHub says the PR merged, and a squash merge is never an
ancestor of the branch, so `-d` would refuse.

---
name: pr-queue-for-merge
description: >-
  Take your own approved PR all the way to merged and closed out, unattended. Puts it in the
  base branch's merge queue (or merges it the repo's way when there is no queue), then watches
  the queue entry and every check on the merge-group commit every 30 seconds. When a check
  fails or hangs it takes the PR out of the queue, reads the failure, and re-queues only what
  the evidence proves flaky (an infrastructure failure, or a test the diff can't reach that
  passed on an equivalent tree); anything else stops with links. Once merged it marks the
  slice MERGED in a plan outside the repo, moves the ticket to Done on the last slice, and
  removes the branch and worktree. Takes a PR number or URL, or the current branch's PR. Ends
  with NEXT and RESULT lines. Use when an approved PR should merge without you watching it.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git/gh/jq) rather than
    host-specific tools. Polling runs through scripts/watch-queue.sh in bounded calls, so a
    host that caps command duration loops it, and a host with a background monitor streams its
    events. Uses the sibling skills pr-checks-green (its wait-checks.sh) and jira-transition;
    if your host has no skill support, read each SKILL.md where this file says to.
when_to_use: >-
  Use once a PR you authored is approved and green (by hand, or from pr-runner), or when it is
  already queued and you want it watched and kept moving past flaky checks. Not for a PR that
  still has feedback or red checks (pr-shepherd, pr-checks-green), not for someone else's PR,
  and never to bypass required reviews or checks.
argument-hint: "[pr-number | pr-url] [--max-requeues N] [--timeout MIN] [--hung-after MIN] [--no-cleanup]"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Grep
  - Glob
---

# PR queue for merge (approved → queued → merged → closed out)

One run: preflight → queue (or merge) → watch → on failure: dequeue, diagnose, re-queue or
stop → plan → ticket → cleanup → report.

**Watch the jobs, not just the queue entry.** A merge-group job can fail ten minutes before
the queue marks the entry unmergeable, because the queue waits for the aggregate check. A
lost runner can keep the entry at "awaiting checks" long after every timeout has passed.
`scripts/watch-queue.sh` reads both every 30 seconds.

**Prove flaky; assume real.** A re-queue costs everyone behind you a full cycle. Re-queue only
what [`references/diagnose.md`](references/diagnose.md) proves flaky; everything else stops.

**Plain language and short** in every progress line and the report.

### What invoking this skill authorizes (this run, this PR only)

- adding this PR to its base branch's merge queue, and re-adding it up to `--max-requeues`
  times; with no merge queue, merging it with the repo's own method
- removing this PR from the queue when one of its merge-group checks failed or hung, and
  cancelling a workflow run that belongs only to this PR's merge group when it hangs
- after the merge: editing the branch's plan when it lives outside the repo, one Jira
  transition to Done with one short comment (last slice only), and deleting the PR's local
  branch and worktree

It does **not** cover: `--admin` or any bypass of required reviews or checks, touching another
PR's queue entry or runs, pushing or editing code, force anything, editing an in-repo plan
(its PR already carried the update), filing tickets, or moving a ticket backwards.

### Arguments

| Argument | Meaning | Default |
|---|---|---|
| `pr-number` or `pr-url` | The PR to merge | the current branch's PR |
| `--max-requeues N` | Re-queues allowed after flaky failures | `3` |
| `--timeout MIN` | Total minutes to wait for the merge | `110` (pr-runner kills a dispatch after its `timeout_min`, 120 by default) |
| `--hung-after MIN` | Minutes a check may run before it counts as hung | `40` (set it just above the repo's longest job timeout) |
| `--no-cleanup` | Keep the local branch and worktree after the merge | off |

### Progress checklist

Stages: 1 Preflight · 2 Queueing · 3 Watching (attempt n) · 4 Updating the plan · 5 Updating
the ticket · 6 Cleaning up. One `in_progress` at a time, live detail in the label
(`Watching (attempt 2/4, 31/43 checks passed)`), skipped stages `completed` with the reason, a
blocked stage stays `in_progress` with `(BLOCKED: …)`. No checklist in the host: one line per
transition.

`$SKILL_DIR` is the directory this file was loaded from (fallbacks
`~/.agents/skills/pr-queue-for-merge` or the host's own skills directory). Sibling skills live
at `$SKILL_DIR/../<name>/`.

---

## Step 0: Resolve, lock, preflight (read-only)

```sh
command -v gh jq >/dev/null && gh auth status >/dev/null || exit 1
PRJ=$(mktemp)    # never a fixed /tmp path: parallel sessions would overwrite it
# A URL carries owner/repo; a bare number uses the current repo; nothing → this branch's PR.
gh pr view ${PR_ARG:+"$PR_ARG"} --json number,url,state,isDraft,author,headRefName,headRefOid,baseRefName,reviewDecision,mergeStateStatus > "$PRJ"
PR=$(jq -r .number "$PRJ"); BASE=$(jq -r .baseRefName "$PRJ"); HEAD_OID=$(jq -r .headRefOid "$PRJ")
NWO=$(jq -r '.url | capture("github.com/(?<r>[^/]+/[^/]+)/").r' "$PRJ")
RUN="${XDG_STATE_HOME:-$HOME/.local/state}/pr-queue-for-merge/${NWO/\//-}-$PR/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"; cp "$PRJ" "$RUN/start.json"
```

**Lock.** Inside a checkout of the PR's head branch (pr-runner starts it there), the lock is
`$(git rev-parse --absolute-git-dir)/pr-queue-for-merge/lock`, so pr-runner sees the run.
Anywhere else, `$RUN/../lock`. Taken with `mkdir`; held → `RESULT: NOOP (another run is
merging #<n>)`. Write `date +%s` into `lock/started`. Every exit removes it.

`$RUN/start.json` keeps the head and the review decision at start: a re-queue later checks
neither has changed. Then, first failure decides:

| Check | Fails → |
|---|---|
| `state == OPEN` | `MERGED` → skip to Step 6 (closeout only). `CLOSED` → `NOOP (closed)` |
| author is you (`gh api user -q .login`) | `NOOP (not your PR)` |
| not a draft | `NOOP (draft)` |
| already queued: `"$SKILL_DIR/scripts/watch-queue.sh" "$PR" --repo "$NWO" --max-wait 0` exits `8`, `1` or `5` | exit `6` (not queued) → keep checking below. `8` → Step 3. `1`/`5` → Step 4 |
| `reviewDecision == APPROVED` (or empty when the repo requires no reviews) | `NOOP (not approved yet)` |
| no human feedback newer than the latest approval (below) | `NOOP (new feedback after approval; pr-shepherd)` |
| checks green on `HEAD_OID`: `"$SKILL_DIR/../pr-checks-green/scripts/wait-checks.sh" "$HEAD_OID" --pr "$PR" --max-wait 60 --grace 30` exits `0` or `3` | `8` → `NOOP (checks still running)`. `1` → `NOOP (checks failing; pr-checks-green)`. `4` → `NOOP (PR head moved)` |
| `mergeStateStatus` is `CLEAN`, `HAS_HOOKS`, or `BEHIND` with a merge queue | `BEHIND` without a queue → `gh pr update-branch "$PR"` and `NOOP (updated with base; checks rerunning)`. `DIRTY` → `NOOP (conflicts; pr-shepherd)`. `BLOCKED` → `NOOP (GitHub reports merge blocked)`. `UNKNOWN` → `NOOP (GitHub still computing mergeability)` |

**Feedback newer than the approval:** read reviews, comments and review-thread comments
(`gh api graphql`, `reviews(last:50)`, `comments(last:50)`, `reviewThreads(last:100){comments(last:1)}`
with `submittedAt`/`createdAt` and `author{login __typename}`). `APPROVED_AT` = the newest
`APPROVED` review. Anything after it whose author is not you and not a bot (`__typename ==
"Bot"` or a login ending in `[bot]`) counts. Comments posted together with the approval
(same `submittedAt`) don't.

## Step 1: Learn how the repo merges

```sh
gh api graphql -F o="${NWO%/*}" -F r="${NWO#*/}" -F b="$BASE" \
  -f query='query($o:String!,$r:String!,$b:String!){repository(owner:$o,name:$r){mergeQueue(branch:$b){id}}}' \
  -q '.data.repository.mergeQueue.id'
```

Non-empty → **queue mode**. Empty → **direct mode**: the method is the one the repo's docs
name (`CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`, the PR template), else the only one
`gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` allows, else
`squash`.

## Step 2: Queue (or merge)

```sh
gh pr merge "$PR" --repo "$NWO"                      # queue mode: enqueues; the queue owns the method
gh pr merge "$PR" --repo "$NWO" --<method>           # direct mode
```

Never `--admin`. Add `--delete-branch` only in direct mode, and only when the repo doesn't
auto-delete head branches (`gh repo view --json deleteBranchOnMerge`).

- Refused because something is still pending (review, checks, conflicts) → `NOOP` with
  GitHub's message. Refused for any other reason → `BLOCKED` with the message.
- **Denied by the agent host's permission layer** (an auto-mode classifier or a deny rule):
  don't route around it with another tool. Print the exact command for the user
  (`! gh pr merge <n> --repo <o/r>` in Claude Code). Interactive: wait for them, then go on to
  Step 3. Headless: `RESULT: BLOCKED (permission to run gh pr merge)`.

Queue mode: say where it sits (`#<n> queued at position <p>`). Direct mode: go to Step 3 and
treat any state but `MERGED` after a minute as the refusal it is.

## Step 3: Watch (every 30 seconds)

```sh
"$SKILL_DIR/scripts/watch-queue.sh" "$PR" --repo "$NWO" --hung-after "${HUNG_AFTER:-40}" \
  > "$RUN/snapshot.json" 2>> "$RUN/events.log"
```

Each call returns within `--max-wait` (default 540 s). Call it again while it exits `8`, until
`--timeout` minutes have passed in total (then `RESULT: BLOCKED (still queued after <n> min;
position <p>)`).

- **A host with a background monitor** (Claude Code's Monitor, a tmux pane): run the script
  under it with `2>&1` and a long `--max-wait`, so each queue or check change arrives as an
  event when it happens. Never poll less often than every 30 seconds, and never only the
  queue entry.
- Relay each event as one short line. Don't narrate silence.

| Exit | Meaning | Do |
|---|---|---|
| `0` | merged | record `mergedAt` and the merge commit (`gh pr view --json mergedAt,mergeCommit`); Step 6 |
| `1` | a merge-group check failed, was cancelled or timed out (`failed[]`) | Step 4 |
| `5` | a check has run past `--hung-after` (`hung[]`) | Step 4 |
| `6` | open, not queued, no failed check seen | read why (`gh pr view <n> --repo <o/r> --json timelineItems`, or the PR page): a removal with a reason you can act on → Step 5; a person dequeued it → `NOOP (dequeued by <who>)` |
| `7` | closed | `NOOP (closed)` |
| `8` | still waiting | call again |
| `2` | usage error, or GitHub unreadable three polls running | retry once after a minute; again → `BLOCKED (cannot read the PR)` |

## Step 4: Take it out of the queue

At once, before diagnosing. GitHub can keep a failing entry in place for many minutes, and
every PR behind it waits.

```sh
ID=$(gh pr view "$PR" --repo "$NWO" --json id -q .id)
gh api graphql -f id="$ID" -f query='mutation($id:ID!){dequeuePullRequest(input:{id:$id}){mergeQueueEntry{state}}}'
```

Skip the mutation when the queue already removed it (`isInMergeQueue` false). For a **hung**
check, also cancel the stuck run, but only a run whose head is this PR's merge-group commit
(`groupSha` in the snapshot):

```sh
[ "$(gh run view <run-id> --repo "$NWO" --json headSha -q .headSha)" = "<groupSha>" ] \
  && gh run cancel <run-id> --repo "$NWO"
```

Save the snapshot as `$RUN/attempt-<k>.json` so the next attempt can compare failures.

## Step 5: Diagnose, then re-queue or stop

```sh
"$SKILL_DIR/scripts/failure-summary.sh" "<url from failed[]>" --repo "$NWO" --save "$RUN/<job-id>.log"
```

It reads a finished job's log even while the rest of the run is still going. Then follow
[`references/diagnose.md`](references/diagnose.md). It ends in one of:

| Verdict | Do |
|---|---|
| **flaky** (infrastructure, or a flaky test with both proofs) | check the caps below, then `gh pr merge "$PR" --repo "$NWO"` and back to Step 3. One line: what failed, why it's flaky, the count (`re-queued (1/3): lane 9 exception-routing; passed on #3438's group`) |
| **caused by this PR** | `BLOCKED (<check>: <test or error> fails because of this PR's change; <link>)` |
| **red on the base branch** | `BLOCKED (<check> fails on <base> too: <this run> and <the base run>)` |
| **can't tell** | `BLOCKED (<check> failed and I can't prove it's flaky: <link>)` |

**Caps, checked before every re-queue.** Any one stops the run:

- `--max-requeues` already spent → `BLOCKED (failed <n> times: <checks>)`
- the same check and test failed in the previous attempt → `BLOCKED (<test> failed twice in a
  row; not treating it as flaky)`
- the head differs from `$RUN/start.json`, the PR is closed, or it is no longer approved →
  `NOOP (PR changed since it was queued: <what>)`

## Steps 6–8: Plan, ticket, cleanup

Follow [`references/closeout.md`](references/closeout.md): mark the slice `MERGED` in a plan
outside the repo and compute `NEXT`; move the ticket to Done only when this was the last
slice; then delete the local branch and worktree (skipped with `--no-cleanup`, or when they
have uncommitted changes). Each of these is skipped, with the reason, when it doesn't apply.

## Step 9: Report and release

A few plain lines:

- the PR link and how it ended: merged at `<time>` as `<merge commit>` (queue or method), or
  where it stopped
- each attempt: what failed, the verdict, the evidence (links), whether it was re-queued, and
  anything done to the queue or runs (dequeues, cancelled runs)
- plan change (path) or why skipped; ticket transition; cleanup

Remove the lock. **The last two lines are always:**

```
NEXT: <plan path> PR <n>        (or: NEXT: none)
RESULT: DONE | NOOP (<why>) | BLOCKED (<what failed and what you need>)
```

## Principles

- **Strict preflight, no overrides.** Approved, green, mergeable, nothing new since the
  approval. GitHub's own merge state is the judge of required reviews and conversations.
- **Merge the repo's way.** The queue when there is one, the repo's method otherwise.
- **Watch the jobs.** The queue entry is the last thing to learn a check failed.
- **Dequeue first, then think.** A failing or hung entry blocks everyone behind it.
- **Prove flaky; assume real.** Twice in a row is a pattern, not a flake.
- **Merged means GitHub says MERGED.** Never close out a merge that hasn't happened.
- **Only this PR.** Never touch another PR's entry or runs.
- **The last line is the contract.**

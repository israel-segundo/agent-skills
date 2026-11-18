---
name: pr-shepherd
description: >-
  Shepherd your own open PR through another review round, unattended: rebase onto the
  default branch, address the new review feedback, push, watch the CI checks and fix what
  breaks until they are green, reply to and resolve the threads, then ask the reviewers on
  Slack to look again. Chains git-rebase, pr-address-feedback, pr-checks-green and
  request-pr-review, and replaces their confirmation prompts with one standing
  authorization: invoking this skill is the go-ahead for this run's lease-protected push,
  thread replies, PR description edit, reviewer re-request and Slack post. Stops to ask only on a blocker it cannot fix. Files no
  tickets. Safe to trigger from GitHub events: a per-worktree lock serializes runs, a run
  with nothing new exits without touching anything, and the last line is a parseable RESULT.
  Use when a PR you authored got feedback (not an approval) and you want it handled end to
  end.
license: Unlicense
metadata:
  version: "1.3.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git/gh/jq) rather than
    host-specific tools. Depends on the sibling skills git-rebase, pr-address-feedback,
    pr-checks-green and request-pr-review; if your host has no skill support, read each
    SKILL.md where this file says to and follow it with the overrides stated here.
when_to_use: >-
  Use in a worktree whose branch has an open PR you authored, after reviewers or review
  bots left feedback, or CI went red, and you want the whole cycle (sync, fix, push, green
  CI, close out threads, re-request review) done without being asked anything. Not for
  someone else's PR, not for opening a PR (create-pr), and not for merging.
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
---

# PR shepherd (one review round, end to end, unattended)

Take this branch's open PR from "someone left feedback" to "fixed, green, and back in the
reviewers' queue" in one run:
triage → sync → assess → rebase → fix → verify → commit → push → CI until green →
re-sweep → reply/resolve → request review.

**The defining stance: you run unattended, so a blocker is the only reason to stop.** Every
confirmation gate in the sub-skills is pre-answered by this run's authorization (below).
Every *safety* guardrail in them still applies. When something comes up that you can't
settle from the code, the plan, or the PR, stop cleanly and say exactly what you need. Don't
guess, and don't route around it.

**The second rule: leave no trace when there's nothing to do.** This skill gets triggered by
webhooks. A run with no new feedback and green CI must not rebase, push, comment, or ping
anyone.

**Plain language and short**, in every reply, PR edit and Slack message.

### What invoking this skill authorizes (for this run, on this branch only)

The user running this skill, or a runner they set up to run it, is the explicit
confirmation that the sub-skills and any user-level "confirm before pushing" rule ask for.
It covers:

- pushing the current feature branch: a plain push, or `--force-with-lease` pinned to the PR
  head this run validated after its own rebase
- commits for review fixes, CI fixes, and an in-repo plan update
- replying to and resolving human review threads, plus one top-level PR comment
- editing the PR description's **Future work** section
- re-requesting review on GitHub from the humans whose feedback this run handled
- posting (or threading) the review request in the configured Slack channel, with no
  preview step

It does **not** cover filing tickets (never, in any form), merging, approving, closing,
draft/ready flips, pushing any other branch, a bare `--force`, `--no-verify`, disabling hooks,
or `git reset --hard` / `rebase --skip` / dropping a stash.

### Blockers: the only reasons to stop

Stop, leave the tree clean, and report `RESULT: BLOCKED` for any of these:

- uncommitted changes to tracked files in the worktree (someone may be working in it)
- the local branch has diverged from the PR's remote head, or a push gets rejected
- a rebase or merge conflict that git-rebase would stop and ask about; abort it first
- a finding that needs a decision only the author can make (see Step 3)
- the repo's verify gate, or a CI check, still failing after 3 fix attempts in this run
- a CI failure that is proven to fail on the base branch too, or whose log you can't read
- the PR head moved to a commit this run didn't push
- no Slack channel configured, or no Slack transport (print the message for the user)
- more than 3 feedback rounds in one run (bots keep finding new things)

**Interactive host:** ask the one question that unblocks you. That's the only prompt this
skill ever makes. **Headless:** print the blocker and exit. Either way, release the lock.

### Sub-skills

Invoke `git-rebase`, `pr-address-feedback`, `pr-checks-green` and `request-pr-review` by
name through the host's skill mechanism, so a repo-local version of any of them wins. If the
host has none, read `$SKILL_DIR/../<name>/SKILL.md` and follow it. `$SKILL_DIR` is the
directory this file was loaded from; hosts usually state it, and the usual fallbacks are
`~/.agents/skills/pr-shepherd` or the host's own skills directory. **The overrides in each step below replace the
sub-skill's confirmation steps, and only those.**

### Progress checklist

Show the run as a checklist in the host's own todo/plan list, the one a TUI or desktop app
renders as empty, half and filled circles. Create it with every stage `pending` as the
**first action of Step 0**, before any command runs, so the user sees the whole run at once.
The `▸ Stage N` markers in the steps below say when each stage starts.

| # | Stage | Covers | Done when |
|---|---|---|---|
| 1 | Checking for new activity | Steps 0–1 | triage has decided there's work |
| 2 | Reading and validating feedback | Steps 2–3 | every finding has a disposition |
| 3 | Rebasing onto `<default branch>` | Step 4 | the branch sits on the latest default |
| 4 | Applying feedback | Step 5: fixes, plan Open items | edits are in the tree |
| 5 | Building and testing | Step 5: verify | the repo's verify gate is green |
| 6 | Committing | Step 5: commit | the commit exists |
| 7 | Pushing | Step 6 | the remote has the new head |
| 8 | Monitoring PR checks | Steps 7–8 | checks green and no new feedback |
| 9 | Replying to reviewers | Step 9 | replies posted, threads resolved, Future work updated |
| 10 | Requesting re-review | Step 10 | GitHub re-request and Slack post done |

Rules for keeping it truthful:

- **Exactly one stage `in_progress` at a time.** Mark each stage `completed` the moment it's
  done, not in a batch at the end.
- **Keep one checklist for the whole run.** The sub-skills don't create their own. If one of
  them would, fold its progress into the current stage's label instead
  (`Applying feedback (3/7)`).
- **Live detail goes in the label**, for example `Monitoring PR checks (4/13 pending)` or
  `Monitoring PR checks (fixing lint, attempt 2/3)`.
- **A skipped stage** is marked `completed`, with the reason in its label:
  `Rebasing onto main (skipped: replies only)`. On a NOOP, mark stage 1 `completed` with
  the reason, and mark every later stage completed as `(skipped)`.
- **A new feedback round** (Step 8) puts stages 2 and 4–8 back to `pending` with a
  `(round N)` suffix. Stage 3 repeats only when the re-sweep finds a conflict.
- **Blocked:** leave the current stage `in_progress` and rename it
  `<stage> (BLOCKED: <short reason>)`. Todo lists have no failed state, and an unfinished
  circle is the honest picture.
- **No checklist in this host** (headless, or a runner reading stdout): print one line per
  transition instead, such as `▸ [3/10] Rebasing onto main: started` and
  `✓ [3/10] Rebasing onto main`. The `RESULT:` line still comes last.

---

## Step 0: Lock and preflight

▸ **Stage 1.** Create the progress checklist (all ten stages `pending`), then set stage 1
`in_progress`.

```sh
command -v git gh jq && gh auth status >/dev/null      # all required
REPO=$(git rev-parse --show-toplevel) || exit
STATE="$(git -C "$REPO" rev-parse --absolute-git-dir)/pr-shepherd"   # per worktree
mkdir -p "$STATE"
LOCK="$STATE/lock"
if mkdir "$LOCK" 2>/dev/null; then
  date +%s > "$LOCK/started"
elif [ $(( $(date +%s) - $(cat "$LOCK/started" 2>/dev/null || echo 0) )) -gt 10800 ]; then
  rm -rf "$LOCK" && mkdir "$LOCK" && date +%s > "$LOCK/started"       # stale (>3h): take over
else
  touch "$LOCK/rerun"                                                  # ask the active run for one more sweep
  echo "RESULT: NOOP (another pr-shepherd run is active here; flagged it to sweep once more)"
  exit 0
fi
```

From here on, **every exit path removes `$LOCK`.** Then check, and stop on the first failure:

- on a branch (not detached), and not the default branch
- no rebase, merge, cherry-pick or bisect in progress
- `git -C "$REPO" status --porcelain --untracked-files=no` is empty → otherwise **BLOCKED**
- an open PR exists for the branch, and its author is you
  (`gh api user -q .login`) → otherwise `RESULT: NOOP` with the reason

Write everything this run learns (PR number, head, cutoffs, findings, outcomes) under
`$STATE/run-<timestamp>/`, so no step relies on remembering what an earlier one found.

## Step 1: Triage (read-only)

```sh
"$SKILL_DIR/scripts/triage.sh" > "$STATE/triage.json"
```

It reports the PR state, the remote head, new feedback since that head's committer date
(excluding your own comments, with per-comment IDs), the head's CI buckets, and
`conflicting`: whether the head still merges into the latest base.

**Use `conflicting`, never GitHub's `mergeable` on its own.** GitHub keeps reporting
`MERGEABLE`/`CLEAN` for a while after the base moves, and longer while the PR sits in a merge
queue, so a run that trusts it can NOOP minutes before the queue drops the PR with
`MERGE_CONFLICT`. The script fetches the base and test-merges the head with `git merge-tree`
when it runs inside a checkout of the PR's repo. If `localMerge.checked` is false, run that
test-merge yourself before deciding there's nothing to do:
`git -C "$REPO" fetch "$REMOTE" "$BASE" && git -C "$REPO" merge-tree --write-tree --name-only FETCH_HEAD "$HEAD_OID"`
(exit 1 = conflict).

- `state` is not `OPEN` → `RESULT: NOOP`.
- **No new feedback** (`feedback.human + feedback.bot == 0`), **no failing checks**, and
  `conflicting` is false → `RESULT: NOOP (nothing new)`. Touch nothing.
- Anything else → carry on. Save `PR`, `HEAD_OID` (= `headRefOid`), `BASE`, and set
  `ROUND=1`, `FIX_ATTEMPTS=0`, `PUSHED=0`.

## Step 2: Catch up to the PR's own remote head

▸ **Stage 2** starts here and runs through Step 3.

Resolve `$REMOTE` the way git-rebase's Step 0 does. Then:

```sh
git -C "$REPO" fetch "$REMOTE" "$BRANCH"
git -C "$REPO" rev-list --left-right --count "HEAD...$HEAD_OID"   # "<ahead> <behind>"
```

- behind = 0 → carry on.
- ahead = 0, behind > 0 → `git -C "$REPO" merge --ff-only "$HEAD_OID"`, and note the commits
  you picked up.
- both > 0 → **BLOCKED**. Show both sides (`git log --oneline HEAD..$HEAD_OID` and the
  reverse). Even when the local-only commits look like stale duplicates of an unpushed rebase,
  the fix is a `reset --hard`, and that's the user's call.

This step runs **before** any rebase on purpose. pr-address-feedback must validate findings
against the tree the reviewer actually saw. After a rebase, its sync gate would read your
own rewritten commits as "diverged" and stop.

## Step 3: Assess the feedback (read-only)

Record `SWEEP_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)` first. Then run **pr-address-feedback
Steps 0–4** with these overrides:

- **Cutoff:** round 1 uses its own (the remote head's committer date). In later rounds, use
  the previous round's `SWEEP_START`, and skip any comment whose `id` + `at` already appears
  in `$STATE/handled.json`.
- **Dispositions: use these five, not its four.** No disposition ever produces a ticket.

| Disposition | When | Outcome |
|---|---|---|
| **Fix now** | Valid, and in scope **or** fixable and short: a localized change with no new module, no schema/API/migration/contract change, and no reversal of a design another reviewer approved (rough guide: under ~50 changed lines) | Implemented. Reply with what changed and the commit, then **resolve** the thread. |
| **Future work** | Valid but not short | Added to the plan's **Open items** (if a plan exists) and to the PR's **Future work** section. Reply saying so; leave the thread **open**. |
| **Answer** | A question you can answer from the code, plan, ticket or PR | Reply with the answer; leave the thread **open**. |
| **Skip** | Invalid, already handled, or stale | Reply with the evidence; leave the thread **open**. |
| **Blocker** | Needs the author's judgment: reviewers contradict each other, a product-behavior choice, undoing a deliberate decision, or a request that conflicts with the plan or ticket | **BLOCKED**, quoting the comment and the decision needed. |

Bot findings get the same dispositions but never get a reply or a resolve, per
pr-address-feedback.

- **Plan gate (its Step 5):** write the HTML report as the record, but **don't open it and
  don't wait**. Its path goes in the final summary.
- **Nothing actionable** (no Fix now or Future work, no human thread needing a reply, CI not
  failing, not `conflicting`) → append the IDs to `handled.json` and finish as
  `RESULT: NOOP (feedback needed no action)`.
- **Only replies needed** (Answer/Skip, no code change, CI not failing, not `conflicting`) →
  skip to Step 9. Don't rebase or push just to post replies.

## Step 4: Rebase (round 1 only)

▸ **Stage 3.**

```sh
PRE_REBASE=$(git -C "$REPO" rev-parse HEAD)
```

Run **git-rebase** with these overrides:

- Anything it would stop and ask about (an undecidable conflict, a divergence, an
  unresolvable default branch) → abort the operation in progress (`rebase --abort` or
  `merge --abort`) so the branch is back at `$PRE_REBASE`, then **BLOCKED**.
- Its "never push" stays. Step 6 pushes.
- If nothing came in from the default branch, that's fine. Carry on.

## Step 5: Apply, record, verify, commit

Run **pr-address-feedback Steps 6–9** with these overrides. The progress stages map onto
them: **Stage 4** covers its Steps 6–7, **Stage 5** its Step 8, and **Stage 6** its Step 9.

- **Step 6:** apply the Fix now items. The blocking-first order and the tests for
  behavioral fixes still apply.
- **Step 7, replaced. No tickets.** For each Future work item:
  - Find the plan for this branch. Take the ticket key from the branch name
    (`[A-Z][A-Z0-9]+-[0-9]+`) and search case-insensitively for `*plan*.md` containing the key
    in this order: a plan doc inside the repo (per pr-address-feedback's
    `references/discovery.md`), then `$PLANS_DIR` (with `{repo}` expanded to the main
    checkout's directory name) or `.plan-store`, then `$PLANS_ROOT` (all recursively,
    including `completed`-style subfolders), then any plan location the user's own agent
    instructions name. If there are several candidates, prefer one with the key in its path that isn't
    under a completed folder. If it's still ambiguous, or there's no plan, skip this and say
    so. That isn't a blocker.
  - Under the plan's `## Open items` heading (add it at the end if it's missing), append
    `- [ ] <one line> (from PR #<n> review, @<reviewer>)`, unless an equivalent line is
    already there. A plan inside the repo goes into the commit. A plan outside the repo gets
    edited in place and isn't committed.
- **Step 8:** verify until green. If it's still red after 3 attempts → **BLOCKED**, with
  the commits left local and unpushed, and say so.
- **Step 9:** commit (message via `-F` file, the repo's convention), but **don't push**.
  Step 6 owns the push.

## Step 6: Push

▸ **Stage 7.**

```sh
if git -C "$REPO" merge-base --is-ancestor "$HEAD_OID" HEAD; then
  git -C "$REPO" push "$REMOTE" "HEAD:$BRANCH"                                   # ahead-only
else
  git -C "$REPO" push --force-with-lease="$BRANCH:$HEAD_OID" "$REMOTE" "HEAD:$BRANCH"   # rebased
fi
```

The explicit lease (`$BRANCH:$HEAD_OID`) is the point. The push succeeds only if the remote
still holds the exact head this run validated, whatever your remote-tracking ref says.
**A rejected push → BLOCKED.** Never escalate it. If a pre-push hook fails, fix the cause and
retry (it counts toward `FIX_ATTEMPTS`). Never use `--no-verify`.

Set `PUSHED=1`, `HEAD_OID=$(git -C "$REPO" rev-parse HEAD)`, and append every in-scope
comment's `id` + `at` to `$STATE/handled.json`.

## Step 7: Watch the checks, fix until green

▸ **Stage 8** starts here and runs through Step 8. Refresh its label with the pending count,
or with the check being fixed.

Run **pr-checks-green** with this run's state: `PR`, `HEAD_OID`, `REMOTE`, `BRANCH`, `BASE`,
`FIX_ATTEMPTS`, and `PR_CI_TIMEOUT` (default 60; `SHEPHERD_CI_TIMEOUT` still works). This
run's authorization covers its commits and plain pushes. Afterwards take back its final
`HEAD_OID` and `FIX_ATTEMPTS`.

| Its result | Do |
|---|---|
| `DONE` | go to Step 8 (`no CI on this repo` → treat local verify as the evidence) |
| `BLOCKED` | **BLOCKED**, with its reason |

## Step 8: Re-sweep for feedback that arrived during the run

Review bots often post *after* CI. Reviewers may also have commented while you worked.

```sh
"$SKILL_DIR/scripts/triage.sh" --pr "$PR" --since "$SWEEP_START"
```

Drop the items already in `handled.json`. If anything is left, or `$LOCK/rerun` exists
(remove it), then `ROUND+=1`. At `ROUND > 3` → **BLOCKED**. Otherwise go back to **Step 3**
(no rebase this time, unless `conflicting`; see below), then Steps 5–8.

The base keeps moving while CI runs. If this sweep reports `conflicting`, rebase again
(Step 4, even in a later round), then Steps 5–8. That counts as a round. Never finish a run
as DONE or NOOP while `conflicting` is true.

## Step 9: Close out on the PR

▸ **Stage 9.**

Use **pr-address-feedback Step 10** for the mechanics (reply shape, GraphQL resolve, and
re-querying the unresolved count). The resolution rules come from the Step 3 table:

- **One reply per human thread** saying what was done. Fix now → the commit SHA, then
  **resolve**. Future work → "not in this PR; listed under Future work", and leave it open.
  Answer / Skip → the answer or the evidence, and leave it open.
- **Human findings outside threads** (review summaries, top-level comments): post **one**
  top-level PR comment that names each one briefly and says what was done.
- **Future work section:** read the body with `gh pr view "$PR" --json body -q .body`, then
  add each item to a `## Future work` section (creating it at the end if needed, and skipping
  lines already there). Write it back with `gh pr edit "$PR" --body-file <file>`.
- Re-query the unresolved count and record it.

## Step 10: Request review again

▸ **Stage 10.**

**Only if `PUSHED=1` and the PR isn't a draft.** If this run pushed nothing, don't ping
anyone. A draft gets everything above, minus this step, and the summary says so.

1. Re-request review on GitHub from each human whose feedback this run handled (excluding
   you): `gh pr edit "$PR" --add-reviewer <login>`. Note any failures, but they aren't
   blockers.
2. Run **request-pr-review** with these overrides:
   - **Its Step 1c (existing request found):** reply in that thread with a follow-up such as
     "Addressed the feedback, ready for another look", per its `message-format.md`. That's
     the normal path here.
   - **Its Step 3 (no reviewers):** use the logins from step 1 above. Still none → **BLOCKED**.
   - **Its Step 4 (a login with no Slack ID):** write the person's plain name (no mention),
     and note it. Never guess an ID.
   - **Its Step 6 (confirm):** skipped, because this run authorizes it.
   - **No channel configured, or no Slack transport** → **BLOCKED**, and print the exact
     message for the user to post.

## Step 11: Report and release

A few plain lines:

- rounds run, and whether the branch was rebased (or merged, and why)
- what was fixed and in which commits, and the CI fix attempts
- Future work items, and where they were recorded (plan path, PR section)
- replies posted, threads resolved, and threads left open (and why)
- the Slack link, and the reviewers re-requested
- the findings report path

Before printing the result, make sure the checklist matches it. On DONE every stage is
`completed`. On BLOCKED exactly one stage is still `in_progress` and labelled with the
blocker.

Remove `$LOCK`. **The last line of output is always exactly one of:**

```
RESULT: DONE
RESULT: NOOP (<why>)
RESULT: BLOCKED (<what you need from the user>)
```

---

## Running it from GitHub events

The simplest runner is **pr-runner**: a scheduled sweep over your open PRs that runs this
skill in each PR's worktree when there's feedback, a red check or a conflict. Event-driven
setups work too:

- Run it from the PR's own worktree with your agent's headless mode (for example
  `codex exec "Use the pr-shepherd skill."`, `gemini -p …`, `claude -p "/pr-shepherd"`), and
  parse the final `RESULT:` line. The host's permission settings must allow the git, gh and verify
  commands to run without prompts.
- Useful triggers: a submitted review that isn't an approval, a review comment, a PR issue
  comment, and a failed check suite. Ignore events you authored yourself. Triage would NOOP
  them anyway, but skipping them saves a run.
- Overlapping triggers are safe. The second run flags the first to sweep once more, then
  exits. A crashed run's lock goes stale after 3 hours.
- Don't point the runner at a worktree where you're actively editing. The clean-tree check
  blocks most of that, but not all of it.

## Principles

- **Blockers are the only prompts.** Every confirmation gate is pre-answered by the run's
  authorization. Every safety guardrail still holds.
- **No news, no noise.** Nothing new means no rebase, no push, no comment, no ping.
- **Validate before rebasing.** Assess the feedback against the tree the reviewer saw, then
  rebase, then fix.
- **Lease against what you validated.** Use `--force-with-lease=<branch>:<validated head>`,
  never a bare force. A rejected push is a blocker, not a prompt to escalate.
- **No tickets.** Short and fixable means fix it now. Otherwise it goes to the plan's Open
  items and the PR's Future work. Every finding gets a reply saying what happened, and only
  implemented findings get resolved.
- **Green means green.** Fix what the branch broke, rerun flakes once, and prove any
  "pre-existing" failure on the base branch before calling it that.
- **The last line is the contract.** Exactly one `RESULT:` line, so a runner never has to
  guess.

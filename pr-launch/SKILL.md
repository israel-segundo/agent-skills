---
name: pr-launch
description: >-
  Take a finished feature branch from "implementation done" to "ready PR, green CI,
  reviewers pinged, ticket updated", unattended. Runs review rounds and fixes every finding,
  runs the repo's unit and end-to-end sanity suites locally, pushes, opens a ready-for-review
  PR whose body is de-slopped and carries Before/After diagrams, drives the checks to green,
  requests review on GitHub and Slack, and posts a development update on the ticket. Chains
  pr-review-fix, create-pr, deslopify, pr-checks-green, request-pr-review and
  jira-update-issue, and replaces their confirmation prompts with one standing
  authorization. Stops to ask only on a blocker it cannot fix. Files no tickets. Ends with a
  parseable RESULT line, and a re-run resumes where a blocked run stopped. Use right after
  execute-plan finishes a slice.
license: Unlicense
metadata:
  version: "1.1.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git/gh/jq) rather than
    host-specific tools. Depends on the sibling skills pr-review-fix, create-pr, deslopify,
    pr-checks-green, request-pr-review, jira-update-issue and jira-transition; if your host
    has no skill support, read each SKILL.md where this file says to and follow it with the
    overrides stated here. Team-specific reviewers live in the request-pr-review registry,
    never here.
when_to_use: >-
  Use in a worktree whose feature branch is implemented and committed but has no PR yet,
  typically right after execute-plan, when you want review, sanity tests, push, PR, green CI,
  review request and ticket update done without being asked anything. Not for a branch that
  already has a PR (pr-shepherd handles later rounds), not for someone else's branch, and not
  for merging.
argument-hint: "[base-branch] [--reviewers login1,login2]"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
---

# PR launch (finished branch → ready PR in reviewers' hands, unattended)

One run: preflight → review and fix → sanity tests → push → ready PR → plan link → CI until
green → request review → ticket update → report.

**You run unattended, so a blocker is the only reason to stop.** Every confirmation gate in
the sub-skills is pre-answered by this run's authorization (below). Every *safety* guardrail
in them still applies. When something comes up you can't settle from the code, the plan, the
ticket or the repo's docs, stop cleanly and say exactly what you need.

**Plain language and short**, in the PR body, the Slack message and the ticket comment.

After this skill, later review rounds belong to **pr-shepherd**.

### What invoking this skill authorizes (for this run, on this branch only)

The user running this skill is the explicit confirmation that the sub-skills and any
user-level "confirm before pushing" rule ask for. It covers:

- commits for review fixes, sanity-test fixes, CI fixes, and an in-repo plan update
- pushing the current feature branch with a **plain** push (it's new, so nothing to force)
- creating **one** PR for this branch, **ready for review** (not draft)
- setting reviewers on that PR
- one Slack review request in the configured channel, with no preview step
- one comment on the branch's ticket, and one status move to in review, with no preview step
- starting and stopping local services the sanity suites need, per the repo's docs

It does **not** cover: filing tickets (never, in any form), editing the ticket or moving it
anywhere but forward to in review, merging, approving, closing, draft flips, force pushes of any kind, `--no-verify`,
disabling hooks or tests, killing processes this run didn't start, seeding anything remote,
or `git reset --hard` / dropping a stash.

### Blockers: the only reasons to stop

Stop, leave the tree clean, record where you stopped, and report `RESULT: BLOCKED`:

- uncommitted changes to tracked files at preflight (someone may be working here)
- pr-review-fix ends BLOCKED, or doesn't converge within its round cap
- a sanity failure or CI check still failing after 3 fix attempts in this run (shared cap)
- a failure proven to fail on the default branch too, or whose log you can't read
- a service a suite needs is held by another worktree or process, or can't be started
- a push gets rejected, or the remote branch moved to a commit this run didn't push
- create-pr's review gate finds a blocker on this HEAD
- a finding or failure that needs a decision only the author can make (product behavior,
  reversing a plan decision, reviewers' or tickets' requirements contradicting each other)
- no reviewers resolvable, or no Slack channel/transport (print the message for the user)

**Interactive host:** ask the one question that unblocks you. **Headless:** print the
blocker and exit. Either way, release the lock. A missing ticket key or Jira transport is
**not** a blocker: print the comment and carry on.

### Sub-skills

Invoke `pr-review-fix`, `create-pr`, `deslopify`, `pr-checks-green`, `request-pr-review`,
`jira-update-issue` and `jira-transition` by name through the host's skill mechanism, so a
repo-local version of any of them wins. If the host has none, read
`$SKILL_DIR/../<name>/SKILL.md` and follow it. `$SKILL_DIR` is the directory this file was
loaded from; the usual fallbacks are
`~/.agents/skills/pr-launch` or the host's own skills directory. **The overrides in each step
replace the sub-skill's confirmation steps, and only those.**

### Progress checklist

Show the run as a checklist in the host's todo/plan list. Create it with every stage
`pending` as the **first action of Step 0**.

| # | Stage | Covers |
|---|---|---|
| 1 | Preflight | Step 0 |
| 2 | Reviewing and fixing | Step 1 |
| 3 | Running sanity tests | Step 2 |
| 4 | Pushing | Step 3 |
| 5 | Creating the PR | Step 4 |
| 6 | Monitoring PR checks | Steps 5–6 |
| 7 | Requesting review | Step 7 |
| 8 | Updating the ticket | Step 8 |

Exactly one stage `in_progress` at a time; mark each `completed` the moment it's done. Live
detail goes in the label (`Running sanity tests (api e2e, 2/3)`,
`Monitoring PR checks (fixing lint, attempt 2/3)`). A skipped stage is `completed` with the
reason (`(skipped: done in previous run)`). Blocked: leave the stage `in_progress`, renamed
`<stage> (BLOCKED: <short reason>)`. No checklist in this host: print one line per
transition (`▸ [3/8] Running sanity tests: started`, `✓ [3/8] Running sanity tests`).

---

## Step 0: Lock, preflight, resume

▸ **Stage 1.**

```sh
command -v git gh jq && gh auth status >/dev/null      # all required
REPO=$(git rev-parse --show-toplevel) || exit
STATE="$(git -C "$REPO" rev-parse --absolute-git-dir)/pr-launch"     # per worktree
mkdir -p "$STATE"
LOCK="$STATE/lock"
if mkdir "$LOCK" 2>/dev/null; then
  date +%s > "$LOCK/started"
elif [ $(( $(date +%s) - $(cat "$LOCK/started" 2>/dev/null || echo 0) )) -gt 10800 ]; then
  rm -rf "$LOCK" && mkdir "$LOCK" && date +%s > "$LOCK/started"       # stale (>3h): take over
else
  echo "RESULT: NOOP (another pr-launch run is active in this worktree)"; exit 0
fi
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
```

From here on, **every exit path removes `$LOCK`.** Resolve `REMOTE` and `BASE` the way
pr-review-fix's Step 0c does (an argument overrides `BASE`). Then check, stopping on the
first failure:

- on a branch (not detached), and not `$BASE`
- no rebase, merge, cherry-pick or bisect in progress
- `git -C "$REPO" status --porcelain --untracked-files=no` is empty → otherwise **BLOCKED**
- `git -C "$REPO" rev-list --count "$REMOTE/$BASE..HEAD"` > 0 → otherwise
  `RESULT: NOOP (no commits ahead of <base>)`
- if the branch already exists on the remote, its head is an ancestor of `HEAD` → otherwise
  **BLOCKED** (someone else pushed)

**Resume.** `$STATE/state.json` records `{branch, pr, done: [stage numbers], fix_attempts}`.

- An open PR exists for `$BRANCH` (`gh pr list --head "$BRANCH" --state open --json number`)
  **and** `state.json` names it → resume: skip every stage in `done`, carry `fix_attempts`.
- An open PR exists and `state.json` doesn't name it → `RESULT: NOOP (PR #<n> already
  exists; later rounds belong to pr-shepherd)`.
- No PR → start fresh (an old `state.json` for this branch keeps only stages 2–3, and only if
  `HEAD` hasn't moved since they finished; record `head` with each stage to check that).

Write each run's notes under `RUN="$STATE/run-<timestamp>"`. Update `state.json` as each
stage completes, so a re-run never redoes finished work.

## Step 1: Review and fix

▸ **Stage 2.**

Run **pr-review-fix** (no PR number; scope is `$BASE...HEAD`). Its review-pass resolution
already prefers a repo-local review command, then the review skills, then the host's
built-in code review, so whatever "the code review" means in this repo is what runs.

Overrides:

- Its "never pushes" stays. Step 3 pushes.
- Its final summary goes to `$RUN/review.md`; the PR body's Tests and Future Tasks read it.
- It ends **BLOCKED** → **BLOCKED** with its reason.

Record `REVIEWED_HEAD=$(git rev-parse HEAD)`.

## Step 2: Sanity tests

▸ **Stage 3.**

Follow [`references/sanity-suite.md`](references/sanity-suite.md): unit (reusing
pr-review-fix's last verify run when it covered unit tests and nothing changed since), then
every end-to-end suite it resolves (UI and API), with services handled by its rules.

If this stage committed any fix, `HEAD` has moved past the reviewed one. Run
**pr-review-fix** once more (`--max-rounds 2`) so a review pass covers the exact head that
gets published, then update `REVIEWED_HEAD`.

## Step 3: Push

▸ **Stage 4.**

```sh
git -C "$REPO" push -u "$REMOTE" "HEAD:$BRANCH"
HEAD_OID=$(git -C "$REPO" rev-parse HEAD)
```

Plain push only. **A rejected push → BLOCKED.** Never escalate it. A failing pre-push hook
is fixed at its cause and retried (counts toward the fix cap). Never `--no-verify`.

## Step 4: Create the PR (ready for review)

▸ **Stage 5.**

Run **create-pr** with `$BASE`, and these overrides:

- **Ready, not draft, said explicitly.** Invoke it with an explicit instruction to open the
  PR ready for review, not as a draft. This run *is* the caller's explicit ask, so it
  overrides any draft-by-default rule in a repo-local create-pr skill, the PR template, or
  the repo's docs. If the repo-local skill still opens a draft, run `gh pr ready "$PR"`
  once, straight away, and note it in the report.
- **Its Step 7 review gate:** pr-review-fix's clean round on `REVIEWED_HEAD` (= `HEAD_OID`)
  is the pass that covers this head. Reuse it; don't run another. If the gate still finds a
  blocker → **BLOCKED**. Never fall back to a draft silently.
- **Future Tasks:** deferrals are labelled *won't fix here*, *accepted risk* or *future
  work*. Never *follow-up ticket*.
- **Diagrams (its System Diagrams section):** when the diff changes a flow, a data path, a
  state machine or the architecture, include **two** Mermaid blocks, each under its own bold
  heading, **Before** first, then **After**. Never one diagram with two disconnected
  subgraphs (renderers reorder them). Keep every line of a node or edge label to about 12
  characters, break longer text with `<br/>` inside a quoted label (`id["Short<br/>lines"]`),
  use plain words instead of long identifiers, and no `*` or `_` emphasis in labels. Never a
  literal `\n`. No flow to draw (docs, config, test-only, pure rename) → omit the section and
  say why in the report.
- **De-slop the body before creating.** After create-pr writes `$WORK/pr_body.md`, run
  **deslopify** on that text as pasted input (not an issue key):
  - apply only its de-slop rules (its Steps 2–5) to the prose; keep create-pr's section
    headings and order
  - leave fenced code blocks, Mermaid blocks, links, file paths, identifiers, numbers and
    ticket keys byte-for-byte
  - no deslopify footer, no Format A/B template, no Jira write, and skip its "show the
    result" step
  - write the result back to `$WORK/pr_body.md`
- **Its confirm before creating:** skipped, this run authorizes it.
- Its "never push" stays (Step 3 already pushed).

Record `PR`. Add it to `state.json` immediately, so a crash after this point resumes rather
than NOOPs.

**Plan link.** Find execute-plan's plan for this branch the way pr-shepherd's Step 5 does
(ticket key from the branch; in-repo plan doc, then `$PLANS_DIR` with `{repo}` expanded,
then `$PLANS_ROOT` recursively, then `.plan-store`, then any plan location the user's agent
instructions name). Then:

- **Plan outside the repo** → set this slice's PR-map row to `IN REVIEW` with the PR link;
  edit in place, no commit. pr-land sets `MERGED` after the merge.
- **Plan inside the repo** → set this slice's row to `MERGED` with the PR link, in this PR
  (a plan with no PR-map table keeps status in its `### PR N: … -- **STATUS**` headings:
  change that marker, and add the PR link under the heading).
  The default branch only sees that row when this PR merges, so it's true there by
  construction and no post-merge commit is ever needed (a closed, unmerged PR never lands
  it). If no other row (or heading) is left `PENDING` or `IN PROGRESS`, and every
  `IN REVIEW`/`COMPLETED` one has a merged PR (`gh pr list --search "<KEY>" --state merged`),
  also set those to `MERGED` and Overall to complete. Commit, plain-push, then
  `HEAD_OID=$(git rev-parse HEAD)`.
- No plan, or ambiguous → skip and say so.

## Step 5: Watch the checks, fix until green

▸ **Stage 6.**

Run **pr-checks-green** with `PR`, `HEAD_OID`, `REMOTE`, `BRANCH`, `BASE`, `FIX_ATTEMPTS`
and `PR_CI_TIMEOUT` (default 60). This run's authorization covers its commits and plain
pushes. Take back its final `HEAD_OID` and `FIX_ATTEMPTS`.

| Its result | Do |
|---|---|
| `DONE` | Step 6 (`no CI on this repo` → local verify and sanity runs are the evidence) |
| `BLOCKED` | **BLOCKED**, with its reason |

## Step 6: Catch early bot feedback

Review bots often comment within minutes of a ready PR. Read the PR's reviews and comments
(`gh pr view "$PR" --json reviews,comments` plus
`gh api "repos/{owner}/{repo}/pulls/$PR/comments"`). Don't act on them here: list them in
the report and say that **pr-shepherd** handles them. This keeps one skill per review round.

## Step 7: Request review

▸ **Stage 7.**

1. **Resolve reviewers.** `--reviewers` given → add exactly those logins
   (`gh pr edit "$PR" --add-reviewer <login>` each, minus you), and they are the people the
   Slack message mentions (CODEOWNERS requests stay on GitHub, but aren't pinged). Skip to 2.
   Otherwise, if the PR already has requested reviewers (CODEOWNERS or branch
   rules usually add them on create: `gh pr view "$PR" --json reviewRequests`), use those
   and skip to 2. Otherwise use the request-pr-review registry's optional
   `default_reviewers` key for this repo (see its `references/config.md`), minus you. Set them:
   `gh pr edit "$PR" --add-reviewer <login>` for each. Note failures (not a collaborator),
   but they aren't blockers while at least one succeeds.
2. Run **request-pr-review** for `$PR` with these overrides:
   - **Its Step 3 (no reviewers):** only reached when the PR got no reviewers on create,
     `default_reviewers` is missing, or every add failed. Use the reviewers the ticket or plan
     names, if any; otherwise **BLOCKED** ("pass --reviewers, or add `default_reviewers`
     for <owner/repo>").
   - **Its Step 4/5 with `--reviewers`:** mention exactly those logins.
   - **Its Step 4 (a login with no Slack ID):** write the person's plain name, no mention, and
     note it. Never guess an ID.
   - **Its Step 6 (confirm):** skipped.
   - **No channel configured, or no Slack transport** → **BLOCKED**, and print the exact
     message for the user to post.

## Step 8: Update the ticket

▸ **Stage 8.**

Run **jira-update-issue** with these overrides:

- **Its Step 8 (show and wait):** skipped; post directly. Still one comment, never a
  transition, never a description edit.
- **Content:** its three sections, written from what this run produced: what the branch
  does (from the PR body), how it was checked (`$RUN/review.md`, `$RUN/sanity.md`, CI
  green), and what happens next (in review, with the PR link and reviewers).
- No ticket key, ticket not found, or no Jira transport → its degrade path: print the
  comment and the command, note it. Not a blocker.

Then run **jira-transition** `--to in_review --if-category new,indeterminate` (this run
authorizes it). A NOOP or a missing transport is fine; note it.

## Step 9: Report and release

A few plain lines:

- PR link, title, base, ready
- review rounds and what they fixed; sanity suites run with pass counts; services started
- CI result and fix attempts (or "no CI on this repo")
- diagrams included, or why not
- plan updated (path) or skipped (why)
- reviewers set, Slack link, ticket comment link (or "printed, not posted" and why), ticket
  status move
- early bot comments, if any, left for pr-shepherd

Make sure the checklist matches: on DONE every stage is `completed`; on BLOCKED exactly one
stage is `in_progress` and labelled with the blocker. Remove `$LOCK`. **The last line of
output is always exactly one of:**

```
RESULT: DONE
RESULT: NOOP (<why>)
RESULT: BLOCKED (<what you need from the user>)
```

---

## Principles

- **Blockers are the only prompts.** Confirmations are pre-answered; guardrails still hold.
- **Review covers what ships.** The head that gets published is the head a clean review
  round saw; any later local fix earns another round before the push.
- **Sanity runs are local and yours.** Use services this worktree started; never borrow,
  kill or reseed someone else's, and never touch a remote environment.
- **Green means green.** Fix what the branch broke, rerun flakes once, prove any
  "pre-existing" failure on the default branch before saying so.
- **No tickets.** Deferrals go in the PR's Future Tasks and the plan, never into new issues.
- **One skill per round.** pr-launch opens the PR and gets it to reviewers; every review
  round after that is pr-shepherd's.
- **The last line is the contract.** Exactly one `RESULT:` line.

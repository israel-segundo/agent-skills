---
name: pr-address-feedback
description: >-
  Take the new review feedback on the current branch's open pull request and drive it to
  done. Reads the comments posted since the remote head, translates and validates each one
  against the actual code, then renders the consolidated plan as a local HTML report and
  waits for sign-off before changing anything. Applies the valid fixes blocking-first,
  files a real ticket for everything deferred and records what was declined, runs the
  repo's own checks until they pass, commits, pushes on confirmation, then replies to and
  resolves the human threads in a relaxed tone — refreshing the report with real outcomes
  as it goes. Reads bot findings but never replies to them. Use when you want review
  feedback handled end to end rather than comment by comment. Idempotent: a re-run after
  pushing sees only genuinely new comments, and does nothing at all when there are none.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git/gh/jq) rather than
    host-specific tools, and degrades gracefully when a capability is absent. If your
    host has no skill support, read this file top to bottom and follow it directly.
when_to_use: >-
  Use when you want to address PR review feedback end to end on the current branch: pull
  the new comments, see a plain-language plan you can sign off on, fix what's valid, ticket
  what's deferred, verify, push, and close out the threads. Safe to run repeatedly. If a
  repo ships its own pr-address-feedback skill, that one wins: it knows the repo's
  conventions and its tracker.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
---

# PR address feedback (validate, confirm, fix, ticket, close out)

Read the new review comments on the current branch's open PR and take them all the way:
validate → **show a plan and confirm** → fix → capture deferrals as tickets → verify →
commit → push → reply → resolve.

**The defining stance: nothing gets silently dropped.** Every finding ends in exactly one of
four states — **fixed now**, **deferred into its own ticket**, **declined and written down**,
or **invalid, skipped, with the reason recorded**. Deferred and declined items must exist
somewhere durable *before* you push or post. A promise in a PR reply is not a record; it's a
thing everyone forgets by Thursday.

**The second rule: validate before you act.** A review comment is a claim about the code, and
some of them are wrong — the file moved, the concern was already handled, the reviewer read a
stale diff. Open the file and confirm the issue is real and still present before changing
anything. Applying an invalid finding is worse than ignoring it, because now the code is
wrong *and* a reviewer thinks it's fixed.

**Plain language and short.** Your reader is a colleague, not a linter. The report, the
replies, and the ticket bodies should sound like someone talking: short sentences, everyday
words, no hedging stacks. Concrete beats abstract. If a sentence has three qualifiers stacked
up, cut two.

### Guardrails (they apply throughout)

- **Never push, commit to a shared branch, post, or file a ticket without explicit
  confirmation.** Not all hosts prompt before running commands — assume none do. Invoking
  this skill is *not* standing consent, and a user-level rule against unprompted pushes
  overrides anything here.
- **Never push to the default branch or any protected branch.** This skill only ever pushes
  the current feature branch, and only ever with `--force-with-lease` when the remote has
  diverged — never a bare `--force`.
- **Read the command before you run it.** The repo's "test" script may migrate a database,
  seed shared state, or hit a live service. Skim it first, and honor documented
  prohibitions.
- **Reply to and resolve human threads only.** Bots get read, never answered.
- **Never dismiss a failing check as pre-existing without proving it.** Run it on the base
  branch or check the base's last CI run, then say which it was.
- **Keep every artifact local.** The report is a file on disk — never a hosted render or an
  uploaded page.
- **Use `gh` for GitHub, never raw API URLs through `curl`.** `gh api` covers what the `gh
  pr` subcommands don't: review comments, replies, and GraphQL thread resolution.

### Reference files (load when you reach the step that needs them)

- `references/discovery.md` — the remote and default branch, the repo's own rules, the
  verification command, the tracker and its transports, plan-doc discovery, bot detection.
  Needed at Steps 1, 4, 7 and 8.
- `references/findings-report.md` — the HTML report spec, the reply shape and tone, the
  thread-resolution mechanics, the gotchas that cost real time, and the length caps. Needed
  at Steps 5 and 10.

---

## Step 0 — Set up and probe what you can do

```sh
command -v git gh jq                             # gh and jq are near-essential here
REPO=$(git rev-parse --show-toplevel) || exit
WORK=$(mktemp -d)                                # findings, drafts, tickets, the report
mkdir -p "$WORK/tickets"
```

Note whether the host can open a local file in a browser (`xdg-open`, `open`, `wslview` —
otherwise you print the path), which tracker transports exist, and **which model and version
you are running as** if anything you post will disclose it.

Say which capabilities you have and which you don't. A missing tracker changes where deferred
items land, not whether they're recorded.

## Step 1 — Find the PR and the cutoff

```sh
gh pr view --json number,headRefName,headRefOid,url,state,baseRefName
OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

No open PR for this branch → stop and say so.

**The cutoff is the committer timestamp of the current head on the *remote*** — the PR's
`headRefOid`:

```sh
gh api "repos/$OWNER_REPO/commits/$HEAD_OID" --jq '.commit.committer.date'
```

Only comments created or updated **after** that timestamp are in scope. This is the whole
idempotency mechanism: once your fixes are pushed, the cutoff advances and the comments you
just handled fall out of scope on the next run.

> **If the branch was just rebased,** the remote head may be older than your local head. The
> cutoff is still the remote's committer date — comments are timestamped against what
> reviewers actually saw. It also means the push in Step 9 will need `--force-with-lease`.

Resolve the remote and base branch per `references/discovery.md`, and read the repo's own
rules while you're there.

## Step 2 — Collect the new comments

Three sources, and missing one looks exactly like ignoring it. **Paginate** — the default
caps at 30:

```sh
gh api --paginate "repos/$OWNER_REPO/pulls/$PR/comments" \
  --jq '.[] | {id, login: .user.login, created_at, updated_at, path, line, in_reply_to: .in_reply_to_id, body}'
gh api --paginate "repos/$OWNER_REPO/pulls/$PR/reviews" \
  --jq '.[] | {login: .user.login, state, submitted_at, body}'
gh pr view --json comments
```

Inline review comments are the resolvable threads. Review summaries and issue-level comments
carry real findings but can't be resolved — they get fixed, not closed out.

Filter to the cutoff, and write the in-scope set to `$WORK/comments.json` so later steps read
it from disk.

## Step 3 — Classify the reviewers

Split human from bot per `references/discovery.md`. **Read every bot finding** — a valid one
gets fixed or ticketed like any other. But bots never get a reply and never get a thread
resolved: it's noise on a machine's account, and it hides which threads a human is still
waiting on.

## Step 4 — Consolidate, validate, assign a disposition

Flatten everything in scope into one list with stable IDs, in `$WORK/findings.md`. For each
one, **open the referenced files and confirm the issue is real and still present.** Then
assign exactly one disposition, with the reason:

- **Fix now** — valid, and in scope for this PR.
- **Defer → ticket** — valid, but larger than this PR, out of its scope, or a team decision.
  A reviewer's open question that isn't a change request belongs here too.
- **Decline → record** — consciously not doing it: a cosmetic nit, an accepted tradeoff, a
  deliberate duplication. It goes in the plan doc, so it's visible rather than dropped.
- **Skip** — invalid, already handled, or outside the diff. Record why; this is the one
  disposition whose reason a reviewer is most likely to ask about.

Then:

- **Flag the blocking findings** — a reviewer marked it blocking, or it breaks the build.
  These get fixed first, in isolation (Step 6).
- **Don't silently re-architect.** A finding that's valid but large, ambiguous, or in
  tension with a deliberate decision another reviewer already approved is a *defer*
  candidate, or a question for the user at the Step 5 gate. It is not a licence to redesign.
- **Fetch the tracker context now**, so tickets come out wired correctly: read the issue
  named in the branch or PR for its parent, labels, and fix version, so follow-ups inherit
  them.
- **If nothing in scope needs a change** (everything skipped), that's the no-op path: say so
  and stop. No report, no commit, no push, no threads touched.

## Step 5 — Show the plan as a local HTML report, then confirm

This is the confirmation gate. Build the report per `references/findings-report.md`, open it,
and **stop**. State your recommended plan in a line or two of plain language and wait for an
explicit yes.

The report includes the "where the deferred items will live" table, which doubles as the
ticket draft — so signing off here also authorizes filing exactly those tickets. Anything
materially new after that gets shown before it's created.

Same file gets refreshed with real outcomes through Steps 6–10. It's the record, not a pitch.

## Step 6 — Apply the fixes, blocking first

- **Blocking and highest-risk first, de-risked in isolation.** Type-check or build just the
  touched package before batching the rest, so a bad assumption surfaces now instead of at
  the bottom of a large diff.
- Add or update tests for behavioral fixes. A bug fix without a regression test is a fix that
  comes back.
- Keep the edits scoped to the findings. A drive-by cleanup makes the reviewer re-review
  everything.
- Refresh the report's outcomes as you go.

## Step 7 — Capture the deferred and declined items — before any push or post

This is the step that makes the whole thing trustworthy. Do it **before** committing.

- **Deferred → a ticket each.** Ask the project which issue types exist rather than assuming
  (`references/discovery.md`), inherit the parent's labels, and link it to the branch's issue
  with whichever link type is actually configured. Write a real description: context, scope,
  and "surfaced on PR #N". A one-line stub is the same as no ticket.
- **No tracker transport?** Write each ticket body to `$WORK/tickets/` and hand the user the
  exact command. Say plainly that they aren't filed yet. Recorded-and-unfiled is acceptable;
  vanished is not.
- **Declined → the plan doc.** Add a short "Follow-ups and deferred (review)" section to the
  plan doc the branch is working from, listing the new ticket keys, anything already tracked,
  and each declined item with its reason. No plan doc in the repo? Put it in the PR
  description and say that's where it went — don't invent a convention the repo doesn't have.
- Refresh the report: real ticket keys in the deferred table, real outcomes in the actions
  column.

## Step 8 — Verify until it's green

Run the repo's own full check, discovered per `references/discovery.md` — the documented
command beats your inference, and never invent a script name. Loop until it passes.

Report red output **verbatim**. Never summarize a red run as "mostly passing", and never
wave a failure off as pre-existing without proving it on the base branch first.

## Step 9 — Commit, then push on confirmation

- Match the repo's commit convention as discovered in Step 1 — including any required
  trailer. If the repo documents a co-author or attribution trailer, use exactly that; if it
  doesn't, either omit it or name the model you are actually running as. Don't carry a
  hardcoded model name that may no longer be true.
- Reference the filed follow-up tickets in the commit body.
- **Stage only what you changed for this feedback.** Leave unrelated working-tree changes —
  a lockfile touched by an earlier rebase, a stray config edit — out of it.
- A plan-doc update from Step 7 is a natural **separate commit**. Prefer that over
  `--amend`: amending is a history rewrite, is often blocked, and is simply wrong once the
  commit is pushed.
- **Write the message to a file and commit with `-F`.** A multi-line `-m "$(cat <<EOF …)"`
  is the most host-fragile construct there is, and a bare `git commit` opens an editor that
  nothing will answer.

**Then ask before pushing.** On confirmation:

```sh
git -C "$REPO" push "$REMOTE" "$BRANCH"
git -C "$REPO" push --force-with-lease "$REMOTE" "$BRANCH"   # only if the branch was rebased
```

A pre-push hook may re-run the checks — let it. If it fails, fix and retry; never disable the
hook to get past it. If the push is refused by the host or a standing rule, **stop and ask** —
don't route around it.

## Step 10 — Reply to and resolve the human threads

Per `references/findings-report.md`: one reply per human thread, 1–3 sentences, relaxed and
first-person — what you did, the commit, and the ticket key for anything deferred. Then
resolve each human inline thread, and **verify by re-querying the unresolved count** rather
than trusting the loop's output.

Finish by refreshing the report footer with the pushed commits and the resolved-thread count,
then give the user a short summary: what was fixed, what was filed, what was declined, and
anything you couldn't do.

---

## Unattended runs

This skill is idempotent and safe to run repeatedly, including from a loop driver, a cron
job, or CI:

- Each run recomputes the cutoff from the *current* remote head, so once fixes are pushed,
  those comments are no longer in scope and won't be handled twice.
- If Step 4 finds nothing to change, it exits cleanly — no report, no commit, no push, no
  threads touched. "No new feedback" is the expected quiet outcome.
- Only human threads tied to in-scope findings get replied to, so a re-run doesn't spam
  threads that are already closed out.
- **Non-interactive is not a licence to skip the gates.** Without a human to answer, still
  write and refresh the report as the record, apply the smallest correct fix, defer anything
  ambiguous to a ticket rather than deciding it — and treat the push and post confirmations
  as *unmet*, so they don't happen. Report what's staged and waiting.

---

## Principles

- **Nothing evaporates.** Every finding is fixed, ticketed, recorded as declined, or skipped
  with a reason — and the deferred ones exist somewhere durable before anything is pushed.
- **Validate before you act.** A review comment is a claim about the code. Open the file.
  Applying an invalid finding leaves the code wrong *and* the reviewer satisfied.
- **Confirm before you change the world.** The report is the gate: sign-off on the plan
  before the edits, and a separate yes before the push and the replies.
- **Blocking first, in isolation.** Surface the bad assumption early, not at the bottom of a
  large diff.
- **Read bots, answer humans.** A valid bot finding is a finding. A reply to a bot hides
  which threads a person is still waiting on.
- **Discover the repo, don't assume it.** The verify command, the default branch, the commit
  convention, the tracker's issue types — all of it is in the repo or the tooling. Ask when
  it isn't.
- **Never dismiss a red check as pre-existing without proving it.** Run it on the base, then
  say which evidence you have.
- **Keep the edits scoped.** A drive-by cleanup makes the reviewer re-review everything.
- **Never rewrite published history to stay tidy.** A second commit costs nothing; an amend
  on a pushed commit costs someone else a conflict.
- **The report is a record, not a pitch.** Same file, same IDs, refreshed with what actually
  happened — including what you couldn't do.
- **Plain language, always — and short.** Respect the length caps. If it reads robotic,
  rewrite it before showing the user, and certainly before posting it.

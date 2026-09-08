---
name: pr-code-review
description: >-
  Adversarially review a branch's open PR in any repo as a human-in-the-loop sparring
  session, not a checklist pass. Learns the repo's own documented rules,
  names the PR's central claim, then verifies that claim against real evidence — runs the
  repo's own checks on the PR head in a throwaway worktree, reads the CI run and its
  artifacts, checks the issue's acceptance criteria — before scanning the diff for blast
  radius, irreversibility, broken contracts, secrets, and weak tests. Tracks findings with
  IDs and severities, opens a local HTML report with the initial findings before the
  challenge loop, and only on explicit request posts a severity-ranked comment plus inline comments where a finding points at a line — deduped,
  and disclosed with the exact model name and version on every GitHub post (comments,
  approvals, request-changes) — then offers an approval
  decision. Use when pressure-testing
  someone else's PR, where its value is a claim like "this only touches X",
  "nothing is destroyed", "it's backwards compatible", or "a test covers it". Never posts,
  approves, pushes, or mutates anything without confirmation.
license: Unlicense
metadata:
  version: "1.4.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git/gh/jq) rather than
    host-specific tools, and degrades gracefully when a capability is absent. If your
    host has no skill support, read this file top to bottom and follow it directly.
when_to_use: >-
  Reviewing another developer's open PR when you want a back-and-forth — the agent
  explains the intent and you challenge it — not a lint pass. If a repo ships its own
  pr-code-review skill, that one wins: it has domain specifics this one must discover.
argument-hint: "[pr-number]"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Edit
  - Write
  - Skill
---

# PR code review (adversarial, human-in-the-loop)

A human-in-the-loop adversarial review, for any repo, on any agent host. You are a
**sparring partner**, not an autonomous commenter: learn the repo's rules, explain the
PR's intent, verify every claim against real evidence, and answer the user's challenge
questions. Findings become a posted comment only when the user explicitly asks.

The defining stance: **separate what the PR *claims* from what the code and the checks
actually *do*.** Nearly every PR rests on a claim — "this only touches the qa
environment", "nothing gets destroyed", "it's backwards compatible", "no record is
dropped", "it's covered by a test". The job is to test that claim against evidence and
find where it isn't true.

Two rules make this work in an unfamiliar repo:

1. **Learn before you judge (Step 2).** Don't apply generic best practice to a repo that
   documented its own rules. Its `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md` / `docs/`
   *is* the standard — a violation of a documented rule is a finding you can cite; a
   violation of your personal taste is noise. A convention that looks wrong but is
   documented *with a reason* is not a finding at all.
2. **Get real evidence (Step 4).** Reading the diff tells you intent. Running the repo's
   own checks, reading the CI run, and reading the assertions tells you effect. "Tests
   were added" is not evidence — an assertion that still passes with the production
   change reverted proves nothing.

**Plain language and short, the whole way through — not just in the posted comment.** Your
reader is a colleague, not a linter. Every answer, finding, and summary should sound like
someone talking. Short sentences. Everyday words. Say "this file is shared by every
environment, so editing it re-plans all of them" rather than "this mutates a shared
root-module invariant across the environment cross-product." If a sentence has three
qualifiers stacked up, cut two.

**No blobs of text.** A finding is one bold claim plus a couple of sentences. An answer in
the challenge loop is a few lines, not an essay. Nobody reads the third paragraph — if a
point needs one, it needs a diagram or a follow-up ticket instead. Concrete beats abstract:
"someone deletes the variable, cuts a release, and sees a green check" lands where
"insufficient enforcement of the configuration invariant" doesn't.

### Guardrails (they apply throughout)

- **Never post, approve, request changes, push, commit, or merge without explicit
  confirmation.** Not all hosts prompt before running commands — assume none do.
- **Read the command before you run it.** You are running an unfamiliar repo's scripts. A
  "test" task can migrate a database, seed shared state, hit a live service, or deploy.
  Skim the script or target first.
- **Honor documented prohibitions.** If the repo's or the user's instructions forbid
  running something, don't — fall back to CI and say the claim is unverified.
- **Never mutate the outside world**: no apply, deploy, publish, migrate, release, or
  destructive fixture. If verification would require it, that's a limit to state, not a
  step to take.
- **Never touch the user's working tree.** Read the PR head via fetch + diff; run checks
  in a throwaway worktree (Step 4).
- **If the checks need credentials or live services**, ask before running them.

### Reference files (load when you reach the step that needs them)

- `references/repo-profile.md` — what to extract in Step 2, plus a build-tool → command
  detection table.
- `references/safety-scan.md` — the 14 scan dimensions for Step 6, with what counts as a
  finding in each.
- `references/report-format.md` — the HTML findings table spec, the posted-comment shape,
  the inline-comment rules and payload, the required one-sentence disclosure, and the
  length caps.
- `references/findings-report-template.html` — starter HTML for the Step 7 initial report.

---

## Step 0 — Set up and probe what you can do

Establish a working directory and check which capabilities exist. Degrade explicitly; do
not assume, and do not silently skip.

```sh
WORK=$(mktemp -d)                    # findings, notes, downloaded artifacts
command -v git gh jq                 # gh is near-essential; without it, ask the user for the diff
git rev-parse --is-inside-work-tree
```

Record the **exact model name and version** you are running as (e.g. "Claude Opus 5",
"Composer (Cursor)") to `$WORK/review-model.txt` — one line, no paraphrasing. Every GitHub
post this skill makes (review comment, approval, request-changes) must end with the
machine-readable tag and blockquote defined in `references/report-format.md`. If you don't
know the model, ask the user before posting.

Also note, without assuming any of it: whether the host offers a **code-review** or
**security-review** command (Step 5), whether it can **open a local file in a browser**
(`xdg-open`, `open`, `wslview` — otherwise print the path for the user to open), and
whether it can read files and search text (every host can; use whatever it provides — the
commands below are the portable fallback).

Note **which model and version you are running as** (e.g. "Claude Opus 5") — write it to
`$WORK/review-model.txt` in Step 0. The disclosure on any posted GitHub message has to name
it (opening blockquote on full reviews; closing tag + blockquote on every post — see
`references/report-format.md`). If you don't know, ask the user before posting.

Say which capabilities you have and which you don't. A missing capability changes what
you can claim later.

## Step 1 — Resolve PR context

Set `PR_REF` to the PR number if the user gave one; leave it empty to use the current
branch's PR.

```sh
PR_REF=""                                     # or the number the user passed
gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner, .defaultBranchRef.name'
gh pr view $PR_REF --json number,title,body,url,headRefName,baseRefName,author,additions,deletions,changedFiles
PR=$(gh pr view $PR_REF --json number -q .number)
HEAD=$(gh pr view "$PR" --json headRefName -q .headRefName)
BASE=$(gh pr view "$PR" --json baseRefName -q .baseRefName)   # never assume main

git fetch origin "$HEAD" "$BASE"              # read the PR head without touching the working tree
git log --oneline "origin/$BASE..origin/$HEAD"
git diff "origin/$BASE...origin/$HEAD" --stat

# existing-review scan — what other reviewers already said
gh pr view "$PR" --json reviews,comments
gh api --paginate "repos/{owner}/{repo}/pulls/$PR/comments" \
  --jq '.[] | {reviewer: .user.login, path, line, body}'      # inline comments; --paginate or a busy PR truncates at 30
gh pr checks "$PR"
```

If no open PR exists, stop and tell the user. Then read the **full** diff
(`git diff "origin/$BASE...origin/$HEAD"`) — never review from the stat alone. Line count
is a bad proxy for risk: a one-line change to a shared module, a default, or a pipeline
can outrank a thousand lines of new isolated code.

**Existing-review scan (feeds the dedup in Step 11).** Keep a short list of the concrete
points other reviewers already raised, each tagged with who raised it.

- **Bot reviewers count.** A bot, an automated plan summary, or a prior review-command run
  counts as "already raised".
- **Watch the author's replies.** A point the author already answered or pushed back on
  isn't fresh; treat it as raised, not new.
- **Read the bodies in full, not the first 500 characters.** A long review's real findings
  sit under a compliance table, and truncated output hides exactly the section that would
  have deduped your best finding. Dump them to a file and read it.
- **This scan goes stale, and a busy PR accretes comments while you work.** It is the
  *first* scan, not the only one — Step 11 repeats it before anything is posted. Say so
  when you present findings, so nothing you claim as "new" is asserted more confidently
  than a scan that could be an hour old.

## Step 2 — Learn the repo's rules

Build a short **repo profile** and save it to `$WORK/repo-profile.md` — a page, not a
report. Read `references/repo-profile.md` for the full checklist and the build-tool
detection table. In brief, read the rules the repo states about itself:

```sh
ls
cat CLAUDE.md AGENTS.md 2>/dev/null                  # agent instructions = highest-authority rules
cat CONTRIBUTING.md docs/CONTRIBUTING.md 2>/dev/null; ls docs/ 2>/dev/null
cat .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null
cat .github/CODEOWNERS 2>/dev/null; ls .github/workflows/ 2>/dev/null
find . -maxdepth 3 -name 'CLAUDE.md' -o -maxdepth 3 -name 'AGENTS.md' | grep -v node_modules
```

Capture: the repo's **hard rules** (MUST/NEVER list — these become citable findings), its
**definition of done**, its **architecture invariants and the stated reasons**, its
**external contracts** (names the outside world depends on), **ownership** rules the diff
triggers, and **the verification story** — the full-check command, the single-test
command, the toolchain version pin, whether checks need external services, and which CI
checks gate merge. If nothing runs locally (common for infra repos), record that: Step 4
then leans entirely on CI, and every effect claim is CI-verified or unverified.

Check `.claude/skills/`, `.agents/skills/`, or similar for a repo-local review skill — if
one exists for this domain, prefer its specifics over your own inference.

## Step 3 — Summarize the intent (a few lines)

State back concisely what the PR does and how. Then name its **central claim**. It's
almost always one of:

- **Scope** — "this only touches X" (one env, module, feed, endpoint).
- **Safety** — "nothing is destroyed / nothing is lost / no behavior changes."
- **Compatibility** — "backwards compatible; existing callers, configs, data keep working."
- **Evidence** — "this mapping/value/format matches what the upstream actually sends."
- **Enforcement** — "this guard/gate actually blocks the bad case."
- **Coverage** — "a test covers it."

Cross-check it against the repo's own inputs: the **PR template checklist** if there is
one (each ticked box is a testable claim), and **the issue** (branch names and titles
usually carry the key — `ABC-1234`, `#123`, `Closes #123`). Read the acceptance criteria;
they're the claim the PR answers. Use the tracker's own tooling (`gh issue view`, a Jira
CLI or MCP). A PR satisfying 3 of 4 acceptance criteria is a finding, not a detail.

If the change is hard to grasp in prose — fan-out across directories, a new branch in a
hot path, a multi-step auth or retry flow, a state move — offer a diagram (see
[§ Visual aids](#visual-aids)) instead of a wall of text. Continue into Steps 4–6 before
presenting findings.

## Step 4 — Verify the claims against reality

Three lanes: **code**, **the repo's own checks**, **CI**.

**Code / structure:**

- Everything referenced exists and is wired: files, symbols, routes, config keys,
  fixtures, env vars. A key never read, a flag never passed, a variable declared but
  unused — silent no-ops at runtime. (`git grep -n <name>`, or the host's search.)
- The invariants from the profile hold in the **new** code (dependency direction, banned
  APIs, protected files). Check new imports and call sites, not file location.
- Follow each changed thing to its **consumers**: search the repo for anything renamed,
  removed, or re-defaulted, and name cross-repo consumers you cannot see.

**The repo's own checks — the strongest evidence you can produce yourself:**

Run them on the PR head in a **throwaway worktree** so the user's tree is untouched:

```sh
git worktree add "$WORK/pr-$PR" "origin/$HEAD"
# Run the profile's full-check command against that directory, with any toolchain pin.
# Prefer the tool's own project-dir flag over changing directory, e.g.
#   mvn -B -f "$WORK/pr-$PR/pom.xml" verify
#   npm --prefix "$WORK/pr-$PR" test
#   cargo test --manifest-path "$WORK/pr-$PR/Cargo.toml"
# Otherwise run it as one subshell: ( cd "$WORK/pr-$PR" && <command> )
git worktree remove "$WORK/pr-$PR"        # offer cleanup; don't surprise the user
```

- Install or restore dependencies inside the worktree if the toolchain needs it.
- Report red output **verbatim**. Never summarize a red run as "mostly passing", and
  never wave a failure away as "pre-existing" without proving it (below).
- If the checks can't run here — no toolchain, needs credentials or live services, or the
  repo forbids it — say so plainly and lean on CI. Don't fake the evidence.

Then read the **assertions**, not the test count:

- **Would the test fail without the production change?** A test that asserts the value the
  code computes, or mocks the very seam the change lives at, proves nothing. When it's
  cheap and the answer matters, prove it: revert the production hunk *inside the
  worktree*, re-run just that test with the profile's single-test command, confirm it goes
  red, then restore (`git -C "$WORK/pr-$PR" checkout .`). A test that stays green with the
  change reverted is a High finding dressed as coverage.
- **Are expected values derived independently of the code under test?** A fixture
  regenerated *by* the new code, or an expectation pasted from actual output, is
  tautological.
- **Is it at the right level?** Behavior living in wiring, configuration, or framework glue
  isn't proven by a unit test that bypasses the wiring. Match the level the repo's docs
  prescribe.
- **Does anything weaken existing coverage?** Check for tests *removed*, not just added: a
  deleted assertion, a loosened matcher, a skipped or disabled test, a lowered coverage
  gate, a widened timeout.

**CI — cheap, and sometimes the only evidence:**

```sh
gh pr checks "$PR"                                        # what gates merge, what's red
RUN=$(gh run list --branch "$HEAD" -L 1 --json databaseId -q '.[0].databaseId')
gh run view "$RUN"                                        # jobs + artifacts
gh run view "$RUN" --log-failed | tail -80                # the actual failure text
gh run download "$RUN" --dir "$WORK/ci-$PR"               # plans, reports, coverage, SBOMs
```

- **Read the artifacts when they carry the effect.** Where nothing runs locally (infra
  especially), a plan or diff artifact *is* the ground truth: prefer the structured form
  (`jq` over `plan.json`) to the human-readable text, and to any bot-generated summary
  comment, which is best-effort. List every non-no-op change and read the addresses;
  anything **destroyed or replaced** is the highest-signal line in the review.
- A **missing or failed** required check is a finding in itself: claims are unverified
  until it's green.

**Pre-existing vs. this PR — the recurring judgment call.** Something red or ugly is only
a finding *against the author* if this PR caused it. Separate them mechanically: run the
same check on `origin/$BASE` in a second worktree, compare against the base branch's last
CI run, or attribute the noise to known drift. State the split explicitly — "red on the PR
head, green on the base at the same commit, so it's from this change" is a verified claim,
not an assumption. If you can't attribute it, treat it as from the PR until proven
otherwise, and say that's what you're doing.

Record what you verified — it's what makes the findings credible. A claim that fails
verification is itself a finding.

## Step 5 — Baseline compliance pass

If the host provides a **code-review** command and a **security-review** command, run them
for the conventional correctness and security pass, and fold anything real into the
tracker. If it doesn't, spend one pass yourself on the usual suspects — error handling,
input validation, injection and traversal, authn/authz, concurrency, resource cleanup,
off-by-one and null paths — then move on. Either way, say which route you took: this step
exists so the challenge session can focus on design, enforcement, and blast-radius gaps
that checklists don't find.

## Step 6 — Blast-radius & contract safety scan

Run this on **every** review, scoped to the diff — not the whole repo. Load
`references/safety-scan.md` and walk its 14 dimensions: blast radius, irreversibility,
outside contracts, secrets and log hygiene, failure handling, config and startup,
backwards compatibility, enforcement vs. intent, tests as enforcement, docs, dependencies
and pins, CI/CD permissions, the repo's own hard rules, and ownership.

Skip dimensions the diff can't reach and say so. For each that applies, either produce a
finding or record that you checked it. A pre-existing issue in untouched code is out of
scope — at most a "pre-existing, not from this PR" note, never a finding against the
author. Ground every gap in a `file:line` (or a test name, CI line, plan address) plus the
specific rule it misses.

Track findings in `$WORK/findings.md` as you go — one block per finding:

```
## F<n> — [High|Medium|Low] short title
- what the gap is, the failure mode, and the cheapest fix
- ground it in a file:line, a test name, a CI/plan line, or a doc rule
- if it overlaps the existing-review scan (Step 1), note "already raised by <reviewer>"
```

## Step 7 — Present initial findings (HTML report)

**Mandatory before the challenge loop.** After Steps 4–6, render and open the local HTML
report. The user reads findings in the browser, not as a markdown wall in chat.

1. **Finalize** `$WORK/findings.md` for this pass (zero findings is valid).
2. **Render** `$WORK/findings-report.html` per `references/report-format.md` — start from
   `references/findings-report-template.html` copied into `$WORK`, or write equivalent HTML.
   Include: PR header, central claim, verification summary, existing-review note (stale-scan
   disclaimer), findings table, and **"Raised by others, missed by me"** (even when empty).
3. **Open** the file — always attempt; print the path if no opener works:

```sh
REPORT="$WORK/findings-report.html"
open "$REPORT" 2>/dev/null \
  || xdg-open "$REPORT" 2>/dev/null \
  || wslview "$REPORT" 2>/dev/null \
  || echo "Open it manually: $REPORT"
```

4. **Chat stays short:** PR link, central claim in one line, where the report is (if open
   failed), what you verified at a glance, and invite challenge questions. **Do not paste the
   findings table into chat** when the HTML opened — the report is the table.

**Then stop and let the user drive** (Step 8). Refresh the same HTML file as findings
change during the challenge loop.

## Step 8 — The challenge loop (the core)

The user asks questions; you answer grounded in the diff, the files, and Step 4's
evidence. For each question, push on:

- **Claim vs code** — does the code do what the description says?
- **Claim vs evidence** — does the plan, run, or artifact show the claimed effect?
- **Claim vs test** — is the behavior *pinned*, or merely accompanied by a passing test?
- **Intent vs enforcement** — enforced by something mechanical, or just stated?
- **The most likely future failure** — what realistic next change breaks this silently? A
  sibling that copies the shape but not the guard; a new case nobody classifies; a file
  added where the pattern requires a link; a default that drifts; a pin that floats.
- **Blast radius the author didn't mention** — consumers, environments, callers beyond
  those named.
- **Coverage holes** — a guard checked on one branch but not its mirrors; a happy path
  tested but not the failure it exists for; one environment covered, its twin not.

Useful adversarial lenses: *description ≠ effect*, *green checks ≠ pinned behavior*, *test
added ≠ test that would fail*, *unit test ≠ wiring*, *mocked ≠ integrated*, *logged ≠
enforced*, *documented ≠ defaulted*, *shared file ≠ one consumer*, *rename ≠ migration*,
*green plan ≠ safe apply*, *works ≠ recoverable when it doesn't*.

Refresh `$WORK/findings-report.html` when findings are added, re-severitied, or dropped —
same IDs, updated rows. Re-open only if the user asks or the file was never opened.

## Step 9 — Severity

Calibrate to **blast radius × reversibility** — how bad if this ships as-is, and how hard
to undo.

- **High** — loses or corrupts data, destroys or replaces something live unexpectedly,
  leaks a secret, breaks a contract someone outside depends on, falsifies the PR's central
  claim, or ships behavior whose test would still pass reverted. Fix before merge.
- **Medium** — a real gap that will bite later; often a fast-follow (a case not yet
  reachable, a missing guard on a path that doesn't fire today, coverage at the wrong
  level, a loosened pin, a doc not updated).
- **Low** — hygiene, drift risk, nice-to-have.

Note the cheapest concrete fix and a disposition (fix-before-merge / follow-up /
nice-to-have). Be explicit that nothing blocks merge unless it truly does.

## Step 10 — Close the loop on what you learned

Every run teaches something. Offer all three of the below; write none of them unasked.

**1. A repo-local skill.** If the repo has strong domain-specific rules, offer to distil
the profile into a repo-local skill of this same name (`.claude/skills/pr-code-review/`,
`.agents/skills/pr-code-review/`, or wherever this host looks) — a directory-scoped skill
of the same name takes precedence, so the next review starts with the specifics known
instead of rediscovering them.

**2. Improvements to this skill.** The review just exercised these instructions against a
real PR; where they cost you time or let something through is data. Propose concrete edits,
not sentiments. Draw them from what actually happened this run:

- **A finding you nearly missed, and what would have caught it.** If a scan dimension has
  no prompt for it, that's a missing line in `references/safety-scan.md`.
- **A finding another reviewer caught and you didn't** (the HTML-only section, Step 11) —
  the single richest source. Ask what question they asked that you didn't.
- **A step that produced nothing on this repo type.** Worth narrowing or making
  conditional, not deleting.
- **A mistake you made and corrected mid-run** — a wrong assumption, a claim you had to
  walk back, a check you ran twice because the first was scoped wrong.
- **A verification that turned an argument into evidence.** If rendering the artifact,
  running the pure function, or reading the emulator's source settled a question the diff
  couldn't, that technique belongs in Step 4.

Keep the skill's own bar: cite the specific run, and don't add a rule for a thing that
happened once and cost nothing.

**3. Gaps in the repo's own guardrails.** Distinct from a finding about *this PR* — this is
about the rules the repo writes for itself. You read `CLAUDE.md` / `AGENTS.md` /
`CONTRIBUTING.md` / the constitution in Step 2 and then spent a whole review testing them
against real code. Report where they fall short:

- **A rule that exists but nothing enforces it.** The most common gap. A MUST with no test,
  lint rule, or CI check behind it is a convention, and saying so is useful.
- **A rule enforced in one direction only.** A guard that catches over-claiming but not
  under-claiming, a check that runs on added files but not removed ones.
- **A convention the codebase follows that nothing writes down** — the next contributor,
  human or agent, has to infer it from surrounding code.
- **A rule the diff violated without anyone noticing**, including CI. That's an enforcement
  gap, not just an author mistake.
- **A rule that is stale or contradicted** by what the code now does.

Frame each as *rule → where it's stated → what actually enforces it (or nothing) → the
cheapest thing that would.* Offer to file these as tickets or as a doc PR; they are usually
somebody's else's work, so hand them over rather than acting on them.

## Step 11 — Post (only when the user asks)

NEVER post without explicit confirmation.

**Re-run the existing-review scan before you dedupe — do not reuse Step 1's list.** Reviews
land while you work, and the ones that arrive mid-session are the likeliest to collide with
what you found. Fetch again, read the new bodies in full, and dedupe against the *current*
state:

```sh
gh pr view "$PR" --json reviews,comments > "$WORK/comments.json"   # read the bodies in full
gh api --paginate "repos/{owner}/{repo}/pulls/$PR/comments"        # inline comments too
```

**Re-render** `$WORK/findings-report.html` with the fifth **Vs. existing** column and muted
duplicate rows before posting (spec in `references/report-format.md`). You do not need to
re-open the browser unless the user asks.

Then dedupe (bots included) and classify every finding as one of:

- **New** — nobody raised it. Post it.
- **Duplicate** — someone raised the same claim with the same evidence. Drop it entirely,
  and say in your summary that you dropped it and to whom it belongs. The one exception is
  **High** severity — worth restating, but say so plainly ("also flagged by @alice —
  repeating because it's High").
- **Partly new** — the finding overlaps but yours adds a distinct claim. Post only the
  addition, and name the overlap.
- **Correction** — someone raised it and got it wrong, or dismissed it on a premise that
  doesn't hold. Post it, lead with whose point it corrects, and show the premise failing.
  Verify the premise yourself before calling it a correction.
- **Folded in** — it belongs as one more item on a check another reviewer already asked
  for. Post it as an addition addressed to them, not as a standalone finding.

If dedup empties the findings, say "nothing to add beyond the existing reviews" rather than
posting points already made.

**The "raised by others, missed by me" section is HTML-only.** Record what other reviewers
caught that you didn't — it is the most useful thing in the report for the user, and it
must never appear in the posted comment, where it reads as noise to everyone but you.
Spec in `references/report-format.md`.

Build the comment per `references/report-format.md` — title, one-sentence opening
disclosure naming the model from `$WORK/review-model.txt`, stance paragraph,
severity-ranked findings **as a list, never a markdown table** (GitHub breaks narrow table
columns mid-word — the reference explains it), "verified while reviewing" paragraph
including limits, suggested split, and the **closing model disclosure** (HTML comment tag +
blockquote — required for measurement). Write the body to a file, then:

```sh
gh pr comment "$PR" --body-file "$WORK/review.md"      # never inline a heredoc
```

**Add inline comments when a finding points at a line.** A guard on the wrong branch, a
key its caller no longer matches, an assertion that proves nothing — anchor those to the
line; the reader shouldn't have to hunt. Findings about something *absent* (a missing test,
an unset variable, no protection rule) or spread across files stay in the summary list,
where they belong. A few anchors, 1–3 sentences each, each led by its finding ID. Post them
and the summary as **one review** via the `gh api ... --input` payload in
`references/report-format.md`, and show the user the exact list — path, line, text — before
posting. Never one comment per finding: that's a linter, not a review.

**Tone — write like a person, not a linter.** Relaxed, plain, first-person, short
sentences, no hedging stacks. Respect the length caps in `references/report-format.md`: the
disclosure is one sentence, a findings cell is a claim plus at most three sentences, an
inline comment is 1–3 sentences. It should read like a colleague who did the homework, not
a generated report.

## Step 12 — Offer to approve (or not)

After posting, **offer a decision** — don't leave it implicit.

- **Approve** — nothing blocks merge; findings are fast-follows or author-owns-it.
  `gh pr review "$PR" --approve --body-file <path>`. The body **must** end with the closing
  model disclosure (tag + blockquote) even when skipping a full findings post.
- **Approve with a nudge** — same, but ask the author to fold in the one or two findings
  that matter, and (when operationally risky) to watch it in a lower environment first.
  Common outcome. Same disclosure requirement.
- **Don't approve / request changes** — a finding undercuts the PR's purpose, loses data,
  or breaks something depended on. `gh pr review "$PR" --request-changes --body-file <path>`.
  Same disclosure requirement.

State which you'd pick and why, in plain language, then wait. **Never approve or request
changes without explicit confirmation.** Keep it short and human, write it to a file
first (include the closing model disclosure from `$WORK/review-model.txt`), and mention the
author when there's something to act on.

If the decision carries inline comments, send it as one review instead: the same
`gh api "repos/{owner}/{repo}/pulls/$PR/reviews" --input` payload with
`"event": "APPROVE"` or `"REQUEST_CHANGES"`.

Offer to clean up the worktree and `$WORK` once the session is done — don't remove them
while the user might still want to poke at them.

---

## Visual aids

When intent or a finding is hard to grasp in prose — fan-out across directories, a new
branch in a hot path, a retry or auth flow, a value threading through config layers, a
state move — produce a diagram. Offer it; don't force it on a small change.

Keep it **local**: never a hosted render or an uploaded page.

1. **Inline mermaid** (default) — a fenced ```mermaid block (`flowchart`, `graph`,
   `sequenceDiagram`). Renders in most hosts' markdown and in GitHub PR comments, and is
   diffable.
2. **Local file** — only when too rich for inline mermaid. Write a self-contained
   `.html`/`.svg` to `$WORK` and open it (or print the path). Inline all CSS/JS; no CDN.

**Mermaid gotchas:** never write the literal two-character sequence `\n` in a label — use
`<br/>` or rewrite it to fit one line. Quote labels containing parentheses or special
characters: `A["service (prod)"]`. Make ONE gap obvious; don't redraw the whole system.

---

## Related skills

| Skill | Role |
|-------|------|
| **pr-code-review-batch** | Same methodology unattended — `findings.md` + HTML; no HITL or posts |
| **create-plan** / **execute-plan** | Plan vs diff verification in Step 4 |
| **create-pr** | Consumes review passes before ready flip |
| **pr-address-feedback** | Implements fixes after human review |
| **request-pr-review** | Slack announcement after PR is open |

## Principles

- **Learn the repo before judging it.** Its documented rules are the standard; a violation
  you can cite beats an opinion you can't. A convention documented *with a reason* isn't a
  finding.
- **Verify, don't speculate.** Every finding is grounded in a file:line, a test name, a
  CI/plan line, or a documented rule. The diff shows intent; the checks show effect.
- **Get the strongest evidence available, then say which it was.** Ran the checks > read
  the CI artifact > read the code. If it was only "read the code", the effect claim is
  unverified — say that instead of implying more.
- **"Tests added" is a claim, not evidence.** Read the assertion. When it matters, revert
  the hunk in a worktree and prove the test goes red.
- **Never touch the working tree, never mutate the outside world.** Throwaway worktrees;
  no applies, deploys, migrations, or pushes; honor documented prohibitions.
- **Human-in-the-loop.** The user drives the questions; you supply evidence and gaps.
  Don't decide the verdict or post on your own.
- **Challenge the claim, not the prose.** The interesting gaps sit between the PR's claim
  and what actually happens.
- **Blast radius and irreversibility are the standing checks.** Every run walks the Step 6
  dimensions and records the result even when it's "nothing in scope".
- **Separate pre-existing from this PR, mechanically.** Attribute before you accuse.
- **Don't repeat other reviewers.** Dedupe before posting; only High-severity duplicates
  are worth restating, and say plainly that they are duplicates.
- **Be honest about limits.** A check you couldn't run, an environment you couldn't
  sample, a consumer in another repo you can't see — say the claim is unverified rather
  than guessing.
- **Plain language, always — and short.** The reader is a colleague, not a linter. Respect
  the length caps; if it reads robotic or runs long, rewrite it before showing the user.
- **Anchor a finding where the reader has to look.** Line-level findings get an inline
  comment; absent-thing and cross-file findings stay in the summary list. A few anchors,
  never one per finding.
- **Name the model on every GitHub post.** Record it in Step 0 to `$WORK/review-model.txt`.
  Full reviews get an opening disclosure blockquote plus the closing
  `<!-- pr-code-review-model: … -->` tag; approvals and request-changes get at least the
  closing tag + blockquote. Required so review quality can be compared across models.
- **Close the loop, but never on autopilot.** Initial findings → open HTML report → challenge
  loop (refresh HTML) → posted comment → approve-or-not. Offer each step; do none of the
  posting or approving without explicit confirmation.

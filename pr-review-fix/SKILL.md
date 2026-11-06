---
name: pr-review-fix
description: >-
  Run the repo's PR review in rounds and fix every finding it returns — Must Fix, Should Fix
  and Nits alike — landing it all as one commit, and stop when a round comes back clean.
  Nothing is deferred, ticketed, or handed back as "your call": if the reviewer raised it,
  this skill fixes it. Resolves the review pass and verify gate from the repo's own docs and
  build files — not from hardcoded Node or npm assumptions. Use after local implementation
  and before opening or updating a PR, when you want review cycles to converge without a
  trail of "address review comment" commits. Never pushes.
license: Unlicense
metadata:
  version: "2.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git) rather than
    host-specific tools, and degrades gracefully when a capability is absent. Review pass
    and verify gate are discovered per repo from docs, CI, and build markers.
when_to_use: >-
  Local pre-PR review cycles on a feature branch you own, when you want the branch left
  clean rather than left with a to-do list. Fixes every finding a round returns. If a repo
  ships its own pr-review-fix skill, that one wins.
argument-hint: "[PR number] [--max-rounds N] [--fast]"
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
  - Edit
  - Task
---

# PR review → fix → converge

Drive the review-and-fix cycle to convergence in one invocation, and land the whole thing as
**one commit** rather than a trail of "address review comment" commits.

Each round: review the change, **fix everything the round returned**, verify, then commit
(round 1) or amend (round 2+). Stop when a round comes back with **no findings**.

**Fix everything. Defer nothing.** There is no deferral ledger, no follow-up ticket, and no
"your call" section in the summary. A finding the reviewer raised is a finding this skill
closes. The only things that stop the loop are the safety conditions in Step 3 — a red gate, a
tripped amend guard, a fix that will not hold, the round cap — and none of them is a judgment
that a finding was not worth fixing.

**This skill never pushes.** It prints the push command and stops.

> **Why this is not a `/loop`.** `/loop` waits on external state — CI turning green, new PRs
> appearing. This cycle is local and synchronous. Running the rounds inside one session keeps
> the **fix ledger** in context, so each round's reviewer knows what the last round already
> changed and re-reviews it instead of re-discovering it. Do not wrap this in `/loop`.

### Reference files (load when you reach the step that needs them)

- `references/review-pass.md` — Step 0a: which review pass to run
- `references/verify-gate.md` — Step 0b: which verify command to run

---

## Step 0 — Resolve the environment

This skill is portable, so it runs in whatever repo you are standing in. Resolve three things
before doing anything else, and **print what you resolved** so the run is auditable.

```sh
REPO=$(git rev-parse --show-toplevel) || exit
command -v git
```

### 0a — The review pass

Follow `references/review-pass.md`. Record the resolved path or skill name.

Not every review pass emits Polish/Behavioral labels. That no longer changes *whether* a
finding gets fixed — everything does — but it does change how carefully you verify the fix
(Step 2b), so say in the final summary when the labels came from your own judgment rather than
from the reviewer.

### 0b — The verify gate

Follow `references/verify-gate.md`. Record the **exact command(s)** you will run, including
container wrappers, env files, or working-directory requirements the repo documents.

**No gate found → stop.** Do not commit anything.

### 0c — Preconditions

Resolve the default branch — never assume `main` or `origin`:

```sh
REMOTE=$(git -C "$REPO" remote | head -1)
REMOTE=${REMOTE:-origin}
git -C "$REPO" remote set-head "$REMOTE" -a >/dev/null 2>&1 || true
DEFAULT=$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s|^$REMOTE/||")
[ -n "$DEFAULT" ] || DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main)
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
```

Then:

- **Not on `$DEFAULT`.** If you are on the default branch, stop — this skill commits, and
  committing review fixes directly to the default branch is never right.
- **`git status` is clean enough:** note every pre-existing modified and untracked file **by
  name** now. These are your "not mine" list. Stage by name later; never sweep them in.
- Record the starting `HEAD` SHA as `BASE_SHA`.

---

## Step 1 — Resolve the scope

- If the invocation contains a **PR number**, pass it to the review pass so it loads prior
  review state. Findings a human already answered on the PR — accepted, disputed, or explained
  — are context for the reviewer, not permission for this skill to skip them: if the round
  still returns the finding, fix it.
- Otherwise review the local branch: `git diff "$DEFAULT"...HEAD` plus the working tree.

Flags:

| Flag | Effect |
|---|---|
| `--max-rounds N` | Round cap. Default **5**. Raise it when the first round returns a long tail of nits, since every one of them gets fixed. |
| `--fast` | Scoped static-analysis / compile portions per round; full gate once before the final amend. See `references/verify-gate.md`. |

---

## Step 2 — The round loop

Repeat until a termination condition in Step 3 fires.

### 2a — Review (fresh subagent, every round)

Spawn a **fresh general-purpose subagent** to run the resolved review pass. Do not review
inline: by round 2 the main session wrote the code under review, and a self-review of your
own edit is biased toward "looks fine".

Hand the subagent:

- the review pass to execute (from Step 0a) and the scope from Step 1;
- the **fix ledger** — every finding fixed in a previous round, with its id and what changed.
  Ask the reviewer to check those fixes rather than re-raise them: a fix that was wrong,
  incomplete, or that broke something adjacent is exactly what a later round is for. Say
  explicitly that a previously-fixed finding may be raised again **if the fix did not hold**,
  and should not be raised again otherwise.

Ask it to return findings as structured JSON, one object per finding:

```json
{
  "id": "R1-01",
  "bucket": "must-fix | should-fix | nit",
  "shape": "polish | behavioral",
  "recommendation": "fix-in-pr | split | null",
  "path": "src/main/java/Foo.java",
  "line": 42,
  "summary": "one sentence",
  "fix": "the concrete change to make"
}
```

Tell the reviewer an **empty array is a valid and expected answer** on a clean branch, and that
inventing findings to seem thorough is worse than returning none — under this skill every
finding it returns will be applied.

### 2b — Triage

**Every finding is fixed.** There is no DEFER column.

| Finding | Action |
|---|---|
| **Must Fix**, any shape, any recommendation | **FIX** |
| **Should Fix**, any shape | **FIX** |
| **Nit**, any shape | **FIX** |

Triage is therefore not about *whether* to fix, only about *how* — and that is what the
polish/behavioral distinction is still for:

> **The Polish test.** Would applying this fix change what the code *does* for any input —
> return value, side effect, emitted log, stored document, rendered output, or timing? If yes,
> it is **behavioral**. If it only changes how the code reads — naming, formatting, comments,
> dead-code removal, a redundant cast, an import order — it is **polish**.

- **Polish** — apply it and let the gate confirm nothing moved.
- **Behavioral** — apply it, and **add or update a test that fails without the fix**. A
  behavioral fix landing with no test is how the next round finds it again. If the repo's
  conventions say where that test goes (Step 2c), follow them.
- **When unsure, treat it as behavioral.** The cost is a test you did not strictly need.

Two cases need a note in the final summary rather than different handling:

- A finding the reviewer marked `split` (it thinks the fix belongs in separate work) is still
  fixed here. Say so in the summary, and say what it widened, so the scope change is visible
  in review rather than buried.
- A finding whose fix would touch code outside this repo, or is blocked on something this
  session cannot reach (a missing credential, an upstream contract, a decision only a human
  holds), cannot be fixed by anyone here. That is **BLOCKED** (Step 3) — a physical
  constraint, not a judgment call — and it stops the run rather than being written down and
  skipped past.

### 2c — Apply the fixes

- Honour the repo's own rules. Read `CLAUDE.md`, `AGENTS.md`, and contributor docs if present.
- One finding, one focused edit. **Do not opportunistically refactor adjacent code.** This
  matters more here than in a skill that defers: when every finding gets fixed, every extra
  line you touch is new surface for the next round to find something in, and that is the main
  way this loop fails to converge.
- Fix the finding that was raised, at the scope it was raised at. If a finding reveals a
  larger problem, fix the finding and note the larger problem in the summary.
- Keep a per-round record of `finding id → files touched → what changed`. It is both the amend
  message and the next round's fix ledger.

### 2d — Verify

Run the gate from Step 0b (or the scoped subset under `--fast`).

**On failure, fix and re-run — capped at 3 attempts per round.** Past 3, stop and report BLOCKED
with the failing output.

**Attribution rule — never write a failure off as "pre-existing" without proof.** If a failure
looks unrelated to this round's edits:

1. Stash this round's edits, capturing the stash **commit SHA** from `git stash create` /
   `git stash push` output — do **not** refer to it as `stash@{0}`.
2. Re-run **that failing step alone** on the clean tree.
3. Restore the stash by the SHA you captured.
4. If it failed clean too, it is genuinely pre-existing: continue, and surface it prominently in
   the final summary. If it passed clean, it is yours — fix it.

### 2e — Commit (round 1) or amend (round 2+)

**Staging, both cases:** `git add <path> …` **by name**, listing only files this skill edited.
Never `git add -A`, never `git add .`. Cross-check against the "not mine" list from Step 0c.
Refuse to stage anything that looks like a credential (`.env*`, `*.pem`, `*.key`, `*secret*`) —
stop and ask instead.

**Round 1 — create a new commit.** Never amend a commit that already existed on the branch.

- Follow the repo's commit message conventions (commitlint config, hook scripts, or
  `CONTRIBUTING.md` if present). When no convention is documented, use conventional commits:
  scope from the ticket in the branch name (`user/type/PROJ-123-thing` → `proj-123`,
  lower-cased). Header ≤ 100 chars when commitlint is present.
- Suggested subject: `fix(<scope>): address review findings`
- Body: one bullet per finding fixed, `<id> — <summary>`.
- **Record the resulting SHA as `FIX_SHA`.** Everything after this amends that one commit.

**Round 2+ — amend `FIX_SHA`.**

- **Amend guard, checked every time:** `git rev-parse HEAD` must equal `FIX_SHA`. If it does not,
  something else committed in between — **stop immediately** and report.
- `git commit --amend` and extend the message with an `## Amendments` round, matching the
  `git-amend` skill convention:

```
## Amendments

### Round 2
- src/main/java/Foo.java — guard the null branch flagged by R2-01
- src/test/java/FooTest.java — regression test for the above
```

Append a new `### Round N` block each round; never rewrite earlier ones.

### 2f — Report the round (every round, no exceptions)

**Print this table at the end of every round, before starting the next one.** It is
informative — nothing in the loop branches on it — but it is not optional: it is the only place
the user sees what a round actually found while the run is still going, and a run that only
reports at the end hides its reasoning until it is too late to redirect.

```
#### Round N — <k> findings

| Severity | Description | Disposition |
|---|---|---|
| Must Fix | RN-01 `src/main/java/Foo.java:42` — null branch is unguarded, NPEs on an empty batch | Fixed |
| Should Fix | RN-02 `docs/DOMAIN.md:118` — the recorded figure predates the mapping change | Fixed |
| Nit | RN-03 `src/main/java/Bar.java:9` — `{@link}` points at a renamed method | Fixed |
```

- **Severity** — the reviewer's bucket, verbatim: Must Fix / Should Fix / Nit.
- **Description** — lead with the finding id and `path:line`, then one clause saying what is
  wrong. Keep it to a line; the detail is in the commit message.
- **Disposition** — one of:

| Disposition | When |
|---|---|
| `Fixed` | The overwhelming default. Every finding lands here unless one of the rows below applies. |
| `Fixed, scope widened` | The reviewer marked it `split` and it was fixed here anyway. Say in one clause what it widened. |
| `Not a defect — <evidence>` | You **verified** the finding is factually wrong. Rare, and the evidence goes in the cell — the file and line, the value you actually measured, the test that already covers it. A reviewer can be wrong, and applying a wrong fix is worse than not applying it; "I disagree" is not evidence, and this is not a place to park work you would rather not do. |
| `Unfixed — <Step 3 condition>` | Only on a BLOCKED run: the gate stayed red, the amend guard tripped, the fix would not hold, the cap was reached, or it cannot be fixed from this repo. |

**A round that found nothing still prints the header** — `#### Round N — 0 findings` — so the
clean round that ends the run is visible rather than inferred from the run simply stopping.

---

## Step 3 — Termination

**DONE** — a round's review returns **no findings at all**. Not "no Must Fix": this skill fixes
every bucket, so a round that returns three nits is a round with work left in it.

**BLOCKED** — any one of:

- a finding that cannot be fixed from this repo or this session (Step 2b's second note);
- the verify gate not green after 3 attempts in a round;
- the amend guard tripped;
- the same finding id/`path:line` survives two consecutive fix attempts — the fix is not
  holding, and a third identical attempt will not help;
- `--max-rounds` reached with findings still outstanding;
- no verify gate resolved (Step 0b).

Both outcomes print the Step 5 summary. **Neither pushes.**

A BLOCKED run with outstanding findings lists them as **unfixed**, with the reason the loop
stopped. That is a report of where the run ran out of road, not a recommendation to leave them.

---

## Step 4 — Making it converge

Fixing every bucket removes the old failure mode — a Must Fix the loop was not allowed to touch,
so the list never emptied — and introduces a different one: **each round's fixes are new code,
and new code attracts new findings.** A run that never terminates is almost always doing one of
these:

- **Refactoring past the finding.** The single largest cause. Fix what was raised, nothing
  adjacent (Step 2c).
- **Rewriting prose the reviewer merely questioned.** A comment or doc line that was flagged as
  wrong needs correcting, not expanding — a longer replacement gives the next round more to
  read and more to disagree with.
- **Fixing a behavioral finding without a test.** The next round finds the same gap because
  nothing pins it (Step 2b).
- **A reviewer with no stopping rule.** If round N returns findings that are purely restatements
  of taste on code the previous rounds already touched, say so in the summary and let the round
  cap end it. Do not argue with the reviewer by re-running it.

The round cap is the backstop, not the plan. If a run hits it, the summary says what was left
and why — see Step 3.

---

## Step 5 — Final summary

```
## /pr-review-fix — <DONE | BLOCKED: reason>

Review pass: <resolved path or skill>   Verify gate: <resolved command(s)>
Commit: <FIX_SHA short> (local only, not pushed)

| Round | Findings | Must Fix | Fixed | Verify |
|-------|----------|----------|-------|--------|
| 1     | 5        | 3        | 5     | ✅ pass |
| 2     | 2        | 0        | 2     | ✅ pass |
| 3     | 0        | 0        | 0     | ✅ pass |

(This is the rollup. The per-finding detail was printed per round by Step 2f and is not
repeated here — re-print a round's table only if the run is BLOCKED and the reader needs the
outstanding items in one place.)

### Scope widened by a fix
- <id> path:line — reviewer recommended `split`; fixed here anyway. What it widened: <…>

### Unfixed — the run stopped before these
- <id> [bucket] path:line — <summary>. Stopped because: <the Step 3 condition>.

### Pre-existing failures surfaced (not caused by these fixes)
- <step> — <evidence from the clean-tree baseline re-run>

### Next
    git push --force-with-lease origin <branch>
```

Emit the three middle sections only when non-empty — on a clean DONE run there is nothing to
hand back. If **no** findings needed fixing at all, say so and confirm that **no commit was
created**.

When Step 0a or 0b used inference (not an explicit doc line), say so — e.g. "Verify gate:
`ant compile && mvn test` (in container) — from CONTRIBUTING.md" vs. "inferred from pom.xml +
Makefile, no explicit doc". Say too when the polish/behavioral labels were your judgment rather
than the reviewer's.

---

## Rules that always hold

- **Never defer a finding**, never convert one into a follow-up ticket, and never end a round by
  handing a finding back as the user's call. Fix it, or report the run BLOCKED with the reason
  it could not be fixed here.
- **Always print the round report (Step 2f)** — every round, including a round that found
  nothing. It is informative, not a gate, and it is still not optional: skipping it is how a run
  ends up explaining itself only after all the decisions have been made.
- **Never `git push`.** Print the command; the user runs it.
- **Never `git add -A` / `git add .`.** Stage by name, cross-checked against the pre-existing
  modified/untracked list from Step 0c.
- **Never amend a commit this skill did not create.** The amend guard is not optional.
- **Never commit without the verify gate passing**, or without an explicit proven-pre-existing
  attribution for the failure.
- **Never dismiss a test failure as pre-existing without the clean-tree baseline re-run.**
- **Never use `cd`** — use absolute paths, or `git -C "$REPO"`.
- **Never invoke test runners or linters directly** when the repo documents a wrapper script or
  package-manager target — go through the resolved gate.
- Do not touch emulators, run seed scripts, or start/stop long-running services unless the
  resolved verify gate explicitly requires it.

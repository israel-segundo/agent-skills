---
name: create-pr
description: >-
  Open a pull request for the current branch with a description a reviewer can actually
  use, and own the draft-to-ready flip. Reads the whole diff rather than the commit
  messages, groups it by logical change instead of by file, and writes a structured body —
  context, deployment steps, services, tests, deferred work — into a file passed to
  `gh pr create --body-file`, so backticks and Mermaid survive intact. Learns the repo's own
  conventions first: its real default branch, its PR template, its title validation, its
  changelog and draft rules. Opens as a draft by default, and gates the flip to ready on a
  review pass having covered the head it is about to publish. Use when the user wants to
  create a pull request, open a PR, prepare a branch for review, refresh a stale PR
  description, or mark an existing PR ready for review.
license: Unlicense
metadata:
  version: "1.0.1"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git, gh, jq) rather than
    host-specific tools, and degrades gracefully when a capability is absent. If your host
    has no skill support, read this file top to bottom and follow it directly.
when_to_use: >-
  Use when a branch is finished (or finished enough to share) and needs a PR whose
  description reviewers can read instead of the diff, or when an existing draft is ready to
  become visible. Not for pushing code, not for fixing review feedback, and not for
  merging. If a repo ships its own create-pr skill, that one wins: it knows the repo's
  template, its CI gates, and its release tooling.
argument-hint: "[target-branch | pr-number]"
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# Create PR (structured description, draft by default)

Read everything the branch changed, work out what it *does*, and write that down in a shape
a reviewer can act on. The output is a pull request whose description saves the reviewer
from reconstructing intent out of a diff.

**The defining stance: the description is written from the diff, not from the commit
messages.** Commit messages record what the author was thinking at each step; the PR body
records what the branch does as a whole. Those differ, and the second is what review needs.
Group by logical change — the three-to-six things this branch does — never one bullet per
file.

**Second stance: a draft is invisible to review, and a ready PR is a claim.** Opening a
draft costs nothing and gates nothing. Flipping to ready says "this is worth someone's
afternoon", and on most repos it also triggers the expensive CI and the review bots. So the
ready flip — not the create — is where this skill checks that a review pass has actually
covered the head being published.

**Plain language and short.** One line per table row. The context section reads like an
engineering summary, not a changelog of files. If a sentence has three qualifiers stacked
up, cut two.

### Guardrails (they apply throughout)

- **Never push without explicit confirmation.** A PR needs a pushed branch, so a push may
  be required — show the exact command and wait for a yes. Assume no host prompts before
  running commands.
- **Never modify tracked source files.** This skill writes exactly two kinds of file: the
  PR body, and its own scratch notes. If the review gate in Step 7 finds blockers, it
  *reports* them and stops — it does not fix them.
- **Never invent.** No ticket key that isn't in the branch or the plan, no deployment step
  that isn't in the diff, no test that isn't in the tree. An empty section stated as empty
  beats a plausible fabrication.
- **Don't interrogate the user.** Everything here is inferable from the repo and the diff.
  Where something genuinely can't be determined, omit it silently (a ticket key) or leave a
  short author placeholder in the body (screenshots) — do not open a question-and-answer
  session before creating the PR.
- **Never inline the body with `--body "..."`.** Backticks get escaped, GitHub stores the
  backslashes literally, and every code fence and Mermaid block in the PR is broken.

Set a scratch directory once and keep every artifact in it:

```sh
WORK="${TMPDIR:-/tmp}/create-pr-$$"; mkdir -p "$WORK"
```

---

## Step 0 — Probe what you can do

```sh
git rev-parse --show-toplevel        # required — stop if this fails
gh auth status                       # required
command -v jq                        # optional: cleaner JSON handling below
```

`gh` missing or unauthenticated → **stop**. Say: `gh` is not installed or not
authenticated; run `gh auth login`. Do not attempt the GitHub REST API by hand as a
fallback.

Then decide the mode:

- Argument is **all digits** (`1658`) → **Marking an existing PR ready** (jump to that
  section at the end). The argument is a PR number, not a branch.
- Argument is anything else → it names the **base branch**.
- No argument → resolve the base branch in Step 1.

## Step 1 — Resolve the base branch and check the branch is publishable

**Never assume `main`.** Resolve the repo's actual default branch, in order:

```sh
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's|^origin/||'
```

Store it as `BASE`. Store the current branch as `BRANCH`
(`git branch --show-current`). If `BRANCH` equals `BASE`, **stop** — there is nothing to
open a PR from, and the fix is a feature branch, not a workaround.

Then confirm the branch is in a publishable state:

```sh
git status --porcelain                                  # uncommitted work?
git fetch origin --quiet
git log --oneline "origin/$BASE..HEAD"                  # what this PR contains
git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null # local behind its own remote?
```

- **Uncommitted changes** → say what's uncommitted and ask whether to proceed without them.
  They will not be in the PR.
- **No commits ahead of `BASE`** → stop; there is no change to review.
- **Local behind its own remote** → stop. Someone else (or another worktree) pushed to this
  branch. Reconcile before describing a diff you can't see.
- **Not pushed, or ahead of its remote** → show the exact command
  (`git push -u origin "$BRANCH"`) and **wait for confirmation**. Do not push on your own.

## Step 2 — Is there already a PR?

```sh
gh pr list --head "$BRANCH" --state open --json number,url,isDraft,title
```

- **One exists** → this is not a create. Either refresh its description (compose the body
  as normal, then `gh pr edit <N> --body-file "$WORK/pr_body.md"`) or, if the ask was to
  publish it, go to **Marking an existing PR ready**. Say which you're doing.
- **None** → carry on with the create path.

## Step 3 — Learn the repo's conventions before writing anything

Repos disagree about PR bodies, and the local convention beats this skill's defaults every
time. Spend one pass finding out:

```sh
ls .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE* 2>/dev/null
ls CONTRIBUTING.md CLAUDE.md AGENTS.md 2>/dev/null
grep -rl "semantic-pull-request\|commitlint\|conventional" .github/workflows/ .commitlintrc* 2>/dev/null
grep -rniE "changelog|draft" CONTRIBUTING.md CLAUDE.md AGENTS.md 2>/dev/null | head -20
```

What to take from each:

- **A PR template exists** → it wins. Fill *its* sections; use the skeleton in Step 9 only
  for sections the template doesn't cover, and keep the template's own headings verbatim so
  the repo's downstream tooling still matches them.
- **Title validation in CI** (`amannn/action-semantic-pull-request`, commitlint, a title
  lint step) → read its config and satisfy the actual regex, not the generic rules in Step
  8. Say which check you conformed to.
- **A changelog convention** (a `Changelog:` trailer, a changeset file, a `docs/changelog-*`
  style guide) → follow it; see Step 9. No convention found → omit the line entirely
  rather than inventing a format.
- **A draft convention** — some repos skip expensive CI on drafts, some require ready. If
  the repo says nothing, draft is the default here.
- **A review command or checklist** (`.claude/commands/pr-review.md`, a review skill, a
  checklist in `CONTRIBUTING.md`) → note it; Step 7 needs it.

Read the repo's contributor docs for anything that constrains the PR body — a required
section, a forbidden one, a ticket-link format. Note them in `"$WORK/conventions.md"` so
Step 9 doesn't have to re-derive them.

## Step 4 — Read the change

```sh
git log "origin/$BASE..HEAD" --oneline
git diff "origin/$BASE...HEAD" --stat
git diff "origin/$BASE...HEAD"
```

Read the full diff. Three dots, not two — you want what this branch adds, not the
difference between two tips.

For a very large diff, read the `--stat` first, group the files into the three-to-six things
the branch does, then read the diff of each group's core files in full and skim the rest.
Never describe a file you have not read.

Write the grouping to `"$WORK/groups.md"` before drafting prose. That file is the spine of
the Context section, and having it on disk means Step 9 doesn't depend on holding the whole
diff in your head.

## Step 5 — Resolve the ticket key and its tracker

Look for an issue key in this order, first match wins:

1. the branch name — `<user>/<type>/<KEY>-<slug>`, `<KEY>-<slug>`, or a bare key anywhere,
2. a plan or task file in the diff (`PLAN.md`, `plan.md`, `tasks.md`) that names one,
3. the commit messages on this branch.

```sh
printf '%s\n' "$BRANCH" | grep -oiE '[A-Z][A-Z0-9]+-[0-9]+' | head -1
```

Branch names are often lower-case, so match case-insensitively. Watch for key-shaped
fragments that aren't tickets — `UTF-8`, `SHA-256`, `ipv4-2`. If the only candidate looks
like that, treat it as no match.

**Normalise:** upper-case in the body and the tracker link, lower-case in the title scope.

**Never hardcode a tracker host.** Discover it from the repo, and only link if you found
one:

```sh
grep -rhoE 'https://[A-Za-z0-9.-]+(\.atlassian\.net|/browse)[^ )"]*' \
  CLAUDE.md AGENTS.md CONTRIBUTING.md README.md .github/ docs/ 2>/dev/null | sort -u | head
```

GitHub-issue repos use `#123` instead — if the key is a GitHub issue number, link it as
`Closes #123` (or `Refs #123` when the PR doesn't close it) and skip the external link.

**No key found → silently omit both the title scope and the link.** Do not ask for one.

## Step 6 — Detect which conditional sections apply

Decide these from the diff alone. Each is an author placeholder or an auto-filled section —
never a question to the user.

- **UI changes** — the diff touches rendered components, styles, or templates
  (`.tsx`/`.jsx`/`.vue`/`.svelte`/`.css`/`.scss`/`.html`, or a components/pages/views
  directory). → include **Screenshots**.
- **Deployment or rollout actions** — the diff adds or changes a migration, a backfill or
  maintenance script, a database index or schema definition, security rules, infrastructure
  config, seed/reference data, or an environment secret; or a plan file in the diff
  describes a rollout step. → include **Deployment & Rollout**.
- **Feature flags** — only if the repo *has* a flag mechanism (a flag registry, a config
  module, an SDK dependency). Include the section when the diff adds or removes a flag, or
  ships a user-facing behaviour change without one. Skip entirely for repos with no flag
  system, and for changes with no user-visible surface.
- **Diagrams** — the change moves data between components, adds a state machine, or
  restructures a flow. Skip for anything a reader can follow from the bullets.
- **Scope drift** — the diff amends governance or convention files (a constitution, a
  contributing guide, a lint config) while the branch is about something else. Don't strip
  it; flag it under **Future Tasks** as accidental scope, with the suggestion to split.

Anything a repo-local skill or a PR template requires beyond these, add it too.

## Step 7 — The review gate (ready PRs only)

Drafts get no gate: nobody is being asked to look yet, and most repos skip their heavy CI
and review bots on drafts. Say in your summary that the review pass belongs before the
ready flip.

**For a ready (non-draft) PR** — because the user explicitly asked for one — a review pass
must already cover this exact HEAD:

1. A pass already covered it — e.g. **pr-code-review** (interactive),
   **pr-code-review-batch** (`findings.md` + HTML with no High/S0 blockers for this HEAD),
   **execute-plan** Phase 8 critique, or the repo's own review command. Reuse it. **Never
   re-run a pass that already covers this HEAD.**
2. None did → run **pr-code-review-batch** or **pr-code-review** if available; otherwise
   the repo's review checklist against `origin/$BASE...HEAD`. If the repo has none, do a
   read-only correctness pass over the diff yourself.

Treat as **blockers** anything the pass marked must-fix, merge-blocking, or high severity.
For **pr-code-review-batch**, treat **High** severity or a **Fix before merge** disposition
as merge-blocking (batch does not use S0/S1 labels).

**Blockers found → report them, create the PR as a draft instead** (keeping the title, body
and Future Tasks you composed), and name the open blockers in your summary. Do not fix them;
this skill does not edit code. Retry the ready flip once they're clear.

Either way, name known deferrals in **Future Tasks** as *won't fix here*, *accepted risk*,
or *follow-up ticket* — an unstated deferral gets re-raised by every review round.

## Step 8 — Compose the title

Default to conventional commits, unless Step 3 found the repo validating something else.

**Format:** `type(scope): lowercase subject`

- **type** — one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
  `ci`, `chore`, `revert`.
- **scope** — optional; the ticket key in **lower-case** when Step 5 found one, else the
  feature area, else omit.
- **subject** — **entirely lower-case**, max ~100 chars. Lower-case is the safe form: the
  common CI regex rejects ALL-CAPS runs, PascalCase and Start Case, so write `api` not
  `API`, `openapi` not `OpenAPI`, `firebase` not `Firebase`.
- The title describes the **whole** branch, not its largest commit. A branch that adds an
  endpoint *and* migrates its callers says both.

```
feat(proj-310): add api infrastructure and openapi spec
fix(proj-456): resolve cors preflight for jwt auth
test: add e2e coverage for catalog import flow
```

## Step 9 — Compose the body

Write it to `"$WORK/pr_body.md"`. Full authoring guidance, with worked good and bad
examples for each section, is in
[`references/pr-body-guide.md`](references/pr-body-guide.md) — read it before drafting if
you have not already.

**One line per paragraph, one line per list item — never hard-wrap prose at a column.** Let
the renderer wrap; a body wrapped at 80/100 chars reads as a ragged, oddly-broken block and
forces a whole-paragraph re-flow on every later edit. Line breaks stay only where they are
content: fenced code, Mermaid, table rows, an intentional `<br>`.

The skeleton, with conditional sections marked. Drop any section that doesn't apply rather
than filling it with "N/A", and **never** emit the guidance comments into the final body:

```markdown
**Ticket:** <tracker link>            <!-- only if Step 5 found a key and a host -->

Changelog: <entry>                    <!-- only if Step 3 found a changelog convention -->

## Context & Summary

<1–2 sentences: what this introduces and why. Then bullets grouped by LOGICAL CHANGE,
bolding the area name, not the file path. HARD LIMIT 8 bullets, however many files changed.>

## Deployment & Rollout            <!-- only if Step 6 detected actions -->

<One bullet per action: **when it runs** (before release / with the deploy / after deploy),
the exact command in backticks, the target environment, and an explicit
**Expected outcome:** the operator can verify. Do not invent actions to fill the section.>

## Screenshots                     <!-- only if UI changes -->

> **Author:** please attach screenshots or a screen recording on this PR.

## Feature flag                    <!-- only if the repo has flags and Step 6 flagged it -->

> **Author (advisory, not a merge gate):** name the flag this ships behind, or state none
> and why; give the default state, target environments, and rollout intent.

## System Diagrams                 <!-- only if a diagram genuinely aids review -->

<Mermaid code blocks.>

## Services & Core Functions

| Service / Module | Function | Description |
|---|---|---|
| `ServiceName` | `functionName()` | One line. |

## Utility Functions

| File | Function | Description |
|---|---|---|
| `utils/foo.ts` | `helperName()` | One line. |

## Tests

**Verification:** <one line: how the change was observed working — the command run and what
was seen. If it wasn't run, say so plainly: `deferred — not executed` or
`N/A — no runtime behaviour`.>

| Area | Type | Summary |
|---|---|---|
| `ServiceName` | Unit | What's covered, one line. |

## Future Tasks

<TODO/FIXME/HACK found in the diff, follow-ups named in plan or task files, and the Step 7
deferrals as explicit won't-fix / accepted-risk / follow-up-ticket lines. If there are none,
say so in one line.>
```

The changelog line, when the repo has that convention: non-user-visible types (`chore`,
`refactor`, `test`, `ci`, `build`, `docs`, `style`, `revert`) get the repo's "no entry"
form; `feat` / `fix` / user-visible `perf` get one sentence in present tense from the user's
point of view, no ticket IDs, no commit scopes.

Scan for deferred work before writing that last section:

```sh
git diff "origin/$BASE...HEAD" | grep -nE '^\+.*(TODO|FIXME|HACK|XXX)'
```

## Step 10 — Create the PR

```sh
gh pr create --draft --base "$BASE" \
  --title "<title>" --body-file "$WORK/pr_body.md"
```

- **`--draft` is the default.** Drafts skip heavy CI on most repos and are invisible to
  review bots — iterate there, flip once.
- Omit `--draft` only when the user explicitly asked for a ready PR *and* Step 7 came back
  clean. Go straight to ready; don't create a draft and immediately flip it.
- `--body-file` always. Never `--body "..."`.

## Step 11 — Report

Give the URL, the title, the base, draft-or-ready, and:

- which conventions you conformed to (template, title check, changelog rule),
- which conditional sections you included and why,
- anything you left as an author placeholder (screenshots, flag posture),
- for a draft: that the review pass belongs before the ready flip,
- for a blocked ready flip: the blockers, and that the PR was opened as a draft instead.

---

## Marking an existing PR ready

Use this when the argument is a PR number, or the ask is to publish an existing draft. The
ready flip — not the create — is where a PR becomes visible to reviewers and, on most repos,
where the expensive CI and the review bots start.

1. **Establish the PR's head, not the session's branch.**

   ```sh
   gh pr view <N> --json baseRefName,headRefName,headRefOid,isDraft,body,url
   gh pr diff <N>
   ```

   Review against `baseRefName...head` from that output — never against whatever branch the
   session happens to be on.

2. **Apply Step 7** as if creating a ready PR. Blockers → report them and **stop**. Leave it
   a draft, hand off to a fix session, retry when clear. This skill does not edit code.

3. **Check the body still describes the branch as it now stands.** A description written at
   draft time goes stale across pushes, and a stale description is what makes reviewers
   re-litigate settled decisions. Recompose it (Steps 4–9) and
   `gh pr edit <N> --body-file "$WORK/pr_body.md"` when the diff has moved, keeping the
   Future Tasks deferrals current.

4. **Flip once, when the batch is complete:** `gh pr ready <N>`. Don't flip early to harvest
   bot feedback — on repos with a sticky review comment, every subsequent push whose CI
   passes rewrites that comment from scratch. Batch later fixes into one push per review
   round.

---

## Principles

- **The diff is the source, the commits are a hint.** Describe what the branch does, not
  what the author was thinking at each step.
- **Group by change, not by file.** Eight bullets maximum. A fifty-file PR still does three
  to six things.
- **The repo's convention beats this skill's default.** Template, title check, changelog
  rule, draft policy — find them first, conform, and say which you conformed to.
- **Draft costs nothing; ready is a claim.** The gate lives at the flip.
- **State the deferrals.** Won't-fix, accepted risk, follow-up ticket. Silence gets
  re-litigated.
- **Don't fabricate to fill a section.** An honest empty section is information.
- **The body is rendered, not read as source.** One line per paragraph; no hard wrapping.
- **Never push, never merge, never edit code.** Show the command, wait for the yes.

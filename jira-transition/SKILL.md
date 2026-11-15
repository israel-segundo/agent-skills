---
name: jira-transition
description: >-
  Move the Jira issue behind the current branch to a workflow status (In Progress, In Review,
  Done, or any named status), safely: resolves the key from the PR or branch, discovers the
  site and a Jira transport instead of assuming them, maps logical names to each project's
  real status names from a per-user config, and never moves an issue backwards or out of a
  done status. A target that is already reached, or not allowed from the current status, is
  a no-op, not an error. Ends with a parseable RESULT line. Use when a ticket's status
  should follow the work (starting a slice, opening a PR, merging the last slice),
  standalone or as a building block inside execute-plan, pr-launch or pr-land.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git, gh, jq, jira/acli)
    rather than host-specific tools, and uses a host Jira integration when present.
    Status-name mapping lives in ~/.config/jira-transition/statuses.ini only. Never creates
    issues and never edits fields other than the status.
when_to_use: >-
  Use when an issue's status should change because the work moved: implementation started,
  PR opened, last PR merged. Not for comments (jira-update-issue), not for creating or
  editing issues, and not for reassigning.
argument-hint: "[KEY] --to <in_progress|in_review|done|\"Status name\"> [--if-category new,indeterminate] [--comment-file FILE]"
allowed-tools:
  - Bash
  - Read
---

# Jira transition (move a ticket's status, forward only)

One status change on one issue. Nothing else: no new issues, no field edits, no reassigning.

**Two ways to run:**

- **Standalone** (a user invoked it): show the issue, its current status and the transition
  you'd make, then wait for a yes.
- **Called by an orchestrator** (execute-plan, pr-launch, pr-land): the caller's standing
  authorization covers the transition. No preview.

## Arguments

| Argument | Meaning |
|---|---|
| `KEY` | Issue key. Omitted → resolve from the branch's PR or branch name (Step 1) |
| `--to` | A logical name (`in_progress`, `in_review`, `done`) or a literal status name |
| `--if-category` | Only move when the issue's current status category is one of these (`new`, `indeterminate`). Default: `new,indeterminate` |
| `--comment-file` | Optional comment posted with the transition, when the transport supports it |

## Rules that always hold

- **Never move out of a `done` category.** A closed issue stays closed.
- **Never move backwards.** `--if-category` is the guard: In Progress is normally called with
  `--if-category new`, so an issue already in review isn't pulled back.
- **Already in the target status → NOOP.**
- **Never guess the Jira site or the status name.** Discover the site; map names through the
  config or the issue's available transitions.
- **Never hand-roll REST calls** when a CLI or host integration exists.

## Step 0: Probe transports

```sh
command -v git gh jq
command -v jira acli          # CLI transports, in order of preference
```

Also note whether the host exposes a Jira or Atlassian integration (it can list transitions
and their target status categories, which is the most reliable path). Say which transports
you have. With none at all → `RESULT: BLOCKED (no Jira transport)` when called by an
orchestrator that requires it; otherwise print the target status and the exact command.

## Step 1: Resolve the issue key and the site

No `KEY` argument → resolve it exactly as **jira-update-issue** Step 3 does (PR body, PR
title, branch name; uppercase; reject `UTF-8`-style false positives). Discover the site as
its Step 4 does. No key → `RESULT: NOOP (no ticket key on this branch)`. Several sites →
ask (standalone) or BLOCKED (orchestrated).

## Step 2: Map the target to a status name

Logical names resolve through `~/.config/jira-transition/statuses.ini` (or
`$JIRA_TRANSITION_CONFIG`), section = project key, falling back to `[default]`:

```ini
[default]
in_progress = In Progress
in_review = In Review
done = Done

[PROJ]
in_review = Code Review
```

```sh
CFG="${JIRA_TRANSITION_CONFIG:-$HOME/.config/jira-transition/statuses.ini}"
PROJECT=${KEY%%-*}
lookup() {  # lookup <section> <key>
  awk -v s="[$1]" -v k="$2" '
    $0 == s { f=1; next } /^\[/ { f=0 }
    f && $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
  ' "$CFG" 2>/dev/null
}
TARGET=$(lookup "$PROJECT" "$TO"); [ -n "$TARGET" ] || TARGET=$(lookup default "$TO")
[ -n "$TARGET" ] || case "$TO" in
  in_progress) TARGET="In Progress" ;; in_review) TARGET="In Review" ;; done) TARGET="Done" ;;
  *) TARGET="$TO" ;;
esac
```

## Step 3: Read the current status and the available transitions

- **Host integration:** fetch the issue's `status` (name + `statusCategory.key`) and its
  transitions (each with `to.name` and `to.statusCategory.key`).
- **jira CLI:** `jira issue view "$KEY" --raw | jq '.fields.status | {name, cat: .statusCategory.key}'`.
  It can't list transitions; Step 5 finds out by trying.
- **acli:** `acli jira workitem view --key "$KEY" --json`, same fields.

Then decide, in order:

1. Current category is `done` → `RESULT: NOOP (<KEY> is <status>, already closed)`.
2. Current status name equals `$TARGET` (case-insensitive) → `RESULT: NOOP (already <status>)`.
3. Current category not in `--if-category` → `RESULT: NOOP (<KEY> is <status>; not moving it back)`.
4. Transitions known and none leads to `$TARGET` (match `to.name`, then the transition's own
   name, case-insensitive) → `RESULT: NOOP (no transition to <target> from <status>; add a
   mapping in statuses.ini)`. Not a blocker. When the target is a logical name and exactly
   one available transition leads to a status of the matching category (`indeterminate` for
   in_progress/in_review, `done` for done) and its name contains the word you'd expect
   (`progress`, `review`, `done`), you may use it, and say so.

## Step 4: Confirm (standalone only)

Show the key with its browse URL, current status → target status, and the transport. Wait
for an explicit yes.

## Step 5: Transition

```sh
jira issue move "$KEY" "$TARGET"
acli jira workitem transition --key "$KEY" --status "$TARGET"
```

Or the host integration's transition call with the transition id from Step 3. A
`--comment-file` is posted separately afterwards through the same transport
(`jira issue comment add "$KEY" --template "$COMMENT_FILE" --no-input`, acli's
`workitem comment`, or the host integration); never inline the comment through a shell
substitution, since the jira CLI can hang on it.

A failure that names an unavailable transition → `RESULT: NOOP (<the error>)`. Any other
failure → `RESULT: BLOCKED (<the error>)`.

## Step 6: Report

One line: `<KEY>: <old status> → <new status> via <transport>`, then:

```
RESULT: DONE
RESULT: NOOP (<why>)
RESULT: BLOCKED (<what you need>)
```

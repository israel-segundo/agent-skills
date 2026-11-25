# Plan review checklist (Step 2a)

The reviewer's job is to **disprove** the plan at `$REF`. Every check below is a claim the plan
makes; confirm it with a read-only git command at the ref, or report it.

Evidence always comes from `$REF`, never from the working tree, memory, or the plan itself.

## 1. Code references

| Check | How | Typical finding |
|---|---|---|
| Every cited path exists | `git ls-tree -r --name-only "$REF" \| rg -x 'path'` | File renamed, moved, or deleted |
| Every cited line or range still holds what the plan says | `git show "$REF:path" \| sed -n 'A,Bp'` | Line drift; the cited code moved 40 lines down |
| Every helper, function, type, constant exists with the stated shape | `git grep -n 'name' "$REF"` | Helper renamed, signature changed, already exists (task is redundant) |
| Every identifier string (permission ids, enum values, collection names, config keys, flags) is current | `git grep -n` for the literal and its registry | Renamed or retired id still used in tasks |
| Every "pre-checked YYYY-MM-DD" note still holds | Re-run the check | The pre-check result changed since that date |
| Code the plan says to delete or migrate still exists | `git grep` | Already removed upstream; task is stale |
| Commits since the plan's stamp that touch cited paths | `git log --oneline "$PLANNED_SHA..$REF" -- <paths>` | A merged PR changed the premise |

## 2. Tests

| Check | Typical finding |
|---|---|
| Named test files, describe blocks and helpers exist at `$REF` | Suite renamed or split |
| Tests the change will flip are named in the plan (an ALLOW case that becomes a DENY, a snapshot, a fixture that seeds the changed state) | A fixture that will go red is not listed, so the implementer "fixes" the rule instead of the fixture |
| New test cases cover each behavior branch the plan introduces, including the regression side | Only the deny path is tested |
| TDD evidence block names a concrete red step | "Write tests" with no failing case named |

## 3. Commands

| Check | Typical finding |
|---|---|
| Every verification command exists (package scripts, Makefile targets, CI jobs) at `$REF` | Script renamed; flag deprecated |
| Filter flags actually filter (the repo's docs may say a wrapper swallows them) | Command runs the whole suite or nothing |
| Commands match the repo's documented verify gate (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`) | Plan invokes a runner directly where the repo mandates a wrapper |

## 4. Plan structure (create-plan contract)

| Check | Typical finding |
|---|---|
| PR map: one row per `### PR N:` heading; statuses match | Row says PENDING, heading says IN PROGRESS |
| Depends on / Parallel consistent with what each PR touches | Two "parallel" PRs edit the same file |
| Each PR names one behavioral check | Verification is only "verify passes" |
| Every Risks & Mitigations action maps to a task in a named PR | Mitigation with no task |
| Acceptance-criteria table covers every AC in the issue | AC dropped |
| No empty `*[pre-check result]*` placeholders; no "add test if missing" hedges | Hedge left for the implementer |
| Out-of-scope list does not contradict a task | Task implements an out-of-scope item |
| Repo rules the plan must follow (commit format, test layering, guards) | Plan breaks a documented repo rule |

## 5. Proportionality

| Check | Typical finding |
|---|---|
| Plan size and PR count fit the ticket's scope | Three PRs for a one-file change; or one PR that cannot name a single behavioral check |
| No speculative abstractions or tasks the ticket does not require | "Future extensibility" helper |

## Finding format

Return a JSON array. Empty is valid.

```json
{
  "id": "P1-03",
  "severity": "must-fix | should-fix | nit",
  "plan_location": "PR 1 › Tasks, bullet 4 (PLAN.md:142)",
  "claim": "what the plan says, quoted or paraphrased in one line",
  "evidence": "origin/main:src/auth/session.ts:41 — `export function issueToken(` (the plan cites src/auth.ts:88, which no longer exists)",
  "fix": "the exact plan edit: replace X with Y in <section>"
}
```

Severity:

- **must-fix** — an implementer following the plan would do the wrong thing or fail: wrong
  path or identifier, a stale premise, a missing task for a test that will go red, a command
  that does not exist, a repo rule broken.
- **should-fix** — the plan works but misleads: line drift, an outdated pre-check date, a
  section that contradicts another, a risk with no task.
- **nit** — wording, formatting, a table that renders badly, a stamp to refresh.

A finding with no `$REF` evidence is not a finding. Taste ("I'd split this differently") is
not a finding unless it breaks a check above.

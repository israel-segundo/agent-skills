# Planning discipline

Normative rules for **create-plan**. Implementers follow the same spirit in
**execute-plan**.

## Anti-hallucination

Plans that reference non-existent files, APIs, schemas, or services cause downstream
implementation failures. When a fact cannot be verified in this session, record it under
**To Be Clarified** — do not guess.

## Smallest plan

Produce the smallest plan that satisfies the ticket. No speculative abstractions or
"future extensibility" tasks unless the ticket requires them.

## Scope escalation

Ambiguous or contradictory scope that blocks PR breakdown → stop and ask; do not guess.

## Pre-check at plan time

If a task can be answered with one search or file read now — "does helper X exist?",
"who imports enum Y?", "is test Z already present?" — do it during exploration and bake
the outcome into the plan:

```markdown
- [ ] Register new status enum — *(pre-checked 2026-09-07: value not in src/constants.ts)*
```

The implementation task becomes a one-line re-verify plus a fallback branch if the finding
moved.

## Plan contract (for implementers)

Plans may use these artifacts; **execute-plan** honors them:

| Artifact | Author writes | Implementer must |
|----------|---------------|------------------|
| **PR map** | One row per PR at plan top | Keep Status in sync with PR headings through execution |
| `*[pre-check result]*` | Placeholder before a conditional task | Run pre-check, fill placeholder, commit plan update, then code |
| Dated pre-check notes | `pre-checked at plan time (YYYY-MM-DD): …` | Re-verify this session before relying |
| TDD evidence block | Red → green → refactor steps per PR | Follow process; capture failing/passing output |
| No coverage hedges | Never "add test if missing" | Rewrite into pre-check + required action |
| Risks & Mitigations | Action mitigations | Every action maps to a checkbox task in a specific PR |

## Repo rules win

Read the repository's own guidance (`AGENTS.md`, `CONTRIBUTING.md`, `docs/`, `.cursor/rules/`,
or equivalent standards directories) before writing tasks. A plan that violates documented
project rules will fail review regardless of this skill.

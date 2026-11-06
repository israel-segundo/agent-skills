# Execute-plan implementation rules

Loaded during Phase 5 (implementation) and Phase 8 (review fixes).

## Test-first

For every new function or behavior change: write the test first, watch it fail, write minimal
code to pass, then refactor. If the plan orders implementation before tests, reorder locally
(test → code) unless the human overrides.

Bug fixes need a regression test: fail without fix, pass with fix.

## Invention guardrails

- Do not reference patterns you have not read in this session.
- Do not invent file paths, route names, or API contracts — verify with search and read.

## Honor plan contract

Plans from **create-plan** may include:

| Artifact | Before coding |
|----------|---------------|
| `*[pre-check result]*` | Run pre-check, fill placeholder, commit plan update |
| Dated pre-check notes | Re-verify this session; apply fallback if finding moved |
| **PR map** | Keep Status column in sync with PR heading through execution |
| TDD evidence | Capture red/green output (separate commits preferred) |
| Coverage hedges | Rewrite into pre-check + required action — never implement on hedges |
| Risk mitigations | Every action mitigation must have a completed task |

## Assertion quality

Avoid assertions that pass regardless of behavior: empty matchers, `toBeDefined()` as the
only shape check, `toHaveBeenCalled()` without argument checks, always-true booleans.

## Comment hygiene

Comments explain non-obvious invariants — not the change narrative. Ticket refs and
"changed per review" prose belong in commit messages and PR descriptions, not inline next
to code.

## Write-contract changes

When changing enums, status fields, or API response shapes, search for readers and test
assertions on the old value. Update them in the same commit or document explicit deferral.

## Review findings discipline

When review produces findings: verify each against the code, fix correct ones, push back on
wrong ones with evidence, re-verify after fixes. No performative agreement — show the fix.

# Story point estimates

Propose a **Fibonacci** estimate only: **1, 2, 3, 5, 8, 13**.

## Guidelines

| Points | Scope |
|--------|-------|
| 1 | Single file, trivial change, clear path, good test coverage |
| 2 | 1–2 files, straightforward logic, minimal risk |
| 3 | 2–4 files, some complexity, may need new tests |
| 5 | Multi-file across modules, requires design decisions, moderate risk |
| 8 | Cross-feature, touches infra/security/schema, significant unknowns |
| 13 | Large scope, multiple unknowns — consider splitting |

## Adjustment factors

- No existing test coverage in the affected area → +1–2 points
- Touches security rules, authz, or permissions → +1 point
- Requires migration or schema change → +1–2 points
- Spike/research ticket → estimate investigation effort, not implementation
- Well-documented ticket with root cause and suggested fix → −1 point
- If story points are already set → show the existing value and ask before re-estimating

Rationale bullets must cite **specific findings** from earlier steps, not generic claims.

## Output structure

```
Suggested estimate: N points

Rationale:
  • [factor 1]
  • [factor 2]
  • [factor 3]

Adjustments applied:
  • [+N for reason] or [−N for reason]
```

## When to recommend a split

Proactively recommend splitting if **any** of:

- Estimate reaches **13**
- Codebase analysis found **3+ independent work streams** that could merge separately
- The ticket mixes **different work types** with different reviewers or risk profiles
- Acceptance criteria contain **distinct phases** that each deliver standalone value

Propose concrete sub-tickets (do **not** create them in Jira):

```
This ticket looks like it could be split into smaller, independently shippable pieces:

  1. "PROJ-XXX-a: [title]" (N points)
     • [what this sub-ticket delivers]
     • [can be merged independently: yes/no]

  2. "PROJ-XXX-b: [title]" (N points)
     • [what this sub-ticket delivers]
     • [depends on: PROJ-XXX-a / none]

Total: N points across M tickets vs N points in one ticket

Benefits of splitting:
  • [e.g., smaller PRs, easier review, earlier value delivery]
```

Ask: **"Would you like to split this, or keep it as one ticket?"**

If splitting: record under **Follow-ups / split proposal** for the Step 5 comment
([comment-template.md](comment-template.md)); leave ticket creation to the engineer or lead.

Then ask: **"Accept N points, adjust, or skip?"**

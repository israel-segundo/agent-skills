# Jira comment template

Compose after Steps 1–4. Incorporate engineer feedback:

| Situation | Comment section |
|-----------|-----------------|
| Unresolved questions | **Open questions** |
| Unresolved decisions | **Decisions needed** (with Engineering/Product owner + options) |
| Resolved decisions | **Decisions made** (what + by whom) |
| Engineer agreed to split | **Follow-ups / split proposal** |
| All questions/decisions resolved | Omit Open questions / Decisions needed |
| No decisions made | Omit Decisions made |
| No split | Omit Follow-ups / split proposal |

Write the draft to `$WORK/comment.md` before showing it.

## Markdown body (host integration / acli)

```markdown
## Pre-Grooming Analysis

**Story points:** N

**Rationale:**
- [bullet 1 — primary complexity driver]
- [bullet 2 — scope detail]
- [bullet 3 — risk or coverage note]

**Likely affected areas (please verify):**
- `path/to/file1.ts` — [why flagged]
- `path/to/file2.tsx` — [why flagged]

**Open questions:**
- [unresolved from Step 3]

**Decisions needed:**
- **[Engineering/Product]:** [decision] — Options: [A] vs [B]

**Decisions made:**
- [decision] — resolved: [what was decided and by whom]

**Follow-ups / split proposal:**
- Create "PROJ-XXX-a: [title]" (N points) — [delivers …]; independent: yes/no
- Create "PROJ-XXX-b: [title]" (N points) — [delivers …]; depends on: …

**Constitution / standards compliance:**
- [relevant principle] — [what's required]

**Completeness gaps:**
- [missing fields from Step 1]

_Generated via pre-groom (`<model + version>`) — reviewed by [engineer display name]_
```

Omit any section with nothing to say. Prefer paths relative to each checkout root; if
multiple checkouts appear, prefix with a short checkout label.

## Wiki markup variant (`jira` CLI)

Convert headings to `h3.`, bold to `*bold*`, bullets to `*`, and wrap paths in
`{{monospace}}`. Do not use `#` for headings or lists.

## Confirmation prompt

> Post this comment and set story points to N? (yes / edit / skip)

Only on **yes**, write story points then post the comment
([jira-transport.md](jira-transport.md)).

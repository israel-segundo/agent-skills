# Report formats

Two outputs: the **local HTML table** you show the user while reviewing, and the **posted
PR comment**, which happens only on explicit request. Both use the same four columns so
the user recognises what they approved.

`$WORK/findings.md` stays the source of truth; the HTML is a view of it.

## The local HTML findings table

Write a self-contained `.html` to `$WORK` and open it with whatever the host has
(`xdg-open`, `open`, `wslview`) — or print the path for the user to open. Keep it
**local**: never a hosted render, an uploaded page, or a published artifact. Refresh it as
findings change.

- Columns: **# · Finding · Severity · Disposition**.
- Lead the Finding cell with the bold one-line claim; detail underneath.
- **Theme-aware** — light and dark via `prefers-color-scheme`.
- Color-coded severity chips (red / amber / grey is enough).
- **Make cells wrap.** This bites every time. Use `table-layout: fixed` with a
  `<colgroup>` (narrow # and Severity, wide Finding, ~25% Disposition) and
  `overflow-wrap: anywhere` on cells and `<code>`. Never leave `white-space: nowrap` on a
  column holding a long sentence.
- Multi-item dispositions render as a real `<ul>`, not a run-on inline list.
- Inline all CSS. No CDN, no external fonts — it must open offline.

## The posted PR comment

Exact shape, in order:

**1. Title** — one line: `## Review: <what the review is about>`.

**2. Disclosure blockquote** — REQUIRED, immediately after the title. Replace `<agent>`
with the actual agent you used, and the middle clause with what the session really did
(ran the checks / read the CI plan / read the artifacts). Never claim evidence you didn't
gather.

> **On how this was produced:** this review is LLM-aided, but it is *not* a blind "I
> pointed an agent at the diff and pasted what it said." I had `<agent>` analyze the
> branch, `<verify against the real evidence — ran the checks on the PR head / read the CI
> plan>`, explain back the PR's intent, and then I challenged that intent through a series
> of questions — each finding below came out of that human-in-the-loop back-and-forth and
> was checked against the actual code and checks. Read it as a human review that used an
> agent as a sparring partner.

**3. Stance paragraph** — a few sentences: what's genuinely good about the PR, what the
findings are about, and which (if any) actually touch its purpose or blast radius.

**4. Findings table** — severity-ranked, stable IDs, exactly these four columns:

```
| # | Finding | Severity | Disposition |
|---|---------|----------|-------------|
| F1 | **Bold one-line claim.** Then the evidence and failure mode, grounded in a file:line, a test name, or a CI line. | **High** | Fix-before-merge / fast-follow / out of scope. |
```

Lead each Finding cell with a bold one-sentence claim, then the detail. Mark out-of-scope
items plainly, e.g. "(OUT OF SCOPE)".

**5. Verified while reviewing** — a short paragraph of what you actually checked: which
checks you ran and their result line, which assertions you read, whether you confirmed a
test fails without the change, which CI artifacts you read, which contracts and defaults
you confirmed. **Include the limits** — what you couldn't run or sample. This paragraph is
what makes the review credible.

**6. Suggested split** — one or two sentences separating cheap fix-before-merge items from
genuine follow-ups. Be explicit that nothing blocks merge unless it truly does.

Post it with a file, never an inline heredoc:

```sh
gh pr comment "$PR" --body-file "$WORK/review.md"
```

## Tone

Write like a person, not a linter. Relaxed, plain, first-person. Short sentences. Say what
you mean without stacking hedges. It should read like a colleague who did the homework, not
a generated report. If a paragraph reads robotic, rewrite it before showing the user — and
certainly before posting it.

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

**2. Disclosure blockquote** — REQUIRED, immediately after the title. **One sentence, and
only one.** Name the **exact model and version** — "Claude Opus 5", "GPT-5.1-codex" — never
"an AI" or "an agent". Say what it really checked; don't claim evidence you didn't gather.

> **How this was produced:** LLM-aided but human-driven — I had `<model + version>` analyze
> the branch and check its claims against `<the real evidence: the repo's checks on the PR
> head / the CI run / the plan artifact>`, then I challenged what it found and confirmed
> every point below myself.

Filled in:

> **How this was produced:** LLM-aided but human-driven — I had Claude Opus 5 analyze the
> branch and check its claims against the repo variables, tofu #238, and the real
> `release-deploy` run logs, then I challenged what it found and confirmed every point
> below myself.

If you don't know which model you're running as, ask the user — don't guess, and don't
fall back to something vague.

**3. Stance paragraph** — **2–4 sentences, no more.** What's genuinely good about the PR,
what the findings are about, and which (if any) touch its purpose or blast radius.

**4. Findings table** — severity-ranked, stable IDs, exactly these four columns:

```
| # | Finding | Severity | Disposition |
|---|---------|----------|-------------|
| F1 | **Bold one-line claim.** Then the evidence and failure mode, grounded in a file:line, a test name, or a CI line. | **High** | Fix-before-merge / fast-follow / out of scope. |
```

Lead each Finding cell with a bold one-sentence claim, then **at most three sentences** of
detail. If a finding needs more than that, it needs a diagram or a follow-up ticket, not a
longer cell. Mark out-of-scope items plainly, e.g. "(OUT OF SCOPE)".

**5. Verified while reviewing** — **one short paragraph**, or a tight bullet list if it
reads better. What you actually checked: which checks you ran and their result, which
assertions you read, whether you confirmed a test fails without the change, which CI
artifacts you read. **End with the limits** — what you couldn't run or sample. This is what
makes the review credible, so keep it factual and skip the adjectives.

**6. Suggested split** — one or two sentences separating cheap fix-before-merge items from
genuine follow-ups. Be explicit that nothing blocks merge unless it truly does.

Post it with a file, never an inline heredoc:

```sh
gh pr comment "$PR" --body-file "$WORK/review.md"
```

## Inline comments

Add inline comments when a finding is **about a specific changed line** and the reader
needs to look at that line to get it. They sit alongside the summary comment, not instead
of it — the table is still the full picture.

**Anchor a finding inline when:** it points at a line in the diff, and pointing is the
fastest way to explain it — a guard on the wrong branch, a renamed key its caller still
uses, an assertion that proves nothing, a hardcoded value.

**Keep it in the table only when:** the finding is about something *absent* (a missing
test, an unset variable, no protection rule), spans several files, or lives outside the
diff. There's no honest line to hang it on, and a stretched anchor confuses more than it
helps.

Rules that keep this from turning into a lint dump:

- **A few, not one per row.** If every finding got an anchor, you're commenting, not
  reviewing.
- **1–3 sentences each.** Lead with the finding ID so it ties back: `**F2** — this reads
  the old key; `resolveTenant` still writes the new one.` Detail lives in the table.
- **Never duplicate the table cell verbatim.** Inline says *what's wrong here*; the table
  says why it matters and what to do.
- **Suggest a fix as a suggestion block** when it's a genuine one-liner, so the author can
  commit it:

  ~~~
  ```suggestion
  const key = resolveTenant(ctx).id;
  ```
  ~~~

**Mechanics.** Post the summary and its inline comments as **one review** — a JSON payload
through `gh api`, so the author gets a single notification instead of a drip:

```sh
# $WORK/review.json — write it with a file tool, never an inline heredoc
# {
#   "event": "COMMENT",                      # or APPROVE / REQUEST_CHANGES
#   "body":  "<the summary comment>",
#   "comments": [
#     {"path": "src/tenant.ts", "line": 42, "side": "RIGHT", "body": "**F2** — ..."},
#     {"path": "ci/deploy.yml", "start_line": 8, "line": 12, "side": "RIGHT", "body": "..."}
#   ]
# }
gh api "repos/{owner}/{repo}/pulls/$PR/reviews" --input "$WORK/review.json"
```

Gotchas, all of which produce a 422 and lose the whole review:

- `line` must be a line **in the diff**. `side: RIGHT` for added or context lines, `LEFT`
  for removed ones. A line the diff doesn't include can't be anchored — move it to the
  table.
- Ranges need both `start_line` and `line` (same side). Whole-file comments need
  `"subject_type": "file"` and no line.
- The whole review is rejected atomically, so on a 422 fix the offending anchor or drop
  it — don't retry the same payload.

Same confirmation rule as everything else: **show the user the inline comments** — path,
line, and text — and get an explicit yes before posting. They're more visible than a
summary comment and land in the author's inbox line by line.

## Tone

**The reader is a colleague, not a linter.** Relaxed, plain, first-person. Everyday words.
Short sentences. Say what you mean without stacking hedges.

Length is part of the tone. Nobody reads the third paragraph of a review comment:

- Disclosure: **one sentence**.
- Stance: **2–4 sentences**.
- Each findings cell: **one bold claim + up to three sentences**.
- Each inline comment: **1–3 sentences**.
- Verified: **one paragraph** (or a tight list), limits at the end.

If a section is longer than that, you're explaining rather than reporting — cut it, or move
the depth into a follow-up ticket. Prefer the concrete over the abstract: "someone deletes
the variable, cuts a release, and sees a green check" beats "insufficient enforcement of
the configuration invariant". If a paragraph reads robotic, rewrite it before showing the
user — and certainly before posting it.

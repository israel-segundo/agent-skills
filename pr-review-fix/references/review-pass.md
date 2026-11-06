# Review pass resolution (Step 0a)

First match wins. Probe from the repo root; a repo-local skill or command beats a global one.

## Priority order

1. **Project review command** — emits the three-bucket contract *and* Polish/Behavioral labels
   this workflow keys off. Check, in order:
   - `.claude/commands/pr-review.md`
   - `.cursor/commands/pr-review.md`
   - `.codex/commands/pr-review.md`
   - `.agents/commands/pr-review.md`

2. **Repo-local review skill** — same directory names under the repo (not the global install):
   - `.claude/skills/pr-code-review/SKILL.md`
   - `.agents/skills/pr-code-review/SKILL.md`
   - `.cursor/skills/pr-code-review/SKILL.md`
   - Any repo-local skill whose name or description indicates PR/code review (e.g.
     `code-review`, `review-pr`). Read frontmatter; pick the one that matches a local review
     workflow.

   When invoking a skill meant for GitHub posting, pass **local-only** intent: no posts,
   no approvals, no pushes. Return structured findings only.

3. **Global `pr-code-review-batch` skill** — unattended scan; writes findings with severities.
   Map severities to buckets in the subagent prompt (High / Fix before merge → must-fix;
   Medium → should-fix; Low → nit). Apply the Polish test yourself for triage (Step 2b).

4. **Global `pr-code-review` skill** — use only if batch is unavailable; instruct the
   subagent to run Steps 0–7 locally without posting or the challenge loop.

5. **Project `code-review` skill** at `.claude/skills/code-review/` or `.agents/skills/code-review/`
   — invoke with `--local-only` if the skill supports it.

6. **Built-in `/code-review` command** on the host, if present.

## Labels and fallbacks

Options 3–6 do **not** reliably emit Polish/Behavioral labels. That does not change *whether*
a finding gets fixed — this skill fixes every bucket — but the label decides whether the fix
ships with a test (Step 2b), so apply the Polish test yourself when one of these is in play,
and say so in the final summary.

## Scope hint for the subagent

Hand the subagent:

- The resolved review pass path or skill name
- Scope from Step 1 (`git diff <default-branch>...HEAD` plus working tree, or PR number)
- The **fix ledger** from prior rounds — every finding already fixed, with its id and what
  changed. Ask the reviewer to check those fixes rather than re-raise them, and say plainly
  that a previously-fixed finding is fair game again **only if the fix did not hold**.

Ask for findings as structured JSON (see Step 2a in `SKILL.md`), and tell the subagent that an
empty array is a valid answer on a clean branch — every finding it returns will be applied, so
a speculative one costs real edits.

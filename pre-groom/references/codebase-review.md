# Codebase & standards review

Run only when at least one checkout path resolved. Search **every** resolved path
(`REPO_PATH` plus `EXTRA_REPO_PATHS`). Do not treat findings as definitive.

## 2a. Cross-reference

1. **Keywords** — extract 3–5 terms from summary + description (feature names, paths,
   symbols, collection/table/API names).
2. **Search** each checkout:

```sh
REPO_PATH=/path/to/checkout
# Prefer ripgrep; fall back to grep -R
rg -n -S -g '!node_modules' -g '!dist' -g '!build' -g '!.git' 'keyword' "$REPO_PATH"
```

3. **Discover layers** from the repo itself — do not assume a product layout:

```sh
# Top-level shape
ls -la "$REPO_PATH"
# Project guidance (read what exists)
for f in AGENTS.md CLAUDE.md CONTRIBUTING.md README.md \
  .specify/memory/constitution.md docs/constitution.md; do
  [ -f "$REPO_PATH/$f" ] && echo "found $f"
done
```

Group hits by whatever layers the repo actually has (examples — use real names from the
tree): backend/services, frontend/ui, shared/types, infrastructure/config, tests. Omit empty
groups.

4. **Test coverage** — look for tests near affected areas (`**/__tests__/**`, `**/*test*`,
   `**/e2e/**`, `**/spec/**`, etc.).
5. **High-risk surfaces** — flag paths that look like authz rules, permissions maps,
   migrations/schema, shared cross-feature utilities, or secret/config wiring. Prefer cues
   from the repo's own docs over generic guesses.
6. **Gaps** — call out unconfirmed files, places that need engineer domain knowledge, and
   work the description omitted.
7. **Other tickets / repos** — if search or issue links point at another system, resolve that
   checkout (ask + optional registry update) and include a separate layer group labeled with
   that path. Allowed and expected when the ticket spans systems.

**Presentation template** (adapt section titles to the repo):

```
Backend:
  • path/to/file — [why flagged]

Frontend:
  • path/to/file — [why flagged]

Shared:
  • path/to/file — [why flagged]

Infrastructure:
  • path/to/file — [why flagged]

Tests:
  • path/to/test — [existing coverage]

Other checkout (/abs/path/to/sibling):
  • path/to/file — [why flagged]
```

Use hedging language throughout.

## 2b. Project standards / constitution

If a constitution or equivalent standards doc exists (common paths above, or whatever
`AGENTS.md` / `CONTRIBUTING.md` points at), read it. Flag **only** principles that
**directly** apply to this ticket's likely changes — never dump the whole document.

**How to build the flag list:**

- Map ticket keywords + affected paths → named principles in that doc.
- For each flag: `• [Principle name] — [what's required for this ticket]`.
- If nothing applies: `No specific constitution concerns identified.`

When the repo has no constitution, skim `AGENTS.md` / `CONTRIBUTING.md` / `docs/` for
hard rules (testing required, no raw permission strings, schema sync, etc.) and flag those
the same way under a `Project standards:` heading.

**Security-oriented flags** (when the standards doc or the change surface warrants them):

- Auth, permissions, or user-data access → least privilege / explicit authz checks
- Security-rule or policy file changes → required tests before deploy (if the repo says so)
- New privileged entrypoints → authentication required; justify bypass of normal access control
- Secrets/credentials → secret manager / no hardcoded secrets

## 2c. System diagram (optional)

Generate a diagram only when multi-component changes, data-flow shifts, or architecture
shifts make a file list insufficient. Prefer:

- **Flowchart** — data flow
- **Sequence diagram** — multi-step workflows
- **Component diagram** — module interaction

Skip for single-file changes, simple bugfixes, or low-clarity-gain cases.

**Output:** Mermaid often does not render in CLI hosts. Write a minimal self-contained HTML
file under `$WORK` (the session temp dir from Step 0 — never inside a repo) that loads Mermaid
from a CDN and renders the diagram with a title. Then open it with a portable opener:

```bash
KEY=PROJ-123
FILE="$WORK/pre-groom-${KEY}.html"
# …write HTML to $FILE…
open "$FILE" 2>/dev/null \
  || xdg-open "$FILE" 2>/dev/null \
  || cmd.exe /c start "" "$FILE" 2>/dev/null \
  || echo "Open $FILE in your browser"
```

## Security review checkpoint

Trigger when Step 2 identified **any** of:

- Changes to authorization / security-rule / policy files with production-wide blast radius
- New or modified **admin-privileged** entrypoints that bypass normal data-store rules
  (callables, privileged workers, break-glass APIs — use the repo's own terms)
- Ticket text that proposes the above

Otherwise skip.

When triggered, present a dedicated callout. Adapt names to what you actually found:

```
⚠ SECURITY / AUTHZ CHANGE DETECTED ⚠

This ticket modifies authorization or privileged entrypoints.
Changes can affect many users and have wide blast radius.

Location: [path + approximate lines if known]
What's changing: [brief]

Required before merge (adjust to repo standards):
  • Tests that prove allow and deny paths for affected roles
  • Review by at least one engineer familiar with these controls
  • Any emulator / staging proof the constitution requires
```

If a privileged entrypoint is involved, add:

```
⚠ PRIVILEGED ENTRYPOINT DETECTED ⚠

This path runs with elevated privileges and may bypass normal
data-store security rules. Authorization MUST be enforced inside
the entrypoint itself.

Entrypoint: [name and path]
Reason: [why this shape instead of a direct constrained write]

Required before merge:
  • Explicit caller permission checks
  • Justify why a narrower direct write is insufficient
  • Authz tests for valid and invalid callers
```

Cross-check against the repo's guidance on privileged vs direct writes when such a section
exists. If a direct constrained write would suffice, raise that as a Step 3 question.

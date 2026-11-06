# Jira description template

Use this structure for Format A output and for `$WORK/description.md` on write-back.
Omit any section with nothing to say — do not pad with placeholders.

## Disclaimer (required on write-back)

Place at the **top** of every Jira description and Slack message that replaces posted content.
Fill the link after the archive comment is posted (Jira) or from the source permalink (Slack).

```markdown
> This text was **deslopified** with `/deslopify`. To consult the original text: [original text]({original_link})
```

| Context | `{original_link}` |
|---------|-------------------|
| Jira write-back | Permalink to the archive comment posted in Step 8a (capture id/URL from the transport response) |
| Jira preview (before post) | `{archive comment — linked after approval}` |
| Slack rewrite | Permalink to the source message (`https://…slack.com/archives/…/p…`) when available |
| Slack, no permalink | Ask once, or post the original as a thread reply first and link that message |

## Description body

Derive the **summary** (issue title) from Core Goal — ≤80 chars, imperative, no filler.

```markdown
> This text was **deslopified** with `/deslopify`. To consult the original text: [original text]({original_link})

## 🎯 Core Goal

[What are we building and why? One short paragraph — lead with the change, who is affected, and why it matters.]

## 💡 Business Value

[One sentence on operational or user impact. Omit when already obvious from Core Goal.]

## 🗂️ Affected Repositories

- [org/repo](https://github.com/org/repo) — [role: API, web, contracts, etc.]
- _None identified_ — only when the input names no repos and none are clearly implied

## 📋 Acceptance Criteria / Scope

- [ ] Deliverable 1
- [ ] Deliverable 2

## 🔀 Potential Subtasks / Split Scope

- [ ] Subtask 1 — independent: yes/no
- [ ] Subtask 2 — depends on: …

## ⛔ Out of Scope

- Item explicitly excluded

## 🚧 Dependencies & Blockers

- [TICKET-123]({jira_site}/browse/TICKET-123) — [what it blocks]
- External team / approval — [detail]

## ❓ Open Questions

- Unresolved decision or missing detail — owner: Engineering/Product

## 🔗 Links / Refs

- [Contract/Spec](url)
- [Design / Figma](url)
```

### Section rules

| Section | When to include |
|---------|-----------------|
| Business Value | Impact is stated or clearly implied but not folded into Core Goal |
| Affected Repositories | Any repo, service, or package named or clearly implied |
| Acceptance Criteria | Concrete deliverables, behaviors, or AC from the source |
| Potential Subtasks | Multiple components, phases, or teams buried in one ticket |
| Out of Scope | Anything explicitly excluded or deferred |
| Dependencies & Blockers | Blocking tickets, teams, flags, migrations, approvals |
| Open Questions | Gaps, ambiguities, or decisions not resolved in the source |
| Links / Refs | URLs, doc names, or ticket keys cited in the input |

Tag inferred items with `(inferred)` in the bullet text. Move pure speculation to **Open
Questions** instead of Acceptance Criteria.

## Wiki markup variant (`jira` CLI comments only)

The **description** body stays markdown (the CLI converts on edit). The **archive comment**
uses wiki markup — see Step 8a in `SKILL.md`.

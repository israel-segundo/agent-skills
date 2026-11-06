# Deslopify examples

## Example 1 — Jira / Technical Spec (Format A)

**Input (excerpt):**

> In order to ensure a seamless user experience across our platform ecosystem, this initiative
> serves as a middle layer to synthesize notification preferences from disparate sources and
> leverage the existing messaging infrastructure to deliver a unified experience. Stakeholders
> have expressed that users are confused. We should also consider push notifications. Depends on
> AUTH-442 being done. Mobile is out for now. Repos: product-api, product-web.

**Output:**

**Proposed summary:** Unify notification preferences into one settings screen

```markdown
> This text was **deslopified** with `/deslopify`. To consult the original text: [original text]({archive comment — linked after approval})

## 🎯 Core Goal

Ship a single notification-preferences UI that reads from all current sources and writes back
through the existing messaging stack, so users stop managing settings in three places.

## 💡 Business Value

Fewer misconfigured alerts and less support volume from "I turned it off but still get emails."

## 🗂️ Affected Repositories

- [product-api](https://github.com/example/product-api) — preference sync service and APIs
- [product-web](https://github.com/example/product-web) — settings UI

## 📋 Acceptance Criteria / Scope

- [ ] Settings UI for notification channels (email, in-app)
- [ ] Preference sync over existing messaging APIs

## 🔀 Potential Subtasks / Split Scope

- [ ] Map current preference storage per product — independent: yes
- [ ] Build read/write sync service — depends on: storage map
- [ ] Ship settings UI + API wiring — depends on: sync service

## ⛔ Out of Scope

- Push notifications
- Mobile clients

## 🚧 Dependencies & Blockers

- [AUTH-442](https://example.atlassian.net/browse/AUTH-442) — auth/session changes must land first

## 🔗 Links / Refs

- _None in source_
```

---

## Example 2 — Slack message rewrite (Format B)

**Input:** Slack message at `https://example.slack.com/archives/C123/p4567890123456`

> Hi team — wanted to loop everyone in on the Q3 planning sync. We'll be discussing roadmap
> priorities and I think it would be great if folks could come prepared with any blockers they're
> seeing. Let me know if the Thursday 2pm slot works or if we should move it. Thanks!

**Output:**

```markdown
> This text was **deslopified** with `/deslopify`. To consult the original text: [original text](https://example.slack.com/archives/C123/p4567890123456)

**Action Required:** Yes — Confirm attendance and share blockers before Thursday 2pm planning sync.

**Core Message:** Q3 planning sync is Thursday at 2pm. Come with your current blockers; reply if that time doesn't work.

**Key Points:**

* Topic: Q3 roadmap priorities
* Prep: bring blocker list
* Time: Thursday 2pm (confirm or propose alternative)
```

---

## Example 3 — Jira archive comment (before replace)

When the user approves write-back on `PROJ-123`:

```markdown
## Original issue text (archived before deslopify)

**Summary:** Implement comprehensive notification orchestration layer

**Description:**

In order to ensure a seamless user experience across our platform ecosystem, this initiative
serves as a middle layer to synthesize notification preferences...

_Archived before deslopify (Composer 2.5)._
```

After the comment is posted, set the description disclaimer link to that comment's URL, then
apply the Format A body from Example 1.

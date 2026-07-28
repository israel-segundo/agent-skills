# agent-skills

Portable agent skills, written once and installed into every AI coding agent on the
machine.

## Following the Agent Skills open spec

These skills follow the [Agent Skills open standard](https://agentskills.io) — the
`SKILL.md` format that emerged from Claude Code, published as an open spec and now
stewarded by the Linux Foundation's Agentic AI Foundation. The same directory is read
unmodified by Claude Code, Codex CLI, Gemini CLI, Cursor, Copilot and 25+ other hosts.

What that means in practice, and what every skill here sticks to:

- **A skill is a directory containing `SKILL.md`.** The directory name matches the
  frontmatter `name`.
- **Only two frontmatter fields are required**: `name` (≤64 chars, lowercase-hyphen) and
  `description` (≤1024 chars, stating both what it does *and* when to trigger it).
  Optional standard fields: `license`, `compatibility`, `metadata`, `allowed-tools`.
- **Vendor-specific fields are allowed but never load-bearing.** Hosts ignore frontmatter
  they don't know (`when_to_use`, `argument-hint`, `context`, `user-invocable`), so they
  are safe to include — but no skill here *depends* on one being honoured.
- **Progressive disclosure.** `SKILL.md` stays under ~500 lines and defers detail to
  `references/`, loaded only at the step that needs it.
- **The body targets the shell, not a host's tool names.** Work happens through `git`,
  `gh`, `jq`, `rg` — not "use the Grep tool". Capabilities are probed at runtime and
  degrade explicitly when absent, so a skill states what it couldn't verify rather than
  assuming a capability exists.

## Inventory

| Skill | What it does | Invoke |
|---|---|---|
| [`pr-code-review`](pr-code-review/) | Adversarial, human-in-the-loop review of someone else's open PR. Learns the repo's documented rules, names the PR's central claim, then verifies it against real evidence — runs the repo's own checks on the PR head in a throwaway worktree, reads the CI run and artifacts, checks the issue's acceptance criteria. Scans the diff across 14 safety dimensions (blast radius, irreversibility, contracts, secrets, weak tests). Tracks findings with IDs and severities, shows them as a local HTML table, and only on request posts a deduped, severity-ranked review comment and offers an approval decision. | `/pr-code-review [pr-number]` |
| [`pr-address-feedback`](pr-address-feedback/) | The other side of a review: takes the new comments on your own PR and drives them to done. Validates each one against the actual code, shows the consolidated plan as a local HTML report and waits for sign-off, then fixes blocking items first, files a real ticket for everything deferred, runs the repo's own checks until green, pushes on confirmation, and replies to and resolves the human threads. Nothing is silently dropped — every finding is fixed, ticketed, declined in writing, or skipped with a reason. Idempotent, so a re-run sees only genuinely new comments. | `/pr-address-feedback` |
| [`git-rebase`](git-rebase/) | Brings the current branch up to date with the repo's actual default branch — resolved, not assumed. Stashes, fetches, rebases, resolves the conflicts, regenerates lockfiles instead of hand-merging them, falls back to a merge on a named stop condition rather than grinding through a cascade, and restores the stash. Only ever touches the local branch. | `/git-rebase` |
| [`git-amend`](git-amend/) | Folds working-tree changes into the last commit so a review cycle ends as one commit instead of a trail of "address review comment" commits. Stages by name, never `-A`, skips generated output, refuses secrets, and appends an `## Amendments` round to the message saying what changed in each file. Checks whether the commit is already published first, and names the push you'll need without running it. | `/git-amend` |
| [`jira-update-issue`](jira-update-issue/) | Leaves a plain-language progress comment on the Jira issue behind the current branch, written for whoever plans the sprint rather than whoever reads the diff. Resolves the key from the PR or branch name, discovers the site from the repo's docs or the local config instead of assuming a tenant, and posts through whichever transport exists — printing the finished comment and the exact command when none does. | `/jira-update-issue` |

## Install

```sh
./install.sh              # symlink into every host skills dir that exists
./install.sh --copy       # copy instead — for hosts whose discovery won't follow symlinks
./install.sh --dry-run    # show what would happen
./install.sh --host ~/.foo/skills   # also target an extra path
```

Idempotent: re-run after adding a skill, editing one, moving this repo, or installing a
new agent. It computes its own source path, replaces stale links, and skips hosts that
aren't installed.

Targets, when present:

| Path | Host |
|---|---|
| `~/.claude/skills/` | Claude Code |
| `~/.agents/skills/` | shared cross-tool convention (Codex CLI, Gemini CLI, others) |
| `~/.gemini/skills/` | Gemini CLI |
| `~/.codex/skills/` | Codex CLI |
| `~/.cursor/skills/` | Cursor |
| `~/.qwen/skills/` | Qwen Code |

Symlink discovery is flaky on some hosts — Gemini CLI and Cursor's CLI have both had bugs
where symlinked skills aren't found. If a host lists no skills, re-run with `--copy` for
that host.

For a host with no native skill support, a skill is still just markdown: point the agent
at the file — "read `pr-code-review/SKILL.md` and follow it". Every skill here is written
to be self-contained enough for that fallback.

## Layout

```
agent-skills/
  install.sh                    # symlink-or-copy fan-out
  <skill-name>/
    SKILL.md                    # <500 lines; frontmatter + procedure
    references/                 # detail loaded on demand
```

## Adding a skill

Keep it portable:

1. Directory name == frontmatter `name`. `description` under 1024 chars and written so a
   host can *trigger* on it — say when to use it, not just what it is.
2. No host tool names in the body. Express intent, and give the shell command that does
   it. Assume no host prompts before running commands.
3. Probe capabilities instead of assuming them; when one is missing, say so and degrade.
4. Anything over ~500 lines moves to `references/`.
5. Numbered steps with explicit stop conditions — a skill that only works on a frontier
   model isn't portable. If step 9 needs step 1's output, write it to a file.
6. Scope repo-specific knowledge to a repo-local skill of the same name
   (`.claude/skills/<name>/`, `.agents/skills/<name>/`), which takes precedence over the
   copy installed here.

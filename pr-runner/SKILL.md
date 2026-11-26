---
name: pr-runner
description: >-
  Keep your open PRs moving without watching them: one sweep over every open PR you
  authored decides, per PR, whether pr-shepherd (feedback, red CI, conflicts) or pr-queue-for-merge
  (approved and green) should run, finds that PR's local worktree, and runs the skill there
  through your agent CLI, one PR at a time. Optionally starts the plan's next slice with
  execute-plan after a merge. Deterministic: classification is a script, so no agent starts
  unless there is work. Skips PRs with no local worktree, uncommitted changes, another skill
  already running, or a block that nothing new has touched. Run by hand for a dry-run table,
  or on a timer for an agentic loop. Use when you want review rounds, merges and next
  slices to happen on their own.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. The sweep is a bash script (gh, jq, git,
    coreutils timeout) and dispatches to whichever agent CLI is configured or found
    (codex, claude, gemini, cursor-agent, opencode, qwen, or any command you name). Reuses
    my-open-prs/scripts/fetch.sh for classification. Config
    lives in ~/.config/pr-runner/config only; state in ~/.cache/pr-runner.
when_to_use: >-
  Use to see what the agentic loop would do with your open PRs right now (dry run), to run
  one real sweep, or to set up the timer that runs it every few minutes. Not for one
  specific PR (run pr-shepherd or pr-queue-for-merge there directly) and not for other people's PRs.
argument-hint: "[--dispatch] [--only owner/repo#N]"
allowed-tools:
  - Bash
  - Read
---

# PR runner (sweep your PRs, dispatch the right skill)

`$SKILL_DIR` is the directory this file was loaded from (fallbacks
`~/.agents/skills/pr-runner` or the host's own skills directory). The sweep needs **my-open-prs**,
**pr-shepherd**, **pr-queue-for-merge** and (for next slices) **execute-plan** installed next to it.

## What a sweep decides

For each open PR you authored (from `my-open-prs/scripts/fetch.sh`):

| PR state | Decision |
|---|---|
| draft | skip |
| conflicted, changes requested, feedback since the last push, or CI failing | **pr-shepherd** |
| approved, CI not pending | **pr-queue-for-merge** when `auto_land=true`, else skip |
| anything else (awaiting review, CI pending) | skip, with the reason |

Then, before dispatching, it skips the PR when:

- the repo isn't under `roots` (or not in the `repos` allowlist, when one is set)
- the head branch has **no local worktree**. Having a worktree is the opt-in: PRs you opened
  from elsewhere are left alone
- the worktree has uncommitted changes (someone's working there)
- execute-plan, pr-launch, pr-shepherd or pr-queue-for-merge holds a fresh lock in that worktree
- the last run on that PR was BLOCKED and the PR hasn't changed since (no new commit or
  activity), so a stuck PR isn't retried every sweep

After a pr-queue-for-merge `DONE` whose `NEXT:` line names a plan slice, and with
`auto_next_slice=true`, it runs **execute-plan** `--unattended <plan>` from the repo's main
checkout, which hands off to pr-launch in a fresh worktree.

## Run it

**By hand (dry run, the default):**

```sh
"$SKILL_DIR/scripts/sweep.sh"                 # what would run, and why everything else is skipped
"$SKILL_DIR/scripts/sweep.sh" --only acme/api#42
```

Show the table to the user as is.

**One real sweep:** `"$SKILL_DIR/scripts/sweep.sh" --dispatch`. Each dispatched run's log is in
`~/.cache/pr-runner/logs/`, and its `RESULT:` line is printed. A BLOCKED result also raises a
desktop notification when `notify-send` exists.

## Configure

`~/.config/pr-runner/config` (or `$PR_RUNNER_CONFIG`), `key=value`, `#` comments. See
[`examples/config.example`](examples/config.example).

| Key | Default | Meaning |
|---|---|---|
| `roots` | `~/repos` | Comma-separated folders holding your main checkouts (worktrees are found through them) |
| `repos` | all | Comma-separated `owner/repo` allowlist |
| `agent` | auto, only when exactly one known CLI is installed | The headless agent command, e.g. `codex exec`, `gemini -p`, `claude -p`, `cursor-agent -p`, `opencode run`; the prompt is appended as one argument |
| `prompt_style` | the agent's known default | `slash` (`/<skill> args`) or `plain` (`Use the <skill> skill. args`). Hosts that honour user-only skill flags (execute-plan is one) need `slash` |
| `auto_land` | `false` | Dispatch pr-queue-for-merge for approved, green PRs. This is the switch that merges without you |
| `auto_next_slice` | `false` | After a merge, start the plan's next unblocked slice |
| `notify` | `true` | Desktop notification on BLOCKED |
| `timeout_min` | `120` | Per-dispatch time limit |

**Headless permissions.** The agent runs without anyone to approve commands, so its own
permission settings must already allow what the skills run: `git`, `gh`, `jq`, the repos'
verify and test commands, the Slack and Jira transports, and file edits in the worktrees and
plan folder. Prefer a narrow allowlist in the agent's settings over a blanket bypass flag.
Run `--dispatch --only <one PR>` once by hand and read the log before turning on the timer:
a permission denial shows up there as a BLOCKED run.

## Schedule

Every 15 minutes is plenty: review rounds take hours, and each sweep that finds nothing to do
costs only GitHub API calls.

- **systemd (user):** copy [`examples/pr-runner.service`](examples/pr-runner.service) and
  [`examples/pr-runner.timer`](examples/pr-runner.timer) to `~/.config/systemd/user/`, fix
  the `ExecStart` path, then `systemctl --user daemon-reload &&
  systemctl --user enable --now pr-runner.timer`. Logs: `journalctl --user -u pr-runner`.
- **cron:** `*/15 * * * * $HOME/.agents/skills/pr-runner/scripts/sweep.sh --dispatch >> $HOME/.cache/pr-runner/cron.log 2>&1`
  (cron's `PATH` is minimal: set it at the top of the crontab so `gh`, `jq`, the agent CLI
  and the repos' toolchains resolve).
- **Inside an agent session:** a host loop command running `sweep.sh --dispatch` works too,
  but stops when the session ends.

Turn it off with `systemctl --user disable --now pr-runner.timer` (or remove the cron line).
Setting `auto_land=false` keeps review rounds automatic and leaves merging to you.

## Principles

- **Decide in code, act through skills.** The script only routes; every change to a PR is
  made by pr-shepherd, pr-queue-for-merge or execute-plan with their own guardrails.
- **A worktree is consent.** No local worktree, no dispatch.
- **Never two skills on one worktree.** Locks are respected, and runs are sequential.
- **Don't hammer a blocked PR.** Retry only when something about it changed.
- **Merging is opt-in.** `auto_land` and `auto_next_slice` default to off.

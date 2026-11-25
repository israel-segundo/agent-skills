---
name: dev-services
description: >-
  Start, watch and stop a repository's long-running local services (emulators, dev servers,
  databases, containers, end-to-end runners) safely and in the open. Resolves how this repo
  runs its services from a per-user recipe in ~/.config/dev-services/ or from the repo's own
  docs instead of guessing, checks that every port and container is free and who holds it
  before starting, never kills or reseeds a process another worktree or session started,
  runs each service in a visible terminal pane (Herdr, tmux, zellij) with a log file, waits
  on the run's own ready and failure lines rather than fixed sleeps, and tears down
  everything it started when the work is done. Use when the user asks to start, restart,
  stop or check emulators or a dev server, or when a test run needs local services. Ends
  with a parseable RESULT line.
license: Unlicense
metadata:
  version: "1.0.0"
  portability: >-
    Written to the Agent Skills open standard. Body uses shell (git, lsof, ps, docker) rather
    than host-specific tools. Repo-specific commands, ports and standing permissions live in
    ~/.config/dev-services/<repo>.md only; nothing is written into repositories. Uses Herdr,
    tmux or zellij for visible panes when present, and says so when none is.
when_to_use: >-
  Use when local services have to be started, restarted, checked or stopped: emulators, a
  dev server, containers, an end-to-end run that needs them. Also when a port is busy and
  you need to know who holds it. Not for remote or hosted environments, and not for
  deploying.
argument-hint: "[start|stop|restart|status] [service ...]"
allowed-tools:
  - Bash
  - Read
---

# Dev services (run local services safely, in visible panes)

Bring a repo's local services up, know they are really up, and take down only what you
started.

**Two ways to run:**

- **Standalone** (a user invoked it): starting and stopping follow the recipe's
  `Authorization` section. With no recipe, or no authorization in it, show the commands you
  would run and wait for a yes.
- **Called by an orchestrator** (pr-launch, a test skill): the same limits apply. An
  orchestrator's authorization never extends to processes this worktree did not start.

## Rules that always hold

- **Never kill, restart, reseed or remove a process or container this worktree did not
  start.** Not even when it blocks your run. Stop, report who holds what (port, pid,
  working directory, command) and ask. Offer to wait instead.
- **A permission to kill covers the one action it was given for.** Ask again the next time.
  A monitoring task carries no destructive authority.
- **Check before you start.** Many start commands begin by killing whatever is already
  running, machine-wide. Run the preflight in Step 2 first, every time.
- **Local only.** Never point a seed, migration or data generator at a remote project. If
  the environment could resolve to one, stop.
- **Visible, not hidden.** Long-running processes go in a terminal pane the user can watch,
  with output copied to a log file you can search.
- **No blind waiting.** No fixed sleeps, no single multi-minute wait. Short checks that match
  failure lines as well as the ready line.
- **Say only what you read.** If a wait was interrupted or timed out, read the pane and the
  log before stating what did or did not run.
- **Leave nothing behind.** When the work is done, stop what you started (Step 7).

## Step 0: Probe

```sh
command -v git lsof ps docker
printf 'herdr=%s tmux=%s zellij=%s\n' "${HERDR_ENV:-}" "${TMUX:+1}" "${ZELLIJ:+1}"
```

Say what is missing. Without `lsof`, use `ss -ltnp` for the port check. Without `docker`,
skip the container checks and say so.

## Step 1: Resolve the recipe

A recipe is a markdown file the user keeps outside every repo, one per repository:

```sh
DIR="${DEV_SERVICES_DIR:-$HOME/.config/dev-services}"
REPO=$(basename -s .git "$(git remote get-url origin 2>/dev/null)")
[ -n "$REPO" ] || REPO=$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")
RECIPE="$DIR/$REPO.md"
[ -f "$RECIPE" ] && cat "$RECIPE"
```

A linked worktree resolves to the same recipe as the main checkout. Read the whole file
before doing anything. It is the authority for this repo, and its sections are:

| Section | What it gives you |
|---|---|
| `Authorization` | What you may do without asking, and what always needs a question |
| `Services` | Each service's start command, log file, ready line and failure lines |
| `Ports and containers` | Every port and container name the stack uses |
| `Prepare a worktree` | Installs and files a fresh worktree needs before the first start |
| `Stop` | How to stop, and what a plain interrupt leaves behind |
| `Data safety` | Checks to pass before a seed or data generator |
| `Tests against the stack` | Test commands, worker caps, memory limits |
| `Gotchas` | Failures seen before and what they really meant |

**No recipe:** read the repo's own docs for the same facts (README, CONTRIBUTING, AGENTS.md,
CLAUDE.md, `docs/`, then `package.json` scripts, `Makefile`, `docker-compose*.yml`). Say that
no recipe exists and which file each command came from. Nothing is authorized ahead of
time: show the plan and wait for a yes. Do not invent a start command.

## Step 2: Preflight (ports, containers, owners)

List every port and container from the recipe, then see who holds them:

```sh
WT=$(git rev-parse --show-toplevel)
owner_cwd() {  # owner_cwd <pid> -> that process's working directory
  if [ -e "/proc/$1/cwd" ]; then readlink "/proc/$1/cwd" 2>/dev/null
  else lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'; fi
}
for port in $PORTS; do
  for pid in $(lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null); do
    ppid=$(ps -o ppid= -p "$pid" | tr -d ' ')
    printf 'port=%s pid=%s cwd=%s parent_cwd=%s cmd=%s\n' "$port" "$pid" \
      "$(owner_cwd "$pid")" "$(owner_cwd "$ppid")" "$(ps -o args= -p "$pid" | cut -c1-80)"
  done
done
docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null   # compare with the recipe's names
```

A listener is **yours** only when its working directory, or its parent's, is inside `$WT`
and you (or an earlier step of this task) started it. Then:

| Preflight shows | Do |
|---|---|
| Nothing listening, no containers | Go on to Step 3 |
| Everything is yours and healthy | Reuse it, or restart it if the task needs a clean state |
| Anything that is not yours, or that you cannot attribute | **Stop.** Report port, pid, working directory and command. Ask. Do not kill it. `RESULT: BLOCKED` |

A container has no working directory to check. Treat a recipe container that is already
running as not yours unless this task started it.

## Step 3: Prepare the worktree

Run the recipe's `Prepare a worktree` section when this checkout has never run the stack
(no dependency directories, no local env file). A missing install usually shows up later
as an unrelated-looking timeout, so do this before the first start, not after it fails.

## Step 4: Start each service in a visible pane

Shell aliases and functions only resolve in an interactive shell. A pane has one. A
non-interactive command runner does not. So when the recipe's start command is an alias, run
it in a pane, never by re-typing what you think the alias expands to.

Every command you start should copy its output to a log file of its own (unless the recipe's
command already does) and finish with a marker line, so a later check can tell this run from
the last one:

```sh
<start command> 2>&1 | tee "/tmp/dev-services-$REPO-<service>.log"; echo "DEVSVC_<SERVICE>_EXIT=$?"
```

**Inside Herdr** (`HERDR_ENV=1`). If no Herdr skill is in your context, run `herdr --skill`
once and follow it for syntax.

```sh
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$WT" --label "<service>" --no-focus
herdr pane run <root-pane-id> "<start command>"
```

- Always pass `--workspace "$HERDR_WORKSPACE_ID"` (or split your own pane with
  `herdr pane split --current ... --no-focus`). Without it Herdr uses the focused workspace,
  which may be the user's.
- Never focus a tab or pane outside your own workspace.
- `herdr pane run` into a pane whose process is still in the foreground only types into that
  process. To restart: `herdr pane send-keys <pane> ctrl+c`, confirm with
  `herdr pane process-info` that the process is gone, then run.
- Take pane IDs from the command's JSON response. Never reuse an ID from memory or notes.

**Inside tmux:** open the window, then type into its interactive shell so aliases resolve:

```sh
tmux new-window -d -n <service> -c "$WT"
tmux send-keys -t <service> '<start command>' Enter
```

**Inside zellij:** `zellij run --name <service> --cwd "$WT" -- bash -ic '<start command>'`.

**No multiplexer:** start it as a background job with the same log file, and tell the user
that it is not visible and where the log is.

## Step 5: Wait until it is really up

Poll the run's **own log file** in short checks (30 to 60 seconds apart at most) for the
recipe's ready line and its failure lines:

```sh
grep -nE '<ready line>|<failure lines>|DEVSVC_<SERVICE>_EXIT=' "/tmp/dev-services-$REPO-<service>.log" | tail -5
```

- Do not trust a wait on a reused pane's scrollback. It can match the previous run's line.
- A failure line or an exit marker before the ready line means it failed. Read the log
  upward from that line for the first real error. The last message is often a timeout that
  names the wrong component.
- Ready line seen, then confirm the ports from Step 2 are now listening.

## Step 6: Use the stack

- **Seeds and data generators:** pass the recipe's `Data safety` checks first, and re-run the
  Step 2 owner check on the port you are about to write to. Not yours, or nothing listening,
  means stop and say so.
- **Test suites:** use the recipe's commands and its worker and memory limits. With no limit
  given, prefer small batches over one large run, and watch free memory during a heavy suite:

  ```sh
  awk '/MemAvailable/ {print int($2/1024) " MB available"}' /proc/meminfo
  ```

  If it keeps falling toward the recipe's floor, stop the run and retry with fewer workers,
  not the same shape.

## Step 7: Tear down

When the task that needed the stack is finished (or the user says stop), take down what you
started, in this order:

1. Interrupt each pane's process (`ctrl+c`) and wait for it to exit.
2. Sweep what an interrupt leaves behind, per the recipe's `Stop` section: child runtimes,
   worker processes, containers. Scope every kill to pids whose working directory is inside
   `$WT`, and every container removal to the names this task started.
3. Re-run the Step 2 check. No port and no container from the recipe may remain.
4. Close the panes and tabs you created, and any browser you opened for the work.

Do not leave services up "in case the user wants to look". Say they are down and offer to
start them again. A machine-wide kill command from the recipe is only safe when Step 2
showed nothing that belongs to someone else.

## Step 8: Report

State what is running (service, pane, log file, ports) or what was stopped, anything you
could not verify, and then:

```
RESULT: READY (<services>)
RESULT: STOPPED (<services>)
RESULT: BLOCKED (<port/container> held by pid <pid> in <dir>: <command>)
```

## Keeping the recipe current

When a run teaches you something the recipe lacks (a new port, a leftover process, a
misleading error), tell the user and offer the exact lines to add to
`~/.config/dev-services/<repo>.md`. Do not write repo-specific service knowledge into this
skill or into the repository.

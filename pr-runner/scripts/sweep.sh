#!/usr/bin/env bash
# pr-runner: one sweep over your open PRs. Decides, per PR, whether pr-shepherd or pr-land
# should run in that PR's local worktree, and (with --dispatch) runs it headlessly through
# your agent CLI, one PR at a time. Deterministic: no agent is started unless there is work.
#
# Requires: gh (authenticated), jq, git; an agent CLI for --dispatch
# Usage:    sweep.sh [--dry-run | --dispatch] [--only owner/repo#N]
# Config:   ${PR_RUNNER_CONFIG:-~/.config/pr-runner/config}  (key=value, see examples/)
# State:    ${XDG_CACHE_HOME:-~/.cache}/pr-runner/{lock,state.json,logs/}
# Output:   one line per PR, then "SWEEP: <n dispatched> dispatched, <n blocked> blocked"
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required" >&2; exit 1; }; }
need gh; need jq; need git

SELF=$(readlink -f "${BASH_SOURCE[0]}")
SKILLS_DIR=$(dirname "$(dirname "$(dirname "$SELF")")")
FETCH="$SKILLS_DIR/my-open-prs/scripts/fetch.sh"
[ -x "$FETCH" ] || { echo "error: $FETCH not found (install my-open-prs next to pr-runner)" >&2; exit 1; }

MODE=dry-run; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  MODE=dry-run ;;
    --dispatch) MODE=dispatch ;;
    --only)     shift; ONLY="$1" ;;
    -h|--help)  sed -n '2,10p' "$SELF"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# ── config ────────────────────────────────────────────────────────────────────
CONFIG=${PR_RUNNER_CONFIG:-$HOME/.config/pr-runner/config}
roots="$HOME/repos"; repos=""; agent=""; prompt_style=""; auto_land=false; auto_next_slice=false
notify=true; timeout_min=120
if [ -f "$CONFIG" ]; then
  while IFS='=' read -r k v; do
    k=$(printf '%s' "$k" | tr -d '[:space:]'); v=$(printf '%s' "$v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$k" in ''|\#*) continue ;; esac
    v=${v/#\~/$HOME}
    case "$k" in
      roots) roots=$v ;; repos) repos=$v ;; agent) agent=$v ;; prompt_style) prompt_style=$v ;;
      auto_land) auto_land=$v ;;
      auto_next_slice) auto_next_slice=$v ;; notify) notify=$v ;; timeout_min) timeout_min=$v ;;
      *) echo "warning: unknown config key '$k' in $CONFIG" >&2 ;;
    esac
  done < "$CONFIG"
fi

# Known headless agent CLIs: "<binary>|<headless command>|<prompt style>". No preference is
# implied by the order; set agent= (and prompt_style=) in the config to choose explicitly.
#   slash = "/<skill> <args>" (hosts that invoke skills as slash commands, including skills
#           marked user-only, which a plain-language request can't trigger)
#   plain = "Use the <skill> skill. <args>"
AGENTS_KNOWN="codex|codex exec|plain
claude|claude -p|slash
gemini|gemini -p|plain
cursor-agent|cursor-agent -p|plain
opencode|opencode run|plain
qwen|qwen -p|plain"
if [ -z "$agent" ]; then
  found=$(while IFS='|' read -r bin _cmd _style; do
             if command -v "$bin" >/dev/null; then echo "$bin"; fi
           done <<< "$AGENTS_KNOWN")
  if [ "$(printf '%s' "$found" | grep -c .)" -eq 1 ]; then
    agent=$(awk -F'|' -v b="$found" '$1 == b {print $2}' <<< "$AGENTS_KNOWN")
  elif [ -n "$found" ] && [ "$MODE" = dispatch ]; then
    echo "error: several agent CLIs found ($(printf '%s' "$found" | paste -sd, -)); set agent= in $CONFIG" >&2; exit 1
  fi
fi
if [ -z "$prompt_style" ] && [ -n "$agent" ]; then
  prompt_style=$(awk -F'|' -v b="${agent%% *}" '$1 == b {print $3}' <<< "$AGENTS_KNOWN")
  prompt_style=${prompt_style:-plain}
fi
prompt_for() {  # prompt_for <skill> [args...]
  local skill=$1; shift
  case "$prompt_style" in
    slash) printf '/%s %s' "$skill" "$*" ;;
    *)     printf 'Use the %s skill. %s' "$skill" "$*" ;;
  esac
}

# ── state and lock ────────────────────────────────────────────────────────────
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/pr-runner
mkdir -p "$CACHE/logs"
STATE_FILE="$CACHE/state.json"; [ -s "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
LOCK="$CACHE/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ $(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) )) -gt 21600 ]; then
    rm -rf "$LOCK"; mkdir "$LOCK"
  else
    echo "SWEEP: skipped (another sweep is running)"; exit 0
  fi
fi
trap 'rm -rf "$LOCK"' EXIT

# ── local checkouts: owner/repo → main checkout path ──────────────────────────
declare -A CHECKOUT=()
IFS=',' read -r -a ROOTS <<< "$roots"
for root in "${ROOTS[@]}"; do
  root=$(printf '%s' "$root" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -d "$root" ] || continue
  while IFS= read -r gitdir; do
    dir=$(dirname "$gitdir")
    git -C "$dir" remote -v 2>/dev/null | awk '{print $2}' | sort -u | while read -r url; do
      slug=$(printf '%s' "$url" | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//')
      [ -n "$slug" ] && printf '%s\t%s\n' "$slug" "$dir"
    done
  done < <(find "$root" -maxdepth 3 -type d -name .git -prune 2>/dev/null)
done > "$CACHE/checkouts.tsv"
while IFS=$'\t' read -r slug dir; do
  [ -n "${CHECKOUT[$slug]:-}" ] || CHECKOUT[$slug]=$dir
done < "$CACHE/checkouts.tsv"

worktree_for() {  # worktree_for <main checkout> <branch> → path or empty
  git -C "$1" worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$2" '
    /^worktree /{ p=substr($0,10) } $0 == "branch " b { print p; exit }'
}
busy() {  # busy <worktree> → 0 when another skill holds a fresh lock there
  local gd; gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  local s started stale
  for s in execute-plan pr-launch pr-shepherd pr-land; do
    if [ -d "$gd/$s/lock" ]; then
      started=$(cat "$gd/$s/lock/started" 2>/dev/null || stat -c %Y "$gd/$s/lock")
      stale=10800; [ "$s" = execute-plan ] && stale=21600
      [ $(( $(date +%s) - started )) -lt "$stale" ] && { echo "$s"; return 0; }
    fi
  done
  return 1
}
allowed_repo() {
  [ -z "$repos" ] && return 0
  case ",${repos// /}," in *",$1,"*) return 0 ;; esac
  return 1
}

# ── decide ────────────────────────────────────────────────────────────────────
PRS=$("$FETCH")
DISPATCHED=0; BLOCKED=0
NOTIFY_CMD=""; [ "$notify" = true ] && command -v notify-send >/dev/null && NOTIFY_CMD=notify-send

line() { printf '%-40s %-12s %s\n' "$1" "$2" "$3"; }

while IFS= read -r pr; do
  repo=$(jq -r .repo <<<"$pr"); n=$(jq -r .number <<<"$pr"); id="$repo#$n"
  [ -z "$ONLY" ] || [ "$ONLY" = "$id" ] || continue
  head=$(jq -r .head <<<"$pr"); status=$(jq -r .status <<<"$pr"); ci=$(jq -r .ci <<<"$pr")
  draft=$(jq -r .isDraft <<<"$pr"); action=$(jq -r .action <<<"$pr")
  fingerprint=$(jq -r '[.lastCommitAt, .updatedAt] | join("|")' <<<"$pr")

  allowed_repo "$repo" || { line "$id" skip "repo not in allowlist"; continue; }

  skill=""
  if [ "$draft" = true ]; then
    line "$id" skip "draft"; continue
  elif [ "$status" = Conflicted ] || [ "$status" = "Changes requested" ] || [ "$status" = "Feedback received" ] \
       || [ "$ci" = FAILURE ] || [ "$ci" = ERROR ]; then
    skill=pr-shepherd
  elif [ "$status" = Approved ] && [ "$ci" != PENDING ] && [ "$ci" != EXPECTED ]; then
    if [ "$auto_land" = true ]; then skill=pr-land
    else line "$id" skip "approved; auto_land is off"; continue; fi
  else
    line "$id" skip "$action"; continue
  fi

  main=${CHECKOUT[$repo]:-}
  [ -n "$main" ] || { line "$id" skip "no local checkout under $roots"; continue; }
  wt=$(worktree_for "$main" "$head")
  [ -n "$wt" ] || { line "$id" skip "no local worktree for $head"; continue; }
  if [ -n "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    line "$id" skip "worktree has uncommitted changes"; continue
  fi
  if holder=$(busy "$wt"); then line "$id" skip "$holder is running there"; continue; fi

  last=$(jq -r --arg id "$id" '.[$id] // {} | "\(.result // "")|\(.fingerprint // "")"' "$STATE_FILE")
  if [ "${last%%|*}" = BLOCKED ] && [ "${last#*|}" = "$fingerprint" ]; then
    line "$id" skip "still blocked, nothing new since"; continue
  fi

  if [ "$MODE" = dry-run ]; then line "$id" "$skill" "would run in $wt"; continue; fi
  [ -n "$agent" ] || { echo "error: no agent CLI found; set agent= in $CONFIG" >&2; exit 1; }

  log="$CACHE/logs/$(printf '%s' "$id" | tr '/#' '__')-$(date +%Y%m%dT%H%M%S)-$skill.log"
  ( cd "$wt" && timeout "${timeout_min}m" $agent "$(prompt_for "$skill")" ) > "$log" 2>&1 || true
  DISPATCHED=$((DISPATCHED + 1))
  result=$(grep -E '^RESULT: ' "$log" | tail -1 || true); result=${result:-"RESULT: BLOCKED (no RESULT line; see log)"}
  kind=$(printf '%s' "$result" | awk '{print $2}')
  line "$id" "$skill" "$result  ($log)"

  # refresh the fingerprint after the run so our own comments don't look like news
  fp_after=$(gh pr view "$n" -R "$repo" --json updatedAt,commits -q '[.commits[-1].commit.committedDate, .updatedAt] | join("|")' 2>/dev/null || echo "$fingerprint")
  tmp=$(mktemp); jq --arg id "$id" --arg r "$kind" --arg f "$fp_after" --arg at "$(date -u +%FT%TZ)" \
    '.[$id] = {result:$r, fingerprint:$f, at:$at}' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

  if [ "$kind" = BLOCKED ]; then
    BLOCKED=$((BLOCKED + 1))
    [ -n "$NOTIFY_CMD" ] && $NOTIFY_CMD "pr-runner: $id blocked" "${result#RESULT: BLOCKED }" || true
  fi

  # next plan slice after a landed PR
  if [ "$skill" = pr-land ] && [ "$kind" = DONE ] && [ "$auto_next_slice" = true ]; then
    next=$(grep -E '^NEXT: ' "$log" | tail -1 || true)
    if [ -n "$next" ] && [ "$next" != "NEXT: none" ]; then
      plan=$(printf '%s' "$next" | sed -E 's/^NEXT: (.*) PR [^ ]+$/\1/')
      nlog="$CACHE/logs/$(printf '%s' "$id" | tr '/#' '__')-$(date +%Y%m%dT%H%M%S)-execute-plan.log"
      ( cd "$main" && timeout "${timeout_min}m" $agent "$(prompt_for execute-plan --unattended "\"$plan\"")" ) > "$nlog" 2>&1 || true
      DISPATCHED=$((DISPATCHED + 1))
      nres=$(grep -E '^RESULT: ' "$nlog" | tail -1 || true); nres=${nres:-"RESULT: BLOCKED (no RESULT line; see log)"}
      line "$id" "next-slice" "$nres  ($nlog)"
      case "$nres" in "RESULT: BLOCKED"*)
        BLOCKED=$((BLOCKED + 1))
        [ -n "$NOTIFY_CMD" ] && $NOTIFY_CMD "pr-runner: next slice blocked" "$plan: ${nres#RESULT: BLOCKED }" || true ;;
      esac
    fi
  fi
done < <(jq -c '.prs[]' <<<"$PRS")

echo "SWEEP: $DISPATCHED dispatched, $BLOCKED blocked ($MODE)"

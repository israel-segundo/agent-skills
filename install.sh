#!/usr/bin/env bash
# Fan out the skills in this directory to every agent host installed on this machine.
#
# Canonical copy lives here; each host gets a symlink (or a copy with --copy, for hosts
# whose skill discovery doesn't follow symlinks — Gemini CLI and Cursor's CLI have both
# had that bug). Idempotent: re-run after adding a skill, editing one, or installing a
# new host.
#
#   ./install.sh                 # symlink into every host dir that exists
#   ./install.sh --copy          # copy instead (use when a host won't follow symlinks)
#   ./install.sh --dry-run       # show what would happen
#   ./install.sh --host ~/.foo/skills   # also target an extra path
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE=link
DRY=
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --copy)    MODE=copy ;;
    --dry-run) DRY=1 ;;
    --host)    shift; EXTRA+=("$1") ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *)         echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# Host skill dirs. `.agents/skills` is the emerging cross-tool convention (Codex CLI and
# Gemini CLI both read it); the per-tool paths are what each host reads natively today.
HOSTS=(
  "$HOME/.claude/skills"      # Claude Code
  "$HOME/.agents/skills"      # shared convention: Codex CLI, Gemini CLI, others
  "$HOME/.gemini/skills"      # Gemini CLI native
  "$HOME/.codex/skills"       # Codex CLI native
  "$HOME/.cursor/skills"      # Cursor
  "$HOME/.qwen/skills"        # Qwen Code
  "${EXTRA[@]+"${EXTRA[@]}"}"
)

# A host counts as installed if its config dir exists, so we don't litter ~ with dirs for
# tools that aren't here. `.agents` is created when any other host is present, since it is
# the shared path rather than one tool's home.
host_installed() {
  local skills_dir="$1" parent
  parent="$(dirname "$skills_dir")"
  [ -d "$parent" ] && return 0
  case "$skills_dir" in "$HOME/.agents/skills") return 0 ;; esac
  return 1
}

# Skills = immediate subdirectories containing a SKILL.md.
mapfile -t SKILLS < <(find "$SRC" -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | sort)
[ ${#SKILLS[@]} -gt 0 ] || { echo "no skills found in $SRC" >&2; exit 1; }

echo "source:  $SRC"
echo "skills:  $(printf '%s ' "${SKILLS[@]##*/}")"
echo "mode:    $MODE${DRY:+ (dry run)}"
echo

run() { if [ -n "$DRY" ]; then echo "    would: $*"; else "$@"; fi; }

for host in "${HOSTS[@]}"; do
  if ! host_installed "$host"; then
    echo "skip  $host  (host not installed)"
    continue
  fi
  echo "host  $host"
  run mkdir -p "$host"
  for skill in "${SKILLS[@]}"; do
    name="${skill##*/}"
    dest="$host/$name"
    # Replace whatever is there (stale symlink, old copy) so re-runs converge. Refuse to
    # clobber a real directory that isn't ours unless it looks like a previous install.
    if [ -e "$dest" ] && [ ! -L "$dest" ] && [ ! -f "$dest/SKILL.md" ]; then
      echo "    !! $name exists and is not a skill dir — leaving it alone"
      continue
    fi
    run rm -rf "$dest"
    if [ "$MODE" = link ]; then
      run ln -s "$skill" "$dest"
      echo "    link $name"
    else
      run cp -R "$skill" "$dest"
      echo "    copy $name"
    fi
  done
done

echo
echo "Done. Verify a host can actually read through the link:"
echo "  head -3 \"\$HOME/.claude/skills/${SKILLS[0]##*/}/SKILL.md\""
echo "If a host lists no skills, re-run with --copy for that host: ./install.sh --copy --host <dir>"

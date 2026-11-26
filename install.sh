#!/usr/bin/env bash
# Fan out the skills in this directory to every agent host installed on this machine.
#
# Canonical copy lives here; each host gets a symlink (or a copy with --copy, for hosts
# whose skill discovery doesn't follow symlinks — Gemini CLI and Cursor's CLI have both
# had that bug). Idempotent: re-run after adding a skill, editing one, deleting one, or
# installing a new host.
#
# Deleted skills are pruned from every host: a symlink that points into this repo at a
# directory that is no longer a skill, and a copy carrying this repo's install marker for a
# skill that no longer exists. Nothing else in a host dir is touched. Copies made before the
# marker existed can't be told apart from your own skills, so they are left alone.
#
#   ./install.sh                 # symlink into every host dir that exists
#   ./install.sh --cursor        # Cursor global only (~/.cursor/skills, ~/.agents/skills)
#   ./install.sh --copy          # copy instead (use when a host won't follow symlinks)
#   ./install.sh --dry-run       # show what would happen
#   ./install.sh --host ~/.foo/skills   # also target an extra path
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE=link
DRY=
CURSOR_ONLY=
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --copy)    MODE=copy ;;
    --dry-run) DRY=1 ;;
    --cursor)  CURSOR_ONLY=1 ;;
    --host)    shift; EXTRA+=("$1") ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *)         echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# Cursor global skill dirs. Cursor reads both natively; ~/.agents/skills is the
# vendor-neutral path, ~/.cursor/skills is Cursor's own home-dir convention.
CURSOR_HOSTS=(
  "$HOME/.cursor/skills"
  "$HOME/.agents/skills"
)

# Host skill dirs. `.agents/skills` is the emerging cross-tool convention (Codex CLI and
# Gemini CLI both read it); the per-tool paths are what each host reads natively today.
ALL_HOSTS=(
  "$HOME/.claude/skills"      # Claude Code
  "$HOME/.agents/skills"      # shared convention: Codex CLI, Gemini CLI, Cursor, others
  "$HOME/.gemini/skills"      # Gemini CLI native
  "$HOME/.codex/skills"       # Codex CLI native
  "$HOME/.cursor/skills"      # Cursor native (global, all projects on this machine)
  "$HOME/.qwen/skills"        # Qwen Code
  "${EXTRA[@]+"${EXTRA[@]}"}"
)

if [ -n "$CURSOR_ONLY" ]; then
  HOSTS=("${CURSOR_HOSTS[@]}" "${EXTRA[@]+"${EXTRA[@]}"}")
else
  HOSTS=("${ALL_HOSTS[@]}")
fi

# A host counts as installed if its config dir exists, so we don't litter ~ with dirs for
# tools that aren't here. `.agents` is created when any other host is present, since it is
# the shared path rather than one tool's home. With --cursor, always install into Cursor's
# global dirs — mkdir -p is harmless even before the first Cursor launch.
host_installed() {
  local skills_dir="$1" parent
  if [ -n "$CURSOR_ONLY" ]; then
    case "$skills_dir" in
      "$HOME/.cursor/skills"|"$HOME/.agents/skills") return 0 ;;
    esac
  fi
  parent="$(dirname "$skills_dir")"
  [ -d "$parent" ] && return 0
  case "$skills_dir" in
    "$HOME/.agents/skills") return 0 ;;
    "$HOME/.cursor/skills")
      # Cursor is present when ~/.cursor exists (config, projects, or built-in skills-cursor).
      [ -d "$HOME/.cursor" ] && return 0
      ;;
  esac
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

# Written into every copy (--copy) so a later run can tell our copies from anything else.
MARKER=".installed-by-agent-skills"

# Remove what this repo installed into $1 for skills that no longer exist here.
prune_host() {
  local host="$1" entry name target
  for entry in "$host"/* "$host"/.[!.]*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name="${entry##*/}"
    if [ -L "$entry" ]; then
      target="$(readlink "$entry")"
      case "$target" in "$SRC"/*) ;; *) continue ;; esac   # not ours
      [ -f "$target/SKILL.md" ] && continue                 # still a skill
      run rm -f "$entry"
      echo "    prune $name  (link to a skill deleted from this repo)"
    elif [ -d "$entry" ] && [ -f "$entry/$MARKER" ] && [ "$(cat "$entry/$MARKER")" = "$SRC" ]; then
      [ -f "$SRC/$name/SKILL.md" ] && continue
      run rm -rf "$entry"
      echo "    prune $name  (copy of a skill deleted from this repo)"
    fi
  done
}

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
      if [ -n "$DRY" ]; then echo "    would: write $dest/$MARKER"; else printf '%s' "$SRC" > "$dest/$MARKER"; fi
      echo "    copy $name"
    fi
  done
  prune_host "$host"
done

echo
echo "Done. Verify a host can actually read through the link:"
if [ -n "$CURSOR_ONLY" ]; then
  echo "  head -3 \"\$HOME/.cursor/skills/${SKILLS[0]##*/}/SKILL.md\""
else
  echo "  head -3 \"\$HOME/.claude/skills/${SKILLS[0]##*/}/SKILL.md\""
  echo "  head -3 \"\$HOME/.cursor/skills/${SKILLS[0]##*/}/SKILL.md\"   # Cursor global"
fi
echo "If a host lists no skills, re-run with --copy for that host: ./install.sh --copy --host <dir>"
echo "Cursor also reads ~/.claude/skills/ for compatibility — if you use Claude Code too,"
echo "the same skill may appear twice in Cursor until you pick one directory per skill."

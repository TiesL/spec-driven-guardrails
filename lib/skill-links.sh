#!/usr/bin/env bash
# lib/skill-links.sh — Create-only repair of missing skill links (#505, A45).
#
# Source, don't execute. This is the one place in the SessionStart hook
# path that mutates a project: pending-changes.sh otherwise only reports.
# It never overwrites, repoints or removes any path; replacing and cleaning
# up stays adopt.sh's job (skill_symlink_update there replaces links, which
# is exactly what this module must not do, so the code is not shared).
#
# Interface: skill_links_create_missing <workflow_dir> <project_dir>
#   stdout: one "Created skill link: ..." line per link, then once the
#           next-session line. Nothing when nothing was created.
#   global: SKILL_LINKS_NOT_CREATED = comma-separated names that are missing
#           (no -e) and were not created; empty when none.
#   always returns 0, never writes to stderr (fail open).
#
# A link is created for a skill only when all of this holds: the project is
# adopted into this checkout (its .claude/settings.json is a symlink whose
# grandparent directory is the checkout, the same derivation the hook
# command uses); .claude/skills is absent or a real directory; nothing
# exists (-e or -L) at .claude/skills/<name>; and git says
# .claude/skills/<name> is ignored. The ignore test is per name, never on
# the bare directory: the managed entry ".claude/skills/" is directory-only
# and does not match a directory that does not exist yet.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no namerefs.

SKILL_LINKS_NOT_CREATED=""

skill_links_create_missing() {
  local workflow_dir="$1" project_dir="$2"
  local skills_dir="$project_dir/.claude/skills"
  local skill_path name missing="" created=0 can_create=1 target dest wf_real

  SKILL_LINKS_NOT_CREATED=""

  # 1. Adopted into this checkout.
  target="$(readlink "$project_dir/.claude/settings.json" 2>/dev/null)"
  if [ -z "$target" ]; then
    can_create=0
  else
    case "$target" in
      /*) ;;
      *) target="$project_dir/.claude/$target" ;;
    esac
    dest="$(cd "$(dirname "$(dirname "$target")")" 2>/dev/null && pwd -P)"
    wf_real="$(cd "$workflow_dir" 2>/dev/null && pwd -P)"
    if [ -z "$dest" ] || [ -z "$wf_real" ] || [ "$dest" != "$wf_real" ]; then
      can_create=0
    fi
  fi

  # 2. .claude/skills is absent or a real directory.
  if [ "$can_create" -eq 1 ]; then
    if [ -L "$skills_dir" ]; then
      can_create=0
    elif [ -e "$skills_dir" ] && [ ! -d "$skills_dir" ]; then
      can_create=0
    fi
  fi

  for skill_path in "$workflow_dir"/skills/*/; do
    [ -d "$skill_path" ] || continue
    name="$(basename "$skill_path")"
    [ ! -e "$skills_dir/$name" ] || continue

    # 3-5. Only a path with nothing at all on it, that git ignores.
    if [ "$can_create" -eq 1 ] && [ ! -L "$skills_dir/$name" ] \
      && git -C "$project_dir" check-ignore -q -- ".claude/skills/$name" 2>/dev/null \
      && mkdir -p "$skills_dir" 2>/dev/null \
      && ln -s "$workflow_dir/skills/$name" "$skills_dir/$name" 2>/dev/null; then
      echo "Created skill link: .claude/skills/$name -> $workflow_dir/skills/$name"
      created=1
      continue
    fi

    # Comma-separated: a skill name with a space in it would otherwise be
    # indistinguishable from multiple separate names.
    if [ -n "$missing" ]; then
      missing="$missing, $name"
    else
      missing="$name"
    fi
  done

  if [ "$created" -eq 1 ]; then
    echo "New skill links may not be visible to this session; they are available from the next session start."
  fi
  SKILL_LINKS_NOT_CREATED="$missing"
  return 0
}

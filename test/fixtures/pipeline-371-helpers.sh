#!/usr/bin/env bash
# test/fixtures/pipeline-371-helpers.sh — shared fixture helpers for the
# #371 scenarios (S176-S185). Source after test/lib.sh. Not a test case.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.
# Hermetic: no network, no timing. The fake `gh` below is data-driven
# (JSON files + real jq), so it does not depend on the exact `gh api`
# call shape or --jq expression an implementation chooses.

# write_adoption <file> <id> <answer> [<id> <answer> ...]
# A WORKFLOW-ADOPTION.md with the given rows (Answer is the second column,
# like the real file).
write_adoption() {
  local file="$1"
  shift
  {
    echo "# Adoption of shared workflow changes"
    echo
    echo "| Change | Answer | Date | Notes |"
    echo "|---|---|---|---|"
    while [ $# -ge 2 ]; do
      printf '| %s | %s | 2026-10-01 | fixture |\n' "$1" "$2"
      shift 2
    done
  } > "$file"
}

# lines_of <file> <min-length>: the file's lines of at least that many
# characters, one per line (short lines like "---" or "" are noise when
# asking "is this file's text in that output").
lines_of() {
  awk -v n="$2" 'length($0) >= n' "$1"
}

# output_has_all_lines <file> <text>: every line (>= 8 chars) of the file
# appears somewhere in the text, as a substring.
output_has_all_lines() {
  local file="$1" text="$2" line
  while IFS= read -r line; do
    case "$text" in
      *"$line"*) ;;
      *) return 1 ;;
    esac
  done < <(lines_of "$file" 8)
  return 0
}

# output_has_any_line <file> <text>: at least one line (>= 25 chars) of the
# file appears in the text.
output_has_any_line() {
  local file="$1" text="$2" line
  while IFS= read -r line; do
    case "$text" in
      *"$line"*) return 0 ;;
    esac
  done < <(lines_of "$file" 25)
  return 1
}

# session_start_commands <settings.json>: every SessionStart hook command,
# NUL-free, one per line (the commands themselves are single-line).
session_start_commands() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hooks.SessionStart[].hooks[].command' "$1"
  else
    python3 -c '
import json, sys
for group in json.load(open(sys.argv[1]))["hooks"]["SessionStart"]:
    for h in group["hooks"]:
        print(h["command"])
' "$1"
  fi
}

# run_session_start <project>: runs every SessionStart command of the
# project's .claude/settings.json as Claude Code would (CLAUDE_PROJECT_DIR
# set, one shell per command) and prints their combined stdout.
run_session_start() {
  local project="$1" cmd
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    CLAUDE_PROJECT_DIR="$project" bash -c "$cmd" 2>/dev/null
  done < <(session_start_commands "$project/.claude/settings.json")
}

# --- Data-driven fake `gh` for the model-record gate -----------------------

# mr <Stage>: one model-record marker for a stage (Review on a different
# model than Implementation, so #244's same-model finding stays out of the way).
mr() {
  local model=sonnet
  [ "$1" = Review ] && model=opus
  printf '<!-- model-record: stage=%s model="%s" effort="high" -->' "$1" "$model"
}

# json_comments <outfile> <body> [<body> ...]: a JSON array of comment
# objects, one per body, as the REST API returns them.
json_comments() {
  local out="$1"
  shift
  jq -n '$ARGS.positional | map({body: .})' --args "$@" > "$out"
}

# json_pr <outfile> <title> <body>
json_pr() {
  jq -n --arg t "$2" --arg b "$3" '{title: $t, body: $b}' > "$1"
}

# fake_gh_rest <data-dir>: a fake `gh` serving REST `gh api` calls from
# <data-dir>:
#   pulls/N            -> pr-N.json        (object: title, body)
#   pulls/N/reviews    -> reviews-N.json   (array of {body})
#   issues/N/comments  -> comments-N.json  (array of {body})
# A missing file, or FAKE_GH_FAIL=1, is a failed call (exit 1, message on
# stderr), like no network. A --jq expression is applied with real jq
# (raw output, as gh does). Echoes the bin directory; put it on PATH and
# export FAKE_GH_DATA=<data-dir>.
fake_gh_rest() {
  local bin="$SANDBOX/fakegh-rest"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'GHEOF'
#!/usr/bin/env bash
[ "${FAKE_GH_FAIL:-}" = "1" ] && { echo "gh: could not connect" >&2; exit 1; }
[ "${1:-}" = "api" ] || exit 1
ep="$2"
shift 2
expr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq|-q) expr="$2"; shift 2 ;;
    *) shift ;;
  esac
done
ep="${ep#repos/}"
ep="${ep#*/*/}"
case "$ep" in
  pulls/*/reviews) f="$FAKE_GH_DATA/reviews-$(echo "$ep" | sed 's#pulls/\([0-9]*\)/reviews#\1#').json" ;;
  pulls/*)         f="$FAKE_GH_DATA/pr-${ep#pulls/}.json" ;;
  issues/*/comments) f="$FAKE_GH_DATA/comments-$(echo "$ep" | sed 's#issues/\([0-9]*\)/comments#\1#').json" ;;
  *) f="" ;;
esac
if [ -z "$f" ] || [ ! -f "$f" ]; then
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi
if [ -n "$expr" ]; then jq -r "$expr" "$f"; else cat "$f"; fi
GHEOF
  chmod +x "$bin/gh"
  echo "$bin"
}

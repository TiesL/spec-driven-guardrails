#!/usr/bin/env bash
# check-no-sigpipe-race.sh — Guards against reintroducing the SIGPIPE/
# pipefail race issue #218 found and fixed (`<producer> | grep -q ...`
# under `set -o pipefail`): grep -q exits as soon as it matches, which can
# SIGPIPE the still-writing producer before it finishes, and pipefail then
# reports that SIGPIPE exit as the pipeline's failure instead of grep's
# real, successful one — a value that genuinely matches gets wrongly
# reported as not found. Rare at low concurrency, much likelier under CPU
# contention (this is exactly how #218 was found: parallelizing the test
# suite in #216/#217 made it land repeatedly).
#
# Any producer, not just printf/echo, and a pipe split across a
# backslash-continued line: the first version of this check (PR #226) only
# matched printf/echo on one physical line, and its own pre-merge-review
# found a live, undetected instance the same PR was supposed to eradicate
# — `pending_ids "$project" | grep -qx "..."` in
# test/cases/r8_retirement_stays_grepable.sh, where pending_ids ends in
# `sort`. The race is structural to "anything piped into an early-exiting
# grep -q under pipefail", not specific to printf/echo or to one line.
#
# The fix is always the same shape: a `<<<` here-string instead of a piped
# producer — no separate writer process, no SIGPIPE to race. AC3 of #218
# asked for a decision on an ongoing check versus a one-time cleanup; this
# is that check, since #218's own description called the pattern "easy to
# reintroduce by habit" and this repo prefers a mechanism over relying on
# that habit not slipping (the same reasoning behind every other guard in
# this repo).
#
# Called from the project's own `check`:
#
#   ./check-no-sigpipe-race.sh .
#
# Deliberately offline: a local scan, no gh, no network — same class of
# check as check-no-dutch.sh, gated on this script's own presence in the
# target the same way. python3 does the matching (already a required
# dependency elsewhere in this repo, e.g. check-traceability.sh,
# hooks/git-guardrails): joining a backslash-continued pipe across lines
# while still reporting the correct starting line number is exactly the
# kind of logic that turns fragile chained sed/grep into something
# unreadable.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

target="${1:-.}"
own_name="$(basename "${BASH_SOURCE[0]}")"

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-no-sigpipe-race: python3 is missing — check skipped." >&2
  exit 0
fi

# Every *.sh file plus extensionless bash/sh-shebanged scripts (the same
# set `check`'s own bash -n step scans), excluding this script itself (its
# own header comment would otherwise match) and .git. Collected to a temp
# file first, not inline inside a nested command substitution — bash 3.2
# (macOS's stock /bin/bash) has been unreliable with this exact case/head
# pattern once nested two levels deep.
script_list="$(mktemp)" || {
  echo "check-no-sigpipe-race: couldn't create a temp file — check aborted" >&2
  exit 1
}
trap 'rm -f "$script_list"' EXIT

find "$target" -type f -name '*.sh' -not -path '*/.git/*' -not -name "$own_name" \
  > "$script_list"

find "$target" -type f -not -name '*.sh' -not -name 'check' -not -path '*/.git/*' \
  | while IFS= read -r candidate; do
      [ -r "$candidate" ] || continue
      case "$(head -c 2 "$candidate" 2>/dev/null)" in
        '#!')
          case "$(head -n 1 "$candidate" 2>/dev/null)" in
            *bash*|*'/sh'*|*'env sh'*) echo "$candidate" ;;
          esac ;;
      esac
    done >> "$script_list"

# One python3 invocation for every file, printing "path:line:content" per
# hit directly — not a per-file subprocess spawn, and not a fragile
# chained sed/grep pipeline for logic (line-joining, "||" vs "|") that
# reads far worse in bash than as real code.
matches="$(sort -u "$script_list" | python3 -c '
import re
import sys

# A genuine pipe, not "||" (boolean or has no producer process — grep
# there reads a named file directly, not stdin) — handled by requiring
# the pipe not be immediately adjacent to another pipe. Flags containing
# q anywhere (not just as the first/only flag: -qx, -qF, -Eq, ...).
pattern = re.compile(r"(?<!\|)\|(?!\|)\s*grep\s+-[a-zA-Z]*q[a-zA-Z]*\b")

for path in sys.stdin.read().splitlines():
    if not path:
        continue
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        continue

    i = 0
    n = len(lines)
    while i < n:
        start = i
        raw = lines[i].rstrip("\n")
        # Comment lines (first non-blank char #) never count, checked on
        # the first physical line of a (possibly continued) logical line
        # — the same rule as documenting the anti-pattern in a comment.
        is_comment = raw.lstrip().startswith("#")
        logical = raw
        # Join a trailing, unescaped backslash continuation onto the next
        # physical line(s), so a pipe split across lines is still seen as
        # one logical line for matching — reported at its starting line.
        while logical.endswith("\\") and not logical.endswith("\\\\") and i + 1 < n:
            i += 1
            logical = logical[:-1] + " " + lines[i].rstrip("\n")
        if not is_comment and pattern.search(logical):
            print(path + ":" + str(start + 1) + ":" + lines[start].rstrip("\n"))
        i += 1
')"

if [ -n "$matches" ]; then
  echo "check-no-sigpipe-race: a producer piped into grep -q found (SIGPIPE/pipefail race, issue #218) — use a <<< here-string instead:" >&2
  printf '%s\n' "$matches" | sed 's/^/  /' >&2
  exit 1
fi

echo "check-no-sigpipe-race: ok"
exit 0

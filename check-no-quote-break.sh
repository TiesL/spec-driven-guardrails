#!/usr/bin/env bash
# check-no-quote-break.sh — Guards against reintroducing the incident found
# while building issue #225 (PR #227): a bash *single-quoted* string
# (`python3 -c '...'`) has no escape mechanism at all — a literal
# apostrophe anywhere inside it (ordinary English prose, e.g. a comment
# reading "PR #227's own pre-merge-review") closes the string right there.
# Everything after that point gets reparsed as bash code, with no error
# until a syntax mismatch surfaces somewhere later in the file, often at a
# completely unrelated line — and since this repo adopts itself,
# hooks/git-guardrails is also this session's own PreToolUse hook, so a
# broken copy of it blocks every Bash tool call in the session, discovered
# only by reading the file blind (no working Bash) until the apostrophe is
# found by hand. See issue #228 and the matching PRD.md Technical debt row.
#
# The fix is always the same: reword the prose to drop the apostrophe (or
# move it out of the single-quoted block entirely, into a bash comment
# above the `python3 -c '` line). This script's job is to catch it before
# it ships, not to fix it — same as every other check- script here.
#
# How it finds a break, without needing a real bash/python parser: every
# `python3 -c '...'` block in this codebase closes on a line whose first
# non-blank character is the closing `'` (`')"`, `' "$arg" <<<...)"`, ...
# — checked across every existing instance before relying on it). Bash
# itself closes a single-quoted string at the *first* `'` it finds after
# the opener, no exceptions — so scanning forward from the opener for the
# first line containing a `'`, and checking whether that quote sits at the
# very start of the line, tells us whether bash's real close point matches
# the block's intended, visually-obvious close point. An apostrophe in
# ordinary prose is never the first character of its line, since it always
# follows a word character ("it's", "#227's") — that's what distinguishes
# an accidental break from the real, intended closer.
#
# Called from the project's own `check`:
#
#   ./check-no-quote-break.sh .
#
# Deliberately offline: a local scan, no gh, no network — same class of
# check as check-no-dutch.sh/check-no-sigpipe-race.sh, gated on this
# script's own presence in the target the same way. python3 does the
# scan (already a required dependency elsewhere in this repo).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

target="${1:-.}"
own_name="$(basename "${BASH_SOURCE[0]}")"

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-no-quote-break: python3 is missing — check skipped." >&2
  exit 0
fi

# Every *.sh file plus extensionless bash/sh-shebanged scripts (the same
# set `check`'s own bash -n step scans), excluding this script itself and
# .git. Collected to a temp file first, not inline inside a nested command
# substitution — bash 3.2 (macOS's stock /bin/bash) has been unreliable
# with this exact case/head pattern once nested two levels deep (found
# while building check-no-sigpipe-race.sh, F22).
script_list="$(mktemp)" || {
  echo "check-no-quote-break: couldn't create a temp file — check aborted" >&2
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

matches="$(sort -u "$script_list" | python3 -c '
import re
import sys

# The opener: a line ending in `python3 -c '"'"'` or `python -c '"'"'`
# (the quote is the last character on the line — anything else is a
# one-liner, out of scope, since a one-liner closes on the same line by
# construction and cannot suffer this bug).
opener = re.compile(r"python3?\s+-c\s+\x27$")

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
        raw = lines[i].rstrip("\n")
        if opener.search(raw):
            # Scan forward for the first line containing a single quote —
            # bash'"'"'s real close point, intended or not.
            j = i + 1
            while j < n and "\x27" not in lines[j]:
                j += 1
            if j < n:
                closer_line = lines[j]
                stripped = closer_line.lstrip()
                if not stripped.startswith("\x27"):
                    print(path + ":" + str(j + 1) + ":" + closer_line.rstrip("\n"))
            i = j
        i += 1
')"

if [ -n "$matches" ]; then
  echo "check-no-quote-break: an apostrophe closes a python3 -c '\''...'\'' block early (SIGPIPE-adjacent incident class, issue #228) — reword to drop the apostrophe, or move it outside the single-quoted block:" >&2
  printf '%s\n' "$matches" | sed 's/^/  /' >&2
  exit 1
fi

echo "check-no-quote-break: ok"
exit 0

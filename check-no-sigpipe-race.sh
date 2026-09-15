#!/usr/bin/env bash
# check-no-sigpipe-race.sh — Guards against reintroducing the SIGPIPE/
# pipefail race issue #218 found and fixed (`printf '%s' "$var" | grep -q
# ...` under `set -o pipefail`): grep -q exits as soon as it matches, which
# can SIGPIPE the still-writing printf before it finishes, and pipefail
# then reports that SIGPIPE exit as the pipeline's failure instead of
# grep's real, successful one — a value that genuinely matches gets
# wrongly reported as not found. Rare at low concurrency, much likelier
# under CPU contention (this is exactly how #218 was found: parallelizing
# the test suite in #216/#217 made it land repeatedly).
#
# The fix is always the same shape: a `<<<` here-string instead of a piped
# printf/echo — no separate writer process, no SIGPIPE to race. AC3 of
# #218 asked for a decision on an ongoing check versus a one-time cleanup;
# this is that check, since #218's own description called the pattern
# "easy to reintroduce by habit" and this repo prefers a mechanism over
# relying on that habit not slipping (the same reasoning behind every
# other guard in this repo).
#
# Called from the project's own `check`:
#
#   ./check-no-sigpipe-race.sh .
#
# Deliberately offline: a local grep, no gh, no network — same class of
# check as check-no-dutch.sh, gated on this script's own presence in the
# target the same way.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

target="${1:-.}"
own_name="$(basename "${BASH_SOURCE[0]}")"

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

matches=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  # A comment mentioning this exact anti-pattern for documentation (as
  # several fixed files now do) must not itself trip the check — excluded
  # by skipping lines whose first non-blank character is #.
  found="$(grep -nE '(printf|echo)[^|]*\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*q' "$file" 2>/dev/null \
    | grep -vE '^[0-9]+:[[:space:]]*#')"
  [ -n "$found" ] || continue
  matches="$matches
$(printf '%s\n' "$found" | sed "s#^#${file}:#")"
done < <(sort -u "$script_list")

matches="$(printf '%s' "$matches" | sed '/^$/d')"

if [ -n "$matches" ]; then
  echo "check-no-sigpipe-race: printf/echo piped into grep -q found (SIGPIPE/pipefail race, issue #218) — use a <<< here-string instead:" >&2
  printf '%s\n' "$matches" | sed 's/^/  /' >&2
  exit 1
fi

echo "check-no-sigpipe-race: ok"
exit 0

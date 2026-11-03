#!/usr/bin/env bash
# pipeline-override.sh — posts the pipeline-override record for a work item,
# so nobody types one (#564, A18, A26). The orchestrator runs it when the
# human has explicitly asked to skip stages (OR34), most often for the named
# short track "abbreviated workflow": --scope skip=Planning --scope skip=Test.
#
# Usage (run from the project's checkout, so gh resolves the project's repo):
#   $SPEC_DRIVEN_GUARDRAILS_DIR/pipeline-override.sh <issue> --scope <scope> [--scope <scope> ...] \
#       --decided-by <name> --reason '<the human'"'"'s words>' [--dry-run]
#
# scope: single-session, or skip=Discovery|Planning|Test|Implementation|Review.
# single-session cannot be combined with skip=, and a scope cannot repeat.
# --decided-by and --reason are required, once each; there is no default and
# no environment fallback. Pass --reason in single quotes: a double-quoted
# shell argument expands $VAR, backticks and ! before this script sees it, and
# the recorded words would then differ from the human's. The script echoes the
# recorded reason on success so that is visible.
#
# Post the record before the work item's first commit or PR open, never after
# the merge guard has reported the missing stages. It goes on the issue as one
# comment (one record line per scope, then one plain-text line). The merge
# gate reads an issue's comments only when the PR title or body names that
# issue with a closing keyword, such as `Closes #<issue>`; without it the
# record is invisible to the gate.
#
# Values are refused, never sanitized: decided-by and reason must be valid
# UTF-8, must not be blank (nothing left but white space, NBSP, other Unicode
# spaces, listed zero-width characters or bidi marks), must not hold `"`, `<`, `>`, a
# control byte (so no multi-line text), a C1 control, U+2028/U+2029 or a bidi
# control, and are at most 100 and 1000 bytes. The bidi controls refused are
# a bidi embedding, override or isolate control (U+202A-U+202E, U+2066-U+2069);
# listed zero-width characters and bidi marks (U+200B, U+200E, U+200F, U+061C, U+FEFF)
# are accepted, as in A33a, so long as some other visible character remains.
# The UTF-8 check is stricter than A33a on purpose: invalid bytes would abort
# the awk in lib/markdown.sh. On a refusal, ask the human for words without
# those characters; do not edit theirs. After building the comment the script reads it back with the gate's
# own reader (lib/model-record.sh) and posts nothing unless every line reads as
# an ok record with exactly the given values.
#
# Not idempotent: running it twice posts a second comment, which is harmless to
# the gate. --dry-run prints the comment body to stdout, posts nothing and
# needs no gh.
#
# Exit codes:
#   0 — posted (gh's stdout, normally the comment URL, is passed through), or
#       --help, or --dry-run
#   1 — the built comment failed the read-back (script and grammar drifted);
#       nothing posted
#   2 — usage or validation refusal; one stderr line names the field; gh not called
#   3 — environment: lib/model-record.sh, lib/markdown.sh or the gh command not found/executable
#   4 — gh ran and failed; its stderr is passed through; nothing recorded
#
# PIPELINE_OVERRIDE_GH names the gh executable (default: gh); it is never
# evaluated as a shell string. The libs are found from this script's real
# directory (a symlink to the script is followed). Bash 3.2-compatible. No eval.

set -uo pipefail

usage_text() {
  cat <<'EOF'
usage: pipeline-override.sh <issue> --scope <scope> [--scope <scope> ...] --decided-by <name> --reason '<their words>' [--dry-run]

Posts the pipeline-override record on issue <issue>: one comment, one record
line per scope. Run it from the project's checkout.
  scope  single-session, or skip=Discovery|Planning|Test|Implementation|Review
         (abbreviated workflow: --scope skip=Planning --scope skip=Test)
Pass --reason in single quotes, so the shell does not expand $VAR, backticks or !.
A value is refused, never edited: ask the human for other words. Refused:
  - ", <, > (a double quote, a less-than or a greater-than sign)
  - a control byte, a tab or a line break
  - a C1 control, or U+2028 / U+2029 (line and paragraph separators)
  - a bidi control: a bidi embedding, override or isolate control
    (U+202A-U+202E, U+2066-U+2069)
  - invalid UTF-8
  - a blank value: empty, or only white space, NBSP (U+00A0), other Unicode
    spaces, listed zero-width characters or bidi marks (U+200B, U+200E, U+200F,
    U+061C, U+FEFF)
  - more than 100 bytes (decided-by) or 1000 bytes (reason)
Also refused: an <issue> that is not a positive integer, any other --scope than
the closed list above, --scope single-session combined with skip=, a repeated --scope,
and a missing or repeated --decided-by or --reason.
Post it before the first commit or PR open of the work item, never after the
merge guard fires. The merge gate reads the record only if the PR title or body names
the issue with a closing keyword, such as Closes #<issue>.
--dry-run prints the comment body and posts nothing.
EOF
}

die() { # <exit> <message>
  echo "pipeline-override: $2" >&2
  exit "$1"
}
refuse() { die 2 "$1"; }

is_flag() { # a value that is one of this script's own flags was swallowed
  case "$1" in --scope | --decided-by | --reason | --dry-run | --help) return 0 ;; esac
  return 1
}

issue="" have_issue=0
decided_by="" have_decided_by=0
reason="" have_reason=0
dry_run=0
scope_n=0
scopes=()

while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      usage_text
      exit 0
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --scope | --decided-by | --reason)
      flag="$1"
      [ $# -ge 2 ] || refuse "$flag needs a value."
      if is_flag "$2"; then refuse "$flag needs a value, but the next argument is the flag $2."; fi
      case "$flag" in
        --scope)
          scopes[scope_n]="$2"
          scope_n=$((scope_n + 1))
          ;;
        --decided-by)
          [ "$have_decided_by" = 0 ] || refuse "--decided-by given more than once."
          decided_by="$2" have_decided_by=1
          ;;
        --reason)
          [ "$have_reason" = 0 ] || refuse "--reason given more than once."
          reason="$2" have_reason=1
          ;;
      esac
      shift 2
      ;;
    --*)
      first_line="${1%%$'\n'*}"
      refuse "unknown flag '$first_line' (see --help)."
      ;;
    *)
      first_line="${1%%$'\n'*}"
      [ "$have_issue" = 0 ] || refuse "unexpected extra argument '$first_line'; only one <issue> is taken."
      issue="$1" have_issue=1
      shift
      ;;
  esac
done

[ "$have_issue" = 1 ] || refuse "<issue> is required (a positive integer)."
case "$issue" in
  '' | *[!0-9]* | 0*) refuse "<issue> must be a positive integer without leading zeros." ;;
esac
[ "$scope_n" -gt 0 ] || refuse "--scope is required (at least once)."
[ "$have_decided_by" = 1 ] || refuse "--decided-by is required; there is no default."
[ "$have_reason" = 1 ] || refuse "--reason is required; there is no default."

# BEGIN field-checks
# hex_of <value>: the value's bytes as " 41 42 " (space-separated lower-case
# hex), so every byte class below is matched without a locale.
hex_of() { printf ' %s ' "$(printf '%s' "$1" | od -An -v -tx1 | tr -s ' \n' '  ' | sed 's/^ //; s/ $//')"; }

# UTF8_AWK reads the hex string and prints invalid (bad UTF-8: bad lead or
# continuation byte, overlong, surrogate, above U+10FFFF), blank (every
# character is white space, an accepted invisible, or a Unicode space), or ok.
# No strtonum, no locale (bash 3.2 and BSD awk).
# shellcheck disable=SC2016 # an awk program, not shell
UTF8_AWK='
function hv(t,   a, b) { a = index("0123456789abcdef", substr(t, 1, 1)) - 1; b = index("0123456789abcdef", substr(t, 2, 1)) - 1; return a * 16 + b }
{
  n = split($0, tk, " "); blank = 1; i = 1
  while (i <= n) {
    b = hv(tk[i]); need = 0; lo = 128; hi = 191
    if (b < 128) need = 0
    else if (b >= 194 && b <= 223) need = 1
    else if (b == 224) { need = 2; lo = 160 }
    else if (b == 237) { need = 2; hi = 159 }
    else if (b >= 225 && b <= 239) need = 2
    else if (b == 240) { need = 3; lo = 144 }
    else if (b == 244) { need = 3; hi = 143 }
    else if (b >= 241 && b <= 243) need = 3
    else { print "invalid"; exit }
    ch = tk[i]
    for (k = 1; k <= need; k++) {
      if (i + k > n) { print "invalid"; exit }
      c = hv(tk[i + k])
      if (c < (k == 1 ? lo : 128) || c > (k == 1 ? hi : 191)) { print "invalid"; exit }
      ch = ch tk[i + k]
    }
    i += need + 1
    if (!(ch == "20" || ch == "c2a0" || ch == "e19a80" || ch == "e280af" || ch == "e2819f" || ch == "e38080" || ch == "d89c" || ch == "efbbbf" || (ch >= "e28080" && ch <= "e2808f"))) blank = 0
  }
  print (blank ? "blank" : "ok")
}'

# check_text <field> <value> <max-bytes>
check_text() {
  local field="$1" v="$2" max="$3" hex bytes kind
  case "${v// /}" in '') refuse "$field must not be empty or blank." ;; esac
  hex="$(hex_of "$v")"
  kind="$(printf '%s' "$hex" | awk "$UTF8_AWK")"
  case "$kind" in
    invalid) refuse "$field is not valid UTF-8; ask the human for words in valid UTF-8 and do not edit theirs." ;;
    blank) refuse "$field must not be empty or blank (only white space, NBSP, Unicode spaces, listed zero-width characters or bidi marks)." ;;
  esac
  case "$hex" in
    *' 22 '* | *' 3c '* | *' 3e '*) refuse "$field must not contain \", < or > (the record grammar cannot hold them); ask the human for words without them and do not edit theirs." ;;
    *' '[01][0-9a-f]' '* | *' 7f '*) refuse "$field must not contain a control byte, a tab or a line break; ask the human for single-line words and do not edit theirs." ;;
    *' c2 '[89]?' '* | *' e2 80 a8 '* | *' e2 80 a9 '* | *' e2 80 a'[a-e]' '* | *' e2 81 a'[6-9]' '*)
      refuse "$field must not contain a C1 control, a line or paragraph separator or a bidi control (a bidi embedding, override or isolate control (U+202A-U+202E, U+2066-U+2069)); ask the human for other words and do not edit theirs."
      ;;
  esac
  bytes="$(printf '%s' "$v" | wc -c | tr -d ' ')"
  [ "$bytes" -le "$max" ] || refuse "$field is $bytes bytes, more than the $max allowed (it is refused, never truncated)."
}
check_text --decided-by "$decided_by" 100
check_text --reason "$reason" 1000

i=0 have_single=0 have_skip=0
while [ "$i" -lt "$scope_n" ]; do
  s="${scopes[$i]}"
  case "$s" in
    single-session) have_single=1 ;;
    skip=Discovery | skip=Planning | skip=Test | skip=Implementation | skip=Review) have_skip=1 ;;
    *) refuse "--scope must be single-session or skip=Discovery|Planning|Test|Implementation|Review." ;;
  esac
  j=0
  while [ "$j" -lt "$i" ]; do
    [ "${scopes[$j]}" != "$s" ] || refuse "--scope $s given more than once."
    j=$((j + 1))
  done
  i=$((i + 1))
done
if [ "$have_single" = 1 ] && [ "$have_skip" = 1 ]; then
  refuse "--scope single-session already waives every stage; do not combine it with skip=."
fi
# END field-checks

# Follow a symlinked script to its real file first (pwd -P alone resolves only
# a symlinked directory), joining a relative target to the link's physical directory.
self="${BASH_SOURCE[0]}"
hops=0
while [ -L "$self" ] && [ "$hops" -lt 40 ]; do
  target="$(readlink "$self")"
  case "$target" in
    /*) self="$target" ;;
    *) self="$(cd "$(dirname "$self")" && pwd -P)/$target" ;;
  esac
  hops=$((hops + 1))
done
own_dir="$(cd "$(dirname "$self")" && pwd -P)"
if [ ! -r "$own_dir/lib/model-record.sh" ]; then
  die 3 "lib/model-record.sh not found next to this script ($own_dir/lib) — nothing recorded."
fi
if [ ! -r "$own_dir/lib/markdown.sh" ]; then
  die 3 "lib/markdown.sh not found next to this script ($own_dir/lib) — nothing recorded."
fi
# shellcheck source=lib/model-record.sh
. "$own_dir/lib/model-record.sh"

# The comment: record lines first, in column 0, then a blank line, then one
# plain-text line (starts with a letter, so it can never be read as a record).
body="" scope_list=""
i=0
while [ "$i" -lt "$scope_n" ]; do
  s="${scopes[$i]}"
  body="$body$(printf '<!-- pipeline-override: decided-by="%s" scope="%s" reason="%s" -->' "$decided_by" "$s" "$reason")"$'\n'
  if [ -z "$scope_list" ]; then scope_list="$s"; else scope_list="$scope_list, $s"; fi
  i=$((i + 1))
done
body="$body"$'\n'"$(printf 'Waiver recorded by the orchestrator, upfront, at %s'"'"'s instruction: "%s". Scope: %s. This waiver covers #%s only.' "$decided_by" "$reason" "$scope_list" "$issue")"

# BEGIN read-back
# The net: the whole body must read back through the gate's reader as exactly
# one ok record per scope, with the exact values given.
scan="$(rec_scan pipeline-override "$body")" || scan="?"
rows=0 bad=0
tab=$'\t'
while IFS= read -r row; do
  [ -n "$row" ] || continue
  rest="${row#*"$tab"}"
  cls="${rest%%"$tab"*}"
  rest="${rest#*"$tab"}"
  line="${rest#*"$tab"}"
  if [ "$cls" != ok ] || [ "$rows" -ge "$scope_n" ]; then bad=1; break; fi
  if [ "$(rec_field "$line" decided-by)" != "$decided_by" ] \
    || [ "$(rec_field "$line" reason)" != "$reason" ] \
    || [ "$(rec_field "$line" scope)" != "${scopes[$rows]}" ]; then
    bad=1
    break
  fi
  rows=$((rows + 1))
done <<EOF
$scan
EOF
if [ "$bad" = 1 ] || [ "$rows" -ne "$scope_n" ]; then
  die 1 "internal check failed: the comment does not read back as $scope_n ok record(s) — nothing posted."
fi
# END read-back

if [ "$dry_run" = 1 ]; then
  printf '%s\n' "$body"
  echo "dry-run: nothing posted" >&2
  exit 0
fi

gh_cmd="${PIPELINE_OVERRIDE_GH:-gh}"
case "$gh_cmd" in
  */*) [ -f "$gh_cmd" ] && [ -x "$gh_cmd" ] || die 3 "gh command '$gh_cmd' not found or not executable — nothing recorded." ;;
  *) command -v "$gh_cmd" >/dev/null 2>&1 || die 3 "gh command '$gh_cmd' not found on PATH — nothing recorded." ;;
esac

url="$(printf '%s\n' "$body" | "$gh_cmd" issue comment "$issue" --body-file -)"
rc=$?
if [ "$rc" -ne 0 ]; then
  die 4 "gh failed with exit $rc — nothing recorded."
fi
[ -z "$url" ] || printf '%s\n' "$url"
printf 'Recorded on issue #%s: scope %s, decided-by "%s", reason "%s". The merge gate sees it only if the PR title or body says Closes #%s.\n' \
  "$issue" "$scope_list" "$decided_by" "$reason" "$issue"

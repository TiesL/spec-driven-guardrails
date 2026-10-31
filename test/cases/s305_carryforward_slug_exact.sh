#!/usr/bin/env bash
# S305 — the carry-forward gate counts a slug as mentioned only when the round carries exactly that slug as a whole token (#453)
# Covers: F28
#
# Issue #453. Seam: the real gate against a recording fake gh serving REST data
# (comments), as S254. A slug is the maximal run of non-whitespace characters after
# `finding:`, compared whole; `ab` is not mentioned by `finding:abc`.
#
# Threat model: ACCIDENTAL (a short slug shadowed by a longer one with the same
# prefix silently clears a real accidental drop). No forger.
#
# Kill table (mutations this case must not survive):
#   substring-grep    `grep -F finding:<slug>` as before (C1, C4, C5, C7, C10)
#   prefix/suffix     prefix-only or suffix-only match (C1/C3, C5)
#   slug-as-regex     a future rewrite that reads the slug as a pattern (C6, C9)
#   narrow-boundary   boundary limited to [A-Za-z0-9_-] or to a following space (C5, C10)
#   second-marker     another marker on the line masking the first, or only the first
#                     marker per line read (C8)
#   open-side-only    the boundary check applied to the open side only (C1, C3)
#   clearing-broken   the fix breaks A37b clearing (C7)
#   output-moved      a changed output line or round number (every case)

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/review-rounds-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-rounds-helpers.sh"

GATE="$TEST_REPO_ROOT/skills/pre-merge-review/finding-carryforward-gate.sh"
[ -x "$GATE" ] || { fail "S305 — skills/pre-merge-review/finding-carryforward-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S305 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup

rr_out="" rr_err=""
rr_status=0
NL=$'\n'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z T3=2026-10-03T10:00:00Z
rev="$(rr_review)"
dn="$(rr_done)"
op() { rr_finding "$1" open; }
rs() { rr_finding "$1" resolved; }

# check <label> <expected "slug:round ..." sorted, or empty> <round body> ...: rounds as PR comments
check() {
  local label="$1" want="$2" ts=("$T1" "$T2" "$T3") args=() i=0 b got
  shift 2
  rr_reset
  for b in "$@"; do args+=("${ts[$i]}" "r$((i + 1))${NL}${b}${NL}${rev}${NL}${dn}"); i=$((i + 1)); done
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "${args[@]}"
  rr_script_run "$GATE" "$RR_PR"
  [ "$rr_status" -eq 0 ] || fail "S305/$label — exit $rr_status, stderr: $rr_err"
  if [ -z "$want" ]; then
    [ -z "$rr_err" ] || fail "S305/$label — clean empty result requires empty stderr, got: $rr_err"
  fi
  got="$(printf '%s\n' "$rr_out" | LC_ALL=C sed -n -E 's/^finding-carryforward: ([^ ]+) was open in the previous round and is missing from this one \(round ([0-9]+)\)$/\1:\2/p' | LC_ALL=C sort | LC_ALL=C tr '\n' ' ')"
  got="${got% }"
  [ "$got" = "$want" ] || fail "S305/$label — expected reported '[$want]', got '[$got]' (stdout: $(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|'); stderr: $rr_err)"
}
raw() { printf '<!-- finding:%s -->' "$1"; } # raw marker text, slug field verbatim

# C1: a longer slug does not carry the shorter one
check "C1 ab open, then only abc" "ab:2" "$(op ab)" "$(op abc)"
# C2: exact slug open or resolved carries it
check "C2 ab open, then ab open" "" "$(op ab)" "$(op ab)"
check "C2 ab open, then ab resolved" "" "$(op ab)" "$(rs ab)"
# C3: the reverse prefix
check "C3 abc open, then only ab" "abc:2" "$(op abc)" "$(op ab)"
# C4: both present / only the longer
check "C4a ab+abc open, then both" "" "$(op ab)${NL}$(op abc)" "$(op ab)${NL}$(op abc)"
check "C4b ab+abc open, then only abc" "ab:2" "$(op ab)${NL}$(op abc)" "$(op abc)"
# C5: boundaries
check "C5a ab at end of line" "" "$(op ab)" "finding:ab"
check "C5a ab followed by a space" "" "$(op ab)" "see finding:ab for details"
check "C5a ab followed by status=resolved -->" "" "$(op ab)" "<!-- finding:ab status=resolved -->"
check "C5b ab-x does not carry ab" "ab:2" "$(op ab)" "<!-- finding:ab-x status=open -->"
check "C5b ab_x does not carry ab" "ab:2" "$(op ab)" "<!-- finding:ab_x status=open -->"
# C6 / C9: regex characters in a slug stay literal (guard against a future regex rewrite)
for s in 'a.c' 'a+c' 'a*c' 'a[c'; do
  check "C6 $s open, then only abc" "$s:2" "$(op "$s")" "$(op abc)"
  check "C6 control: $s carried exactly" "" "$(op "$s")" "$(op "$s")"
done
check "C9 a.c and a+c, then abc and aac" "a+c:2 a.c:2" "$(op 'a.c')${NL}$(op 'a+c')" "$(op abc)${NL}$(op aac)"
# C7: clearing intact
check "C7a ab open, missing, exact ab in r3" "" "$(op ab)" "none here" "$(op ab)"
check "C7b ab open, missing, only abc in r3" "ab:2" "$(op ab)" "none here" "$(op abc)"
# C8: two markers on one line, each judged on its own slug
check "C8a abc open + ab resolved on one line" "" "$(op ab)" "$(op abc) $(rs ab)"
check "C8b abc and abd on one line" "ab:2" "$(op ab)" "$(op abc) $(op abd)"
# C9b-C10: glued punctuation is not a boundary; xfinding:ab still counts
check "C10 ab--> glued" "ab:2" "$(op ab)" "<!-- finding:ab-->"
check "C10 ab\" glued" "ab:2" "$(op ab)" 'quote "finding:ab"'
check "C10 ab. glued" "ab:2" "$(op ab)" "see finding:ab."
check "C10 xfinding:ab still a mention" "" "$(op ab)" "xfinding:ab"

test_done

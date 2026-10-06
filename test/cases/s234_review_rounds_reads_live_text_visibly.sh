#!/usr/bin/env bash
# S234 — review-rounds.sh prints no count when a live_text or marker read fails, and reads a marker after an invalid byte on its line the same under a UTF-8 LANG as under LC_ALL=C.
# Covers: F34, F42
#
# Issue #423, review round 1 of PR #443 (finding review-rounds-untested; QA
# round 1 note 1: review-rounds.sh used to carry a fourth live_text copy and
# now takes it from lib/markdown.sh). Two behaviours the other cases never
# reached, because review-rounds.sh was outside AC3:
#   (1) a failed read is visible: rr_rounds returns 1 and the script prints a
#       warning and NO round count, never a false "review-rounds: 2" for a
#       body that was read as empty. Seam: a PATH shim named awk that counts
#       its calls and exits 2 for the call(s) selected; the sweep fails each
#       awk call k of a baseline run alone (every call is a live_text or a
#       marker read), and all of them at once. Mutation: the
#       `live_text ... || return 1` of rr_rounds is removed (the sweep's
#       live_text calls turn red: the round vanishes from a printed count).
#   (2) the callers' own `tr '\001' '\n'` and the done-marker `grep` run under
#       the C locale: a body carrying `x<invalid byte>y ` BEFORE its marker
#       is read under LC_ALL unset + LANG=en_US.UTF-8 as under LC_ALL=C
#       (BSD tr aborts and cuts the body at the byte, BSD grep finds no match
#       after it). Mutations: `LC_ALL=C` removed from the tr; from the grep.
# The bytes reach the script through a placeholder swapped after jq (jq turns
# an invalid byte into U+FFFD). Not asserted: wording of a warning.
# Runs on the macOS leg (BWK awk, BSD tr/grep, bash 3.2); a host without a UTF-8
# locale reports the UTF-8 arm as skipped, except on Darwin where it fails.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/markdown-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/markdown-helpers.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/review-rounds-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-rounds-helpers.sh"

RR_SCRIPT="$TEST_REPO_ROOT/review-rounds.sh"
[ -x "$RR_SCRIPT" ] || { fail "S234 — review-rounds.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S234 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup

T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z T3=2026-10-03T10:00:00Z T4=2026-10-04T10:00:00Z
SHA40="cccccccccccccccccccccccccccccccccccccccc"
rev="$(rr_review)"
pln="$(rr_planning)"
done_m="<!-- pre-merge-review:done sha=$SHA40 -->"

# a gh in front of the recording fake that swaps the placeholder for the raw byte
RAWBIN="$SANDBOX/rr-rawbin"
mkdir -p "$RAWBIN"
cat > "$RAWBIN/gh" <<GHEOF
#!/bin/bash
tmp="\$(mktemp)"
trap 'rm -f "\$tmp"' EXIT
"$RR_BIN/gh" "\$@" > "\$tmp" || exit \$?
ff="\$(printf '\\377')"
tr_="\$(printf '\\342\\200')"
LC_ALL=C sed -e "s/@FF@/\$ff/g" -e "s/@TR@/\$tr_/g" "\$tmp"
GHEOF
chmod +x "$RAWBIN/gh"

AWK_SHIM_REAL="$(command -v awk)"
export AWK_SHIM_REAL
AWK_SHIM_COUNT="$SANDBOX/awk-count"
export AWK_SHIM_COUNT
shimdir="$SANDBOX/awkshim"
make_awk_shim "$shimdir"
shim_count() { if [ -r "$AWK_SHIM_COUNT" ]; then cat "$AWK_SHIM_COUNT"; else echo 0; fi; }
ALL=999999

RR_OUT=""
RR_RC=0
# rr_go <C|utf8> <fail-from> <fail-to>: stdout in RR_OUT, exit status RR_RC
rr_go() {
  local mode="$1" from="$2" to="$3"
  rm -f "$AWK_SHIM_COUNT"
  case "$mode" in
    C) RR_OUT="$(cd "$RR_CWD" && env LC_ALL=C AWK_SHIM_FAIL_FROM="$from" AWK_SHIM_FAIL_TO="$to" PATH="$shimdir:$RAWBIN:$PATH" "$RR_SCRIPT" "$RR_PR" "$RR_ISSUE" 2>/dev/null)" ;;
    utf8) RR_OUT="$(cd "$RR_CWD" && env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" AWK_SHIM_FAIL_FROM="$from" AWK_SHIM_FAIL_TO="$to" PATH="$shimdir:$RAWBIN:$PATH" "$RR_SCRIPT" "$RR_PR" "$RR_ISSUE" 2>/dev/null)" ;;
  esac
  RR_RC=$?
}
counts() { LC_ALL=C grep -a '^review-round' <<<"$RR_OUT" || true; }

# rr_fixture <prefix>: three rounds (a Review marker, a done-only body, a Review
# marker) and a Planning marker after them; each body line starts with <prefix>.
rr_fixture() {
  local pre="$1"
  rr_reset
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
    "$T1" "${pre}${rev}" \
    "$T2" "${pre}${done_m}" \
    "$T3" "${pre}${rev}" \
    "$T4" "${pre}${pln}"
}

# =========================================================================
# 1. a failed read is visible: no count, never a false one
# =========================================================================
rr_fixture ""
rr_go C 0 0
[ "$(shim_count)" -gt 0 ] || fail "S234 baseline — review-rounds.sh never called awk (count $(shim_count)): every arm below would be vacuous"
LC_ALL=C grep -aq '^review-rounds: 3$' <<<"$RR_OUT" || fail "S234 baseline — three rounds (review, done-only, review) should print 'review-rounds: 3', got: $RR_OUT (a broken fixture)"
total="$(shim_count)"

rr_go C 1 "$ALL"
[ "$(shim_count)" -gt 0 ] || fail "S234 all-fail — the shim was never invoked (vacuous pass)"
[ "$RR_RC" -eq 0 ] || fail "S234 all-fail — exit $RR_RC (the script is read-only and fails open: exit 0)"
[ -z "$(counts)" ] || fail "S234 all-fail — every awk call fails and the script still prints a count: $(counts)"

k=1
while [ "$k" -le "$total" ]; do
  rr_go C "$k" "$k"
  [ "$RR_RC" -eq 0 ] || fail "S234 call $k of $total — exit $RR_RC (fail-open: exit 0)"
  [ -z "$(counts)" ] || fail "S234 call $k of $total — awk call $k alone fails and the script prints a count (a body read as empty became 'no round'): $(counts)"
  k=$((k + 1))
done

# =========================================================================
# 2. the C locale holds for the script's own tr and grep
# =========================================================================
md_need_locale "S234" || test_done
for name in invalid truncated; do
  case "$name" in invalid) ph='@FF@' ;; truncated) ph='@TR@' ;; esac
  rr_fixture "x${ph}y "
  rr_go C 0 0
  c_counts="$(counts)"
  LC_ALL=C grep -aq '^review-rounds: 3$' <<<"$RR_OUT" || fail "S234 before/$name — baseline under LC_ALL=C: three rounds after the bytes should print 'review-rounds: 3', got: $RR_OUT"
  LC_ALL=C grep -aq '^planning-after: 3$' <<<"$RR_OUT" || fail "S234 before/$name — baseline under LC_ALL=C: the Planning marker after the bytes should be reported after round 3, got: $RR_OUT"
  rr_go utf8 0 0
  [ "$(counts)" = "$c_counts" ] || fail "S234 before/$name — under LANG=$MD_UTF8 (LC_ALL unset) the rounds read as '$(counts | paste -sd' ' -)', under LC_ALL=C as '$(printf '%s' "$c_counts" | paste -sd' ' -)': a tr or grep ran without the C locale"
done

test_done

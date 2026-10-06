#!/usr/bin/env bash
# S195 — compliance-evidence.sh: gate 1 shares the anchored attribute
# extraction, an effort-only difference between issues is NOT a conflict
# (#424), and exit code 3 names the lib.
# Covers: F39
#
# Issue #392, review of PR #397 (low findings that contradict the design).
# A25: neither script carries its own attribute extraction; a lookalike
# attribute (`xmodel=`) or free text ending in ` model=` is never a model.
# Seam: the collector's table rows, the conflict evidence text, and the
# documented exit codes.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/compliance-evidence.sh"
[ -x "$script" ] || { fail "S195 — compliance-evidence.sh is missing or not executable"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
export CE_ID=S195
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

nl=$'\n'

# ===== (3) gate 1: anchored extraction ========================================
# Discovery on the closing issue, the other three on the PR, each with a
# lookalike attribute BEFORE the real model=.
# the extra attribute goes BEFORE model= (the position that can hijack it)
lk() { printf '<!-- model-record: stage=%s %s model="claude-sonnet-5" effort="medium" -->' "$1" "$2"; }
disc() { lk Discovery "$1"; }
plan() { lk Planning "$1"; }
tst() { lk Test "$1"; }
impl() { lk Implementation "$1"; }
row1() { # label want-status issue265-markers pr-markers
  ce "Closes #265" "$4" "$3"
  assert_table_shape "S195 $1" "$ce_out"
  [ "$(row_status "$ce_out" 1)" = "$2" ] || fail "S195 — $1: gate 1 should be '$2', got '$(row_status "$ce_out" 1)' ($(row_evidence "$ce_out" 1))"
}
LA='xmodel="zzz-lookalike"'
row1 "gate 1, xmodel= before model=" evidenced "$(disc "$LA")" "$(plan "$LA")${nl}$(tst "$LA")${nl}$(impl "$LA")"
ev="$(row_evidence "$ce_out" 1)"
case "$ev" in *zzz-lookalike*) fail "S195 gate 1 — read the lookalike xmodel= as the model: $ev" ;; esac
case "$ev" in *claude-sonnet-5*) : ;; *) fail "S195 gate 1 — the real model should be cited, got: $ev" ;; esac
case "$ev" in *all*claude-sonnet-5*) : ;; *) fail "S195 gate 1 — four equal real models read as 'all', got: $ev" ;; esac

# the lookalikes must not make equal models look different (or the reverse)
row1 "gate 1, differing lookalikes, equal real models" evidenced "$(disc 'xmodel="a"')" "$(plan 'xmodel="b"')${nl}$(tst 'xmodel="c"')${nl}$(impl 'xmodel="d"')"
case "$(row_evidence "$ce_out" 1)" in *all*claude-sonnet-5*) : ;; *) fail "S195 gate 1 — lookalikes made equal models look different: $(row_evidence "$ce_out" 1)" ;; esac

# free text ending in ' model=' (floor-basis-like) before the real model
row1 "gate 1, text ending in ' model=' before model=" evidenced "$(disc 'note="beats model="')" "$(plan 'note="beats model="')${nl}$(tst 'note="x"')${nl}$(impl 'note="x"')"
ev="$(row_evidence "$ce_out" 1)"
case "$ev" in *"model="*) fail "S195 gate 1 — read text ending in ' model=' as a model: $ev" ;; esac

# a marker with NO real model= but such text is malformed, not a model
row1 "gate 1, no model= but 'model=' inside a value" indeterminate "$(disc 'x="y"')" "$(plan '')${nl}<!-- model-record: stage=Test note=\"beats model=\" effort=\"low\" -->${nl}$(impl '')"

# ===== (4) two closing issues that differ only in legacy effort ===============
# #424 (A33): effort is not part of the conflict key, so this is no conflict:
# the same model on both issues is read as one Review marker (evidenced), and
# no text about effort appears.
two="Closes #265, closes #266"
ce "$two" "$(mk Implementation claude-sonnet-5 medium)" "$(mk Review claude-sonnet-5 medium 'floor-basis="x"')" "$(mk Review claude-sonnet-5 high 'floor-basis="x"')"
assert_table_shape "S195 effort-only difference" "$ce_out"
[ "$(row_status "$ce_out" 2)" = "evidenced" ] || fail "S195 — an effort-only difference between issues is no conflict (#424): gate 2 should be evidenced, got '$(row_status "$ce_out" 2)' ($(row_evidence "$ce_out" 2))"
ev="$(row_evidence "$ce_out" 2)"
grep -qi 'conflict' <<<"$ev" && fail "S195 — no conflict text for an effort-only difference, got: $ev"
# a model conflict still shows both models, and no effort
ce "$two" "$(mk Implementation claude-sonnet-5 medium)" "$(mk Review claude-sonnet-5 medium 'floor-basis="x"')" "$(mk Review claude-opus-5 medium 'floor-basis="x"')"
ev="$(row_evidence "$ce_out" 2)"
case "$ev" in *claude-sonnet-5*claude-opus-5* | *claude-opus-5*claude-sonnet-5*) : ;; *) fail "S195 — a model conflict must still show both models, got: $ev" ;; esac
case "$ev" in *"(effort"*) fail "S195 — a model conflict must not quote the issues' efforts (#424), got: $ev" ;; esac

# ===== (5) exit code 3: header and behaviour ===================================
hdr="$(awk '/^# Exit codes:/ { f = 1 } f && /^# +3 / { g = 1; print; next } g && /^# +[0-9] / { exit } g && /^#( |$)/ && !/^# [A-Z]/ { print } g && /^# [A-Z]/ { exit }' "$script")"
[ -n "$hdr" ] || fail "S195 — could not find the exit-code-3 entry in the header comment"
grep -qE 'model-record|lib/' <<<"$hdr" || fail "S195 — the header's exit 3 entry must also name the missing library (lib/model-record.sh), got: $hdr"
# behaviour: the script alone, with no lib next to it, exits 3 and names it
alone="$SANDBOX/alone"
mkdir -p "$alone"
cp "$script" "$alone/compliance-evidence.sh"
err="$("$alone/compliance-evidence.sh" 279 2>&1 >/dev/null)"
rc=$?
[ "$rc" -eq 3 ] || fail "S195 — without lib/model-record.sh the collector must exit 3, got $rc"
grep -q 'model-record' <<<"$err" || fail "S195 — the missing-lib message must name lib/model-record.sh, got: $err"

test_done

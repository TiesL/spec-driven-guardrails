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
test_source_match -qE 'model-record|lib/' <<<"$hdr" || fail "S195 — the header's exit 3 entry must also name the missing library (lib/model-record.sh), got: $hdr"
# behaviour: the script alone, with no lib next to it, exits 3 and names it
alone="$SANDBOX/alone"
mkdir -p "$alone"
cp "$script" "$alone/compliance-evidence.sh"
err="$("$alone/compliance-evidence.sh" 279 2>&1 >/dev/null)"
rc=$?
[ "$rc" -eq 3 ] || fail "S195 — without lib/model-record.sh the collector must exit 3, got $rc"
test_source_match -q 'model-record' <<<"$err" || fail "S195 — the missing-lib message must name lib/model-record.sh, got: $err"

test_done

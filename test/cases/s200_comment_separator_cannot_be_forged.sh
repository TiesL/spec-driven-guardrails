#!/usr/bin/env bash
# S200 — legacy collector input coverage retained unchanged until #429.
# Covers: F39
# #427 retires gate half; strict gate counterparts: S257/S259/S264/S266.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S200 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S200
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

RS=$'\036'
NL=$'\n'
impl_good="$(marker Implementation Sonnet high)"
rev_sp='<!-- model-record: stage=Review note=" same model --> lower effort" model="Sonnet" effort="low" -->'
UNC='<!-- model-record: stage=Review model="Sonnet effort=high'

# ---------------------------------------------------------------------------
# compliance-evidence.sh: the same byte in a PR comment
# ---------------------------------------------------------------------------
impl_c="$(mk Implementation claude-sonnet-5 medium)"
c_unc='<!-- model-record: stage=Review model="claude-opus-5 effort=high'
c_rev_sp='<!-- model-record: stage=Review note=" same model --> lower effort" model="claude-sonnet-5" effort="low" -->'
for variant in "${c_unc}${RS}" "${RS}${c_unc}" "${c_unc}${RS} x\" -->"; do
  ce "Closes #265" "$impl_c
$variant
$c_rev_sp" ""
  assert_table_shape "S200 gate2 separator in an unclosed comment" "$ce_out"
  [ "$(row_status "$ce_out" 2)" = "evidenced" ] || fail "S200 gate2 — the separator byte in comment N must not change how comment N+1 is read, got '$(row_status "$ce_out" 2)' ($(row_evidence "$ce_out" 2))"
done

test_done

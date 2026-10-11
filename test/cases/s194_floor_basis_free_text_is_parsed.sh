#!/usr/bin/env bash
# S194 — legacy collector input coverage retained unchanged until #429.
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

command -v jq >/dev/null 2>&1 || { fail "S194 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S194
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

# label|value pairs (the newline variant is tested separately, per script)
variants=(
  "gt|stronger model > weaker model"
  "lt|a < b"
  "dashes|mechanical -- rename"
  "arrow|stronger model --> weaker model"
  "opener|mentions an <!-- opener inside"
  "mix|<!-- x --> > < --"
)

NL=$'\n'
SOH=$'\001'
BT='`'

# ---------------------------------------------------------------------------
# compliance-evidence.sh gate 2
# ---------------------------------------------------------------------------
impl_m="$(mk Implementation claude-sonnet-5 medium)"
no_misleading() { # label
  local ev
  ev="$(row_evidence "$ce_out" 2)"
  case "$ev" in
    *illustration* | *"code span"* | *quoted* | *"no \`stage=Review\`"*)
      fail "S194 gate2/$1 — the marker was recognised, so the evidence must not claim a quoted illustration or an absent marker, got: $ev" ;;
  esac
}
ce_variant() { # label value
  local label="$1" v="$2" fb
  fb="floor-basis=\"$v\""
  check "gate2/$label same model, lower legacy effort" evidenced "$impl_m
$(mk Review claude-sonnet-5 low "$fb")"
  case "$(row_evidence "$ce_out" 2)" in
    *"${BT}low${BT}"* | *"${BT}medium${BT}"*) fail "S194 gate2/$label — the verdict is on the model alone and must quote no effort (#424), got: $(row_evidence "$ce_out" 2)" ;;
  esac
  no_misleading "$label"
  check "gate2/$label same model, equal effort" evidenced "$impl_m
$(mk Review claude-sonnet-5 medium "$fb")"
  no_misleading "$label"
  check "gate2/$label different models" unverifiable-from-artifacts "$impl_m
$(mk Review claude-opus-5 medium "$fb")"
  no_misleading "$label"
}
for pair in "${variants[@]}"; do ce_variant "${pair%%|*}" "${pair#*|}"; done
ce_variant nl "line one${SOH}line two"

# the marker on a closing issue, with a PR comment fetch failing: the verdict
# degrades to indeterminate because of the lookup guard, not because the marker
# was "not found"
both="$(mk Implementation claude-sonnet-5 medium)
$(mk Review claude-sonnet-5 low 'floor-basis="stronger > weaker"')"
check "gate2 lookup guard, PR comments fail, '>' in floor-basis" indeterminate FAIL "$both"
case "$(row_evidence "$ce_out" 2)" in
  *"no \`stage=Review\`"*) fail "S194 gate2 guard — the Review marker with '>' was read, so the guard text must not say it was not found, got: $(row_evidence "$ce_out" 2)" ;;
esac
check "gate2 sound verdict, one issue fails, markers on the PR, '>' in floor-basis" evidenced \
  "$impl_m
$(mk Review claude-sonnet-5 low 'floor-basis="stronger > weaker"')" FAIL

test_done

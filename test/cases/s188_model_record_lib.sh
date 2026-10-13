#!/usr/bin/env bash
# S188 — unchanged normalization and v2 attribute walks.
# Covers: F39
# Seam: normalize_model, rec_scan and rec_field on strict valid records.
# Invalid attribute order/classification belongs to S271/S246.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

lib="$TEST_REPO_ROOT/lib/model-record.sh"
if [ ! -f "$lib" ]; then
  fail "S188 — lib/model-record.sh does not exist"
  test_done
fi
# shellcheck source=../../lib/model-record.sh disable=SC1091
. "$lib"
for fn in normalize_model rec_field; do
  type "$fn" >/dev/null 2>&1 || fail "S188 — lib/model-record.sh defines no $fn"
done
type rec_field >/dev/null 2>&1 && type normalize_model >/dev/null 2>&1 || test_done
# #424: effort_rank is deleted; nothing may be left to rank an effort
! type effort_rank >/dev/null 2>&1 || fail "S188/#424 — lib/model-record.sh still defines effort_rank"
! test_source_match -qE '(^|[^A-Za-z_])effort_rank' "$lib" || fail "S188/#424 — lib/model-record.sh still mentions effort_rank"

eq() { # label, got, want
  [ "$2" = "$3" ] || fail "S188 — $1: got '$2', want '$3'"
}

# --- normalize_model: unchanged (#268): strips the vendor word, an 8-digit
# date and separators, folds case; no model table.
eq "label styles fold together" "$(normalize_model 'Sonnet 5')" "$(normalize_model 'claude-sonnet-5')"
eq "case folds" "$(normalize_model 'Claude SONNET 5')" "$(normalize_model 'claude sonnet 5')"
eq "snapshot date stripped" "$(normalize_model 'claude-sonnet-5-20260101')" "$(normalize_model 'claude-sonnet-5')"
eq "concrete form" "$(normalize_model 'claude-sonnet-5-20260101')" "sonnet 5"
eq "display name" "$(normalize_model 'Claude Opus 5')" "opus 5"
eq "multi-part version" "$(normalize_model 'claude-opus-5-5')" "opus 5 5"
[ "$(normalize_model 'claude-sonnet-5')" != "$(normalize_model 'claude-opus-5')" ] \
  || fail "S188 — different models must normalize different"
# A short alias is NOT the same model as its full id (human decision 4: no
# model table; different models are a recorded judgment, #424).
[ "$(normalize_model 'opus')" != "$(normalize_model 'claude-opus-5')" ] \
  || fail "S188 — a short alias must not normalize equal to its full id (no model table)"
eq "empty stays empty" "$(normalize_model '')" ""

# --- rec_field <line> <name>: the quoted value of one attribute.
m='<!-- model-record: stage=Review model="claude-sonnet-5" effort="high" floor-basis="same model, higher effort" -->'
eq "model" "$(rec_field "$m" model)" "claude-sonnet-5"
eq "effort" "$(rec_field "$m" effort)" "high"
eq "floor-basis (value with spaces and a comma)" "$(rec_field "$m" floor-basis)" "same model, higher effort"
eq "stage-less attribute absent" "$(rec_field "$m" same-model-exception)" ""
eq "absent attribute prints nothing" "$(rec_field '<!-- model-record: stage=Test model="x" -->' effort)" ""

# Word boundary: an attribute whose name merely ENDS in model/effort must
# never be read as model/effort, in either order (A25, V5).
m='<!-- model-record: stage=Review model="sonnet" reviewer-model="opus" peak-effort="high" effort="low" -->'
eq "reviewer-model before model" "$(rec_field "$m" model)" "sonnet"
eq "peak-effort before effort" "$(rec_field "$m" effort)" "low"
m='<!-- model-record: stage=Review model="sonnet" same-model="opus" effort="low" max-effort="high" -->'
eq "same-model after model" "$(rec_field "$m" model)" "sonnet"
eq "max-effort after effort" "$(rec_field "$m" effort)" "low"
m='<!-- model-record: stage=Review model="real" x-model="opus" -->'
eq "suffixed name cannot replace model" "$(rec_field "$m" model)" "real"
m='<!-- model-record: stage=Review model="sonnet" floor-basis="uses a bigger model" -->'
eq "floor-basis first, model second" "$(rec_field "$m" model)" "sonnet"
# floor-basis itself is not found inside a longer name either
m='<!-- model-record: stage=Review model="real" old-floor-basis="x" -->'
eq "floor-basis not matched inside old-floor-basis" "$(rec_field "$m" floor-basis)" ""

# Strict invalid records are not attribute sources (S246 pins isolation).
for m in '<!-- model-record: stage=Review model=Sonnet effort=medium -->' '<!-- model-record: stage=Review model="a" effort=medium -->'; do
 out="$(rec_scan model-record "$m")"
 case "$out" in $'1\tnear-miss\tReview\t'*) :;; *) fail "invalid record class: $out";; esac
done
eq "empty optional value" "$(rec_field '<!-- model-record: stage=Review model="a" floor-basis="" -->' floor-basis)" ""

test_done

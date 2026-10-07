#!/usr/bin/env bash
# S188 — lib/model-record.sh: one shared normalize_model and marker_attr for
# the model-record gate and the compliance collector. effort_rank is gone
# (#424: effort is neither chosen nor checked).
# Covers: F39
#
# Issue #392, A25. Seam: the three functions of the sourced lib
# (normalize_model <label>, marker_attr <marker-line> <name>), by their
# documented output only; marker_attr stays generic, so it still reads a
# legacy `effort` attribute, which nothing interprets any more (#424). normalize_model's behaviour is
# the pre-#392 one, moved unchanged (#268).

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
for fn in normalize_model marker_attr; do
  type "$fn" >/dev/null 2>&1 || fail "S188 — lib/model-record.sh defines no $fn"
done
type marker_attr >/dev/null 2>&1 && type normalize_model >/dev/null 2>&1 || test_done
# #424: effort_rank is deleted; nothing may be left to rank an effort
! type effort_rank >/dev/null 2>&1 || fail "S188/#424 — lib/model-record.sh still defines effort_rank"
! grep -qE '(^|[^A-Za-z_])effort_rank' "$lib" || fail "S188/#424 — lib/model-record.sh still mentions effort_rank"

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

# --- marker_attr <line> <name>: the quoted value of one attribute.
m='<!-- model-record: stage=Review model="claude-sonnet-5" effort="high" floor-basis="same model, higher effort" -->'
eq "model" "$(marker_attr "$m" model)" "claude-sonnet-5"
eq "effort" "$(marker_attr "$m" effort)" "high"
eq "floor-basis (value with spaces and a comma)" "$(marker_attr "$m" floor-basis)" "same model, higher effort"
eq "stage-less attribute absent" "$(marker_attr "$m" same-model-exception)" ""
eq "absent attribute prints nothing" "$(marker_attr '<!-- model-record: stage=Test model="x" -->' effort)" ""

# Word boundary: an attribute whose name merely ENDS in model/effort must
# never be read as model/effort, in either order (A25, V5).
m='<!-- model-record: stage=Review reviewer-model="opus" model="sonnet" peak-effort="high" effort="low" -->'
eq "reviewer-model before model" "$(marker_attr "$m" model)" "sonnet"
eq "peak-effort before effort" "$(marker_attr "$m" effort)" "low"
m='<!-- model-record: stage=Review model="sonnet" same-model="opus" effort="low" max-effort="high" -->'
eq "same-model after model" "$(marker_attr "$m" model)" "sonnet"
eq "max-effort after effort" "$(marker_attr "$m" effort)" "low"
m='<!-- model-record: stage=Review x-model="opus" -->'
eq "only a suffixed name: model is absent" "$(marker_attr "$m" model)" ""
m='<!-- model-record: stage=Review floor-basis="uses a bigger model" model="sonnet" -->'
eq "floor-basis first, model second" "$(marker_attr "$m" model)" "sonnet"
# floor-basis itself is not found inside a longer name either
m='<!-- model-record: stage=Review old-floor-basis="x" -->'
eq "floor-basis not matched inside old-floor-basis" "$(marker_attr "$m" floor-basis)" ""

# Unquoted and empty values.
eq "unquoted model is not read" "$(marker_attr '<!-- model-record: stage=Review model=Sonnet effort=medium -->' model)" ""
eq "unquoted effort is not read" "$(marker_attr '<!-- model-record: stage=Review model="a" effort=medium -->' effort)" ""
eq "empty value is empty" "$(marker_attr '<!-- model-record: stage=Review model="a" floor-basis="" -->' floor-basis)" ""

# The attribute-hijack arms (#397 review round: a floor-basis ending in ' model='
# or ' effort=', model= inside a value, `>`, `<`, `--` and `-->` in a value) moved
# to S246 (issue #425, R5), where they are asserted on rec_field against strict
# lines; the `>`, `<` and `-->` shapes are near-misses under the v2 grammar
# (S243), not lines marker_attr's successor reads. marker_attr stays here, with
# its word-boundary arms, until its last caller moves (V8).

test_done

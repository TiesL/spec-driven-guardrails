#!/usr/bin/env bash
# S188 — lib/model-record.sh: one shared normalize_model, effort_rank and
# marker_attr for the model-record gate and the compliance collector.
# Covers: F39
#
# Issue #392, A25. Seam: the three functions of the sourced lib
# (normalize_model <label>, effort_rank <value>, marker_attr <marker-line>
# <name>), by their documented output only. normalize_model's behaviour is
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
for fn in normalize_model effort_rank marker_attr; do
  type "$fn" >/dev/null 2>&1 || fail "S188 — lib/model-record.sh defines no $fn"
done
type marker_attr >/dev/null 2>&1 && type effort_rank >/dev/null 2>&1 && type normalize_model >/dev/null 2>&1 || test_done

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
# model table; the effort check is skipped, recorded as debt).
[ "$(normalize_model 'opus')" != "$(normalize_model 'claude-opus-5')" ] \
  || fail "S188 — a short alias must not normalize equal to its full id (no model table)"
eq "empty stays empty" "$(normalize_model '')" ""

# --- effort_rank: low < medium < high, as 0/1/2; unknown prints nothing.
eq "low" "$(effort_rank low)" "0"
eq "medium" "$(effort_rank medium)" "1"
eq "high" "$(effort_rank high)" "2"
eq "case-insensitive HIGH" "$(effort_rank HIGH)" "2"
eq "case-insensitive Medium" "$(effort_rank Medium)" "1"
for unknown in session-default unknown max xhigh "" " " "very high" "low,high" 1; do
  eq "unknown effort '$unknown' prints nothing" "$(effort_rank "$unknown")" ""
done

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

# --- #397 review round (#392): free text in floor-basis must never be read
# as another attribute, and `>`, `<`, `--` inside a value are just text.
m='<!-- model-record: stage=Review xmodel="x" model="opus" xeffort="high" effort="low" -->'
eq "xmodel before model" "$(marker_attr "$m" model)" "opus"
eq "xeffort before effort" "$(marker_attr "$m" effort)" "low"
m='<!-- model-record: stage=Review floor-basis="beats model=" model="opus" effort="low" -->'
eq "floor-basis ending in ' model=' does not hijack model" "$(marker_attr "$m" model)" "opus"
m='<!-- model-record: stage=Review floor-basis="slower effort=" model="opus" effort="high" -->'
eq "floor-basis ending in ' effort=' does not hijack effort" "$(marker_attr "$m" effort)" "high"
m='<!-- model-record: stage=Review floor-basis="beats model=" effort="low" -->'
eq "model absent: a floor-basis ending in ' model=' is not a model" "$(marker_attr "$m" model)" ""
m='<!-- model-record: stage=Review floor-basis="uses model= and effort= words" -->'
eq "model absent: model= inside a value is not a model" "$(marker_attr "$m" model)" ""
eq "model absent: effort= inside a value is not an effort" "$(marker_attr "$m" effort)" ""
m='<!-- model-record: stage=Review floor-basis="stronger > weaker, a < b, a -- b" model="opus" effort="low" -->'
eq "value with > < -- : model" "$(marker_attr "$m" model)" "opus"
eq "value with > < -- : effort" "$(marker_attr "$m" effort)" "low"
eq "value with > < -- : floor-basis itself" "$(marker_attr "$m" floor-basis)" "stronger > weaker, a < b, a -- b"
m='<!-- model-record: stage=Review model="opus" effort="low" floor-basis="x --> y" -->'
eq "value containing --> : floor-basis itself" "$(marker_attr "$m" floor-basis)" "x --> y"

test_done

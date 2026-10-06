#!/usr/bin/env bash
# S196 — the shared marker parser works under a UTF-8 locale as well as
# LC_ALL=C, and a failure of its awk is never silent.
# Covers: F39
#
# Issue #392, round 3 of the PR #397 review (high finding). On macOS awk
# (BWK) under a UTF-8 locale, `substr` splits a multibyte character and a
# regex test on the fragment aborts ("towc: multibyte conversion failure"):
# a non-ASCII byte right after `stage=` (the placeholder prose `stage=…`
# this repo really writes) silently dropped every later marker, and the
# gate failed open. Every delimiter of the grammar is ASCII, so the parser
# must run its awk programs under LC_ALL=C. PLATFORM NOTE: only BWK awk
# (macOS) aborts; gawk and mawk (Linux CI) do not, so the UTF-8 half proves
# the fix on macOS only, which is why the code itself must set LC_ALL=C and
# a fake awk checks the failure path on every platform.
# Seam: model-record-gate.sh stdout and compliance-evidence.sh's rows,
# against fake gh, with the locale exported by this test.
#
# Issue #424: "the marker was read" used to be proved by the same-model
# lower-effort finding. With effort gone, a read marker pair gives NO output
# (gate) or `evidenced` (gate 2), while a dropped marker gives "no record
# found for stage ..." / not-evidenced. The proof is the absence of those.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S196 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S196
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

# --- a UTF-8 locale that exists on this machine ------------------------------
avail="$(locale -a 2>/dev/null)"
utf8=""
for cand in en_US.UTF-8 nl_NL.UTF-8 C.UTF-8 en_US.utf8 C.utf8; do
  if grep -qix "$cand" <<<"$avail"; then utf8="$cand"; break; fi
done
locales="C"
if [ -n "$utf8" ]; then
  locales="C $utf8"
else
  echo "    NOTE: S196 — no UTF-8 locale is installed here (tried en_US.UTF-8 nl_NL.UTF-8 C.UTF-8); the UTF-8 half cannot run, falling back to checking that the parser pins LC_ALL=C for its awk programs" >&2
  grep -qE 'LC_ALL=C[[:space:]]+awk|LC_ALL=C[[:space:]]+(command[[:space:]]+)?awk|export LC_ALL=C|local LC_ALL=C' "$TEST_REPO_ROOT/lib/model-record.sh" \
    || fail "S196 — no UTF-8 locale to test with, and lib/model-record.sh does not pin LC_ALL=C for its awk programs"
fi

PH='<!-- model-record: stage=… -->'
NL=$'\n'
impl_g="$(marker Implementation Sonnet high)"

# ---------------------------------------------------------------------------
# gate: placeholder prose before the real markers must not drop them
# ---------------------------------------------------------------------------
gate_case() { # label locale body...   (bodies = comments, in order)
  local label="$1" loc="$2"
  shift 2
  rf_data "$@"
  rf_out="$(cd "$RF_PLAIN" && PATH="$RF_BIN:$PATH" LC_ALL="$loc" LANG="$loc" "$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh" 246 2>/dev/null)"
  rf_status=$?
  [ "$rf_status" -eq 0 ] || fail "S196 gate/$label [$loc] — exit $rf_status"
  [ -z "$rf_out" ] \
    || fail "S196 gate/$label [$loc] — both markers must be read (no 'no record found', no finding at all), got: '$rf_out'"
}
for loc in $locales; do
  rev_low="$(marker Review Sonnet low 'floor-basis="ok"')"
  gate_case "placeholder in its own comment" "$loc" "Placeholder: \`$PH\` is written as prose." "$impl_g" "$rev_low"
  gate_case "placeholder bare, own comment" "$loc" "$PH" "$impl_g" "$rev_low"
  gate_case "placeholder in the same comment, before the markers" "$loc" "see $PH${NL}$impl_g${NL}$rev_low"
  gate_case "non-ASCII in a quoted value" "$loc" "$impl_g" "$(marker Review Sonnet low 'floor-basis="stronger → weaker, ≥ Implementation"')"
  gate_case "non-ASCII outside the quotes" "$loc" "$impl_g" "<!-- model-record: stage=Review model=\"Sonnet\" effort=\"low\" note=… floor-basis=\"ok\" -->"
  gate_case "non-ASCII right after stage= on a real marker is not a stage" "$loc" "<!-- model-record: stage=Réview model=\"Sonnet\" effort=\"high\" -->${NL}$impl_g" "$rev_low"
done

# ---------------------------------------------------------------------------
# compliance-evidence.sh: gates 1 and 2
# ---------------------------------------------------------------------------
impl_c="$(mk Implementation claude-sonnet-5 medium)"
rev_c_low="$(mk Review claude-sonnet-5 low 'floor-basis="ok"')"
ce_case() { # label locale
  local label="$1" loc="$2" pr="$3" st="$4"
  export LC_ALL="$loc" LANG="$loc"
  check "$label [$loc]" "$st" "$pr"
  unset LC_ALL LANG
}
for loc in $locales; do
  ce_case "gate2 placeholder before markers" "$loc" "$PH
$impl_c
$rev_c_low" evidenced
  case "$(row_evidence "$ce_out" 2)" in
    *claude-sonnet-5*) : ;;
    *) fail "S196 gate2 [$loc] — the model-only verdict must name the model, got: $(row_evidence "$ce_out" 2)" ;;
  esac
  ce_case "gate2 non-ASCII in quoted value" "$loc" "$impl_c
$(mk Review claude-sonnet-5 low 'floor-basis="stronger → weaker"')" evidenced
  ce_case "gate2 non-ASCII outside quotes" "$loc" "$impl_c
<!-- model-record: stage=Review model=\"claude-sonnet-5\" effort=\"low\" note=… floor-basis=\"ok\" -->" evidenced
  # gate 1: Planning after the placeholder
  export LC_ALL="$loc" LANG="$loc"
  ce "Closes #265" "$PH
$(mk Planning claude-sonnet-5 medium)
$(mk Test claude-sonnet-5 medium)
$impl_c" "$(mk Discovery claude-sonnet-5 low)"
  unset LC_ALL LANG
  [ "$(row_status "$ce_out" 1)" = "evidenced" ] || fail "S196 gate1 [$loc] — all four stages are recorded after a placeholder; got '$(row_status "$ce_out" 1)' ($(row_evidence "$ce_out" 1))"
done

# ---------------------------------------------------------------------------
# a failure of the parser's awk is never silent
# ---------------------------------------------------------------------------
real_awk="$(command -v awk)"
fakeawk="$SANDBOX/fakeawk"
mkdir -p "$fakeawk"
cat > "$fakeawk/awk" <<EOF2
#!/bin/sh
# fails only the marker parser's programs (they take -v want=...); anything
# else is the real awk
case "\$*" in
  *want=*) echo "awk: simulated parser failure" >&2; exit 2 ;;
esac
exec "$real_awk" "\$@"
EOF2
chmod +x "$fakeawk/awk"

rf_data "$impl_g" "$(marker Review Sonnet low 'floor-basis="ok"')"
rf_out="$(cd "$RF_PLAIN" && PATH="$fakeawk:$RF_BIN:$PATH" "$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh" 246 2>/dev/null)"
rf_status=$?
if [ "$rf_status" -eq 0 ]; then
  grep -q '^model-record:' <<<"$rf_out" \
    || fail "S196 gate — the marker parser's awk failed and the gate printed no model-record: finding and exited 0 (a silent fail-open), got: '$rf_out'"
fi

PATH="$fakeawk:$PATH" ce "Closes #265" "$impl_c
$rev_c_low" "$(mk Discovery claude-sonnet-5 low)" 2>/dev/null
# ce ran the collector with the system PATH inside; run it again with the fake first
bin="$(cat "$FAKEGH_OUT")"
ce_out="$(PATH="$fakeawk:$bin:$PATH" "$script" 279 2>/dev/null)"
ce_rc=$?
if [ "$ce_rc" -eq 0 ]; then
  [ "$(row_status "$ce_out" 2)" = "indeterminate" ] \
    || fail "S196 gate2 — the marker parser's awk failed: gate 2 must be indeterminate (or the run non-zero), got '$(row_status "$ce_out" 2)' ($(row_evidence "$ce_out" 2))"
  [ "$(row_status "$ce_out" 1)" != "evidenced" ] \
    || fail "S196 gate1 — the marker parser's awk failed: gate 1 must not claim evidenced from an unread corpus"
fi

test_done

#!/usr/bin/env bash
# S202 — model-record-gate.sh reports a latest marker whose `model` or `effort`
# cannot be read, for each of the five stages.
# Covers: F40
#
# Issue #402, R3/R4, AC3-AC6, Architect A26 and the human decisions of
# 2026-10-03: an unquoted (but otherwise well-formed), empty or missing
# `model` or `effort` on the LATEST marker of any of the five stages is a
# visible, non-blocking finding (prefix `model-record:`, never `role-played:`,
# exit 0), one line per stage and field. Before this, the gate stayed silent
# while the collector said `indeterminate`. Everything else is unchanged: a
# quoted marker (also `effort="unknown"`), a placeholder, a quoted example in
# a fence, a missing marker (the existing "no record found" line only), and a
# project that did not opt in sees the same findings.
# Seam: the gate's stdout lines and exit status against a data-driven fake
# `gh`; the collector's gates 1 and 2 as the consistency control.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S202 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S202
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

NL=$'\n'
M="claude-haiku-4-5"
good() { # stage -> a fully well-formed quoted marker
  if [ "$1" = Review ]; then
    printf '<!-- model-record: stage=Review model="%s" effort="high" floor-basis="same model, higher effort" -->' "$M"
  else
    printf '<!-- model-record: stage=%s model="%s" effort="medium" -->' "$1" "$M"
  fi
}
bad() { # stage form -> a marker with one unreadable field (Review keeps its floor-basis)
  local s="$1" form="$2" fb=""
  [ "$s" = Review ] && fb=' floor-basis="why"'
  case "$form" in
    unquoted-model) printf '<!-- model-record: stage=%s model=%s effort="low"%s -->' "$s" "$M" "$fb" ;;
    unquoted-effort) printf '<!-- model-record: stage=%s model="%s" effort=low%s -->' "$s" "$M" "$fb" ;;
    empty-model) printf '<!-- model-record: stage=%s model="" effort="low"%s -->' "$s" "$fb" ;;
    empty-effort) printf '<!-- model-record: stage=%s model="%s" effort=""%s -->' "$s" "$M" "$fb" ;;
    missing-model) printf '<!-- model-record: stage=%s effort="low"%s -->' "$s" "$fb" ;;
    missing-effort) printf '<!-- model-record: stage=%s model="%s"%s -->' "$s" "$M" "$fb" ;;
    unquoted-both) printf '<!-- model-record: stage=%s model=%s effort=low%s -->' "$s" "$M" "$fb" ;;
  esac
}

# data5 <discovery> <planning> <test> <implementation> <review> [extra comments...]:
# Discovery on the closing issue, the rest one comment each on the PR
# (the dispatched shape). An empty argument leaves that stage out.
data5() {
  local d="$1" p="$2" t="$3" i="$4" r="$5" x
  shift 5
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
  json_comments "$FAKE_GH_DATA/reviews-246.json"
  if [ -n "$d" ]; then json_comments "$FAKE_GH_DATA/comments-239.json" "$d"; else json_comments "$FAKE_GH_DATA/comments-239.json"; fi
  local -a bodies=()
  for x in "$p" "$t" "$i" "$r"; do [ -n "$x" ] && bodies+=("$x"); done
  for x in "$@"; do bodies+=("$x"); done
  json_comments "$FAKE_GH_DATA/comments-246.json" "${bodies[@]}"
}
run() { rf_gate "${1:-$RF_PLAIN}"; }
no_role_played() { ! grep -q '^role-played: ' <<<"$rf_out" || fail "S202 $1 — a marker finding must never use the role-played: prefix, got: $rf_out"; }

# marker for stage $1 in its slot, everything else good
data_with() { # stage marker [extra...]
  local s="$1" m="$2"
  shift 2
  local d p t i r
  d="$(good Discovery)"; p="$(good Planning)"; t="$(good Test)"; i="$(good Implementation)"; r="$(good Review)"
  case "$s" in
    Discovery) d="$m" ;; Planning) p="$m" ;; Test) t="$m" ;; Implementation) i="$m" ;; Review) r="$m" ;;
  esac
  data5 "$d" "$p" "$t" "$i" "$r" "$@"
}

# ---- control: five well-formed markers give nothing -------------------------
data5 "$(good Discovery)" "$(good Planning)" "$(good Test)" "$(good Implementation)" "$(good Review)"
run
[ "$rf_status" -eq 0 ] && [ -z "$rf_out" ] || fail "S202 control — five well-formed quoted markers: expected no output and exit 0, got status $rf_status: '$rf_out'"

# ---- each stage x each form: exactly one finding, naming stage and field -----
for s in Discovery Planning Test Implementation Review; do
  for form in unquoted-model empty-model missing-model unquoted-effort empty-effort missing-effort; do
    field="${form#*-}"
    data_with "$s" "$(bad "$s" "$form")"
    run
    [ "$rf_status" -eq 0 ] || fail "S202 $s/$form — exit $rf_status (non-blocking)"
    [ "$(rf_findings)" -eq 1 ] || fail "S202 $s/$form — expected exactly one finding, got: '$rf_out'"
    case "$rf_out" in
      "model-record:"*) : ;;
      *) fail "S202 $s/$form — the finding must start with the model-record: prefix, got: '$rf_out'" ;;
    esac
    grep -q "$s" <<<"$rf_out" || fail "S202 $s/$form — the finding must name the stage $s, got: '$rf_out'"
    grep -qiE "(^|[^a-z])$field([^a-z]|$)" <<<"$rf_out" || fail "S202 $s/$form — the finding must name the unreadable field ($field), got: '$rf_out'"
    # the OTHER field must not be blamed
    other=effort; [ "$field" = effort ] && other=model
    grep -qE "no quoted $other" <<<"$rf_out" && fail "S202 $s/$form — only the $field is unreadable, got: '$rf_out'"
    no_role_played "$s/$form"
  done
  # both fields unreadable: two lines, one per field
  data_with "$s" "$(bad "$s" unquoted-both)"
  run
  [ "$(rf_findings)" -eq 2 ] || fail "S202 $s/unquoted-both — one line per stage and field (two), got: '$rf_out'"
done

# ---- the dry-run example, verbatim shape -------------------------------------
data_with Implementation '<!-- model-record: stage=Implementation model=claude-haiku-4-5 effort=low -->'
run
[ "$(rf_findings)" -eq 2 ] && grep -q 'Implementation' <<<"$rf_out" || fail "S202 dry-run example — unquoted Implementation marker must be reported, got: '$rf_out'"

# ---- Review and Implementation unreadable together: separate lines ----------
data5 "$(good Discovery)" "$(good Planning)" "$(good Test)" "$(bad Implementation unquoted-model)" "$(bad Review unquoted-model)"
run
[ "$(rf_findings)" -eq 2 ] || fail "S202 — Implementation and Review both unreadable: two lines, each once, got: '$rf_out'"
grep -q 'Implementation' <<<"$rf_out" && grep -q 'Review' <<<"$rf_out" || fail "S202 — each line must name its stage, got: '$rf_out'"
[ "$(grep -c 'Implementation' <<<"$rf_out")" -eq 1 ] || fail "S202 — Implementation reported more than once: '$rf_out'"

# ---- mixed: quoted model, unquoted effort -> only the effort -----------------
data_with Planning '<!-- model-record: stage=Planning model="claude-haiku-4-5" effort=low -->'
run
[ "$(rf_findings)" -eq 1 ] && grep -qiE 'effort' <<<"$rf_out" || fail "S202 mixed — only the unquoted effort is reported, got: '$rf_out'"
# a quoted marker with an unquoted OTHER attribute is fine for model
data_with Implementation '<!-- model-record: stage=Implementation model="claude-haiku-4-5" effort="low" note=hello -->'
run
[ -z "$rf_out" ] || fail "S202 — an unrelated unquoted attribute is not a finding, got: '$rf_out'"
# effort="unknown" is the documented honest value, not a finding
data_with Implementation '<!-- model-record: stage=Implementation model="claude-haiku-4-5" effort="unknown" -->'
run
[ -z "$rf_out" ] || fail "S202 — effort=\"unknown\" is quoted and honest: no finding, got: '$rf_out'"

# ---- only the LATEST marker of a stage counts ---------------------------------
data5 "$(good Discovery)" "$(good Planning)" "$(good Test)" "$(bad Implementation unquoted-model)" "$(good Review)" "$(good Implementation)"
run
[ -z "$rf_out" ] || fail "S202 latest — an earlier unquoted Implementation superseded by a later quoted one: no finding, got: '$rf_out'"
data5 "$(good Discovery)" "$(good Planning)" "$(good Test)" "$(good Implementation)" "$(good Review)" "$(bad Implementation unquoted-model)"
run
[ "$(rf_findings)" -ge 1 ] && grep -q 'Implementation' <<<"$rf_out" || fail "S202 latest — a LATER unquoted Implementation marker is the one that counts, got: '$rf_out'"

# ---- not markers: placeholders, quoted examples ----------------------------------
data5 "$(good Discovery)" "$(good Planning)" "$(good Test)" "$(good Implementation)" "$(good Review)" \
  "The marker format is <!-- model-record: stage=… --> in prose." \
  "Also written <!-- model-record: stage=... model=<model> effort=<low|medium|high> --> as a placeholder."
run
[ -z "$rf_out" ] || fail "S202 placeholder — a stage=… placeholder is not a marker, got: '$rf_out'"
data5 "$(good Discovery)" "$(good Planning)" "$(good Test)" "$(good Implementation)" "$(good Review)" \
  "Example:${NL}\`\`\`${NL}$(bad Implementation unquoted-both)${NL}\`\`\`" \
  "Inline: \`$(bad Review unquoted-model)\`" \
  "> $(bad Test unquoted-both)"
run
[ -z "$rf_out" ] || fail "S202 quoted example — markers inside a fence, a code span or a blockquote are not counted, got: '$rf_out'"

# ---- a missing marker keeps the existing line only ----------------------------
data5 "$(good Discovery)" "$(good Planning)" "$(good Test)" "" "$(good Review)"
run
[ "$(rf_findings)" -eq 1 ] && grep -q 'no record found for stage Implementation' <<<"$rf_out" \
  || fail "S202 missing — only the existing 'no record found for stage Implementation' line, no second 'unreadable' line, got: '$rf_out'"

# ---- opt-in: the finding appears for both; role-played never ------------------------
id="process-multi-agent-roles"
optin="$(fresh_project optin)"
write_adoption "$optin/WORKFLOW-ADOPTION.md" "$id" yes
optout="$(fresh_project optout)"
write_adoption "$optout/WORKFLOW-ADOPTION.md" "$id" no
for proj in "$optin" "$optout" "$RF_PLAIN"; do
  data5 "$(good Discovery)" "$(good Planning)" "$(good Test)" "$(bad Implementation unquoted-model)" ""
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(good Planning)" "$(good Test)" "$(bad Implementation unquoted-model)"
  json_comments "$FAKE_GH_DATA/reviews-246.json" "$(good Review)"
  run "$proj"
  [ "$rf_status" -eq 0 ] || fail "S202 project ${proj##*/} — exit $rf_status"
  grep -q '^model-record:.*Implementation' <<<"$rf_out" || fail "S202 project ${proj##*/} — the finding must appear whether or not the project opted in, got: '$rf_out'"
  no_role_played "project ${proj##*/}"
done

# ---- a hand-typed quoted stage (stage="Planning") is malformed and said so ----
# (A26 amended: the malformed-marker finding covers any stage token, also an
# empty one; before, such a marker vanished silently and the stage just looked
# missing)
typed='<!-- model-record: stage="Planning" model="claude-haiku-4-5" effort="low" -->'
for _once in 1; do
  data_with Planning "$typed"
  run
  [ "$rf_status" -eq 0 ] || fail "S202 typed stage — exit $rf_status (non-blocking)"
  grep -q '^model-record:.*malformed' <<<"$rf_out" \
    || fail "S202 typed stage — a marker with a quoted or empty stage is malformed: the gate must say so (naming the real cause), got: '$rf_out'"
  grep -q 'no record found for stage Planning' <<<"$rf_out" \
    || fail "S202 typed stage — and Planning has no valid record, so the existing 'no record found' line stays, got: '$rf_out'"
  no_role_played "typed stage"
done

# ---- the collector says indeterminate for the same input (control) ----------------
mkr() { # stage form-or-good
  if [ "$2" = good ]; then good "$1"; else bad "$1" "$2"; fi
}
ce_case() { # label, planning, implementation, expected row-1, expected row-2
  ce "Closes #265" "$2
$(good Test)
$3
$(good Review)" "$(good Discovery)"
  assert_table_shape "S202 collector $1" "$ce_out"
  [ "$(row_status "$ce_out" 1)" = "$4" ] || fail "S202 collector/$1 — gate 1 should be $4, got '$(row_status "$ce_out" 1)' ($(row_evidence "$ce_out" 1))"
  [ "$(row_status "$ce_out" 2)" = "$5" ] || fail "S202 collector/$1 — gate 2 should be $5, got '$(row_status "$ce_out" 2)' ($(row_evidence "$ce_out" 2))"
}
ce_case "well-formed (control)" "$(good Planning)" "$(good Implementation)" evidenced evidenced
ce_case "unquoted Planning model" "$(bad Planning unquoted-model)" "$(good Implementation)" indeterminate evidenced
ce_case "unquoted Implementation model" "$(good Planning)" "$(bad Implementation unquoted-model)" indeterminate indeterminate

test_done

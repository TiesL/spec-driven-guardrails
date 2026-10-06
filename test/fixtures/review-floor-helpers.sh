#!/usr/bin/env bash
# test/fixtures/review-floor-helpers.sh — shared fixtures for the #392
# scenarios (S187-S193): the Review stage must be at least as capable as
# Implementation (model and effort together), not a different model.
#
# Source, don't execute. Expects test/lib.sh and
# test/fixtures/pipeline-371-helpers.sh to be sourced already and
# sandbox_create to have run. Bash 3.2: no declare -A, no mapfile.

# marker <Stage> <model> <effort> [<extra attrs>]: one model-record marker.
marker() {
  printf '<!-- model-record: stage=%s model="%s" effort="%s"%s -->' \
    "$1" "$2" "$3" "${4:+ $4}"
}

# marker_ne <Stage> <model> [<extra attrs>]: a model-record marker with NO
# effort attribute, which is what model-record-emit.sh prints from #424 on.
marker_ne() {
  printf '<!-- model-record: stage=%s model="%s"%s -->' "$1" "$2" "${3:+ $3}"
}

# para_has_all <file> <ere> [<ere> ...]: success when ONE paragraph (a run
# of non-blank lines, joined into one line) of <file> matches every ERE,
# case-insensitively. The
# unit is the paragraph so an instruction cannot be "satisfied" by words
# scattered over unrelated sections.
para_has_all() {
  local file="$1" para="" line ere ok flat
  shift
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "${line//[[:space:]]/}" ]; then
      para="$para$line"$'\n'
      continue
    fi
    if [ -n "$para" ]; then
      ok=1
      flat="${para//$'\n'/ }"
      for ere in "$@"; do grep -qiE -- "$ere" <<<"$flat" || { ok=0; break; }; done
      [ "$ok" -eq 1 ] && return 0
      para=""
    fi
  done < "$file"
  if [ -n "$para" ]; then
    ok=1
    flat="${para//$'\n'/ }"
    for ere in "$@"; do grep -qiE -- "$ere" <<<"$flat" || { ok=0; break; }; done
    [ "$ok" -eq 1 ] && return 0
  fi
  return 1
}

# rf_gate_setup: creates the fake gh (REST, data-driven) and a plain,
# not-opted-in working directory. Sets RF_BIN, RF_PLAIN and exports
# FAKE_GH_DATA.
rf_gate_setup() {
  export FAKE_GH_DATA="$SANDBOX/rf-ghdata"
  mkdir -p "$FAKE_GH_DATA"
  RF_BIN="$(fake_gh_rest "$FAKE_GH_DATA")"
  RF_PLAIN="$SANDBOX/rf-plain"
  mkdir -p "$RF_PLAIN"
}

# rf_data <marker> [<marker> ...]: PR 246 closes issue 239. Issue 239
# carries Discovery; the PR carries Planning, Test and then each given
# marker as its own comment, in order (so later ones are later rounds).
rf_data() {
  local m
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
  json_comments "$FAKE_GH_DATA/reviews-246.json"
  json_comments "$FAKE_GH_DATA/comments-239.json" "$(marker Discovery sonnet-x low)"
  local -a bodies=("$(marker Planning sonnet-x medium)" "$(marker Test sonnet-x medium)")
  for m in "$@"; do bodies+=("$m"); done
  json_comments "$FAKE_GH_DATA/comments-246.json" "${bodies[@]}"
}

# rf_gate [<cwd>] [<gate path>]: runs the gate for PR 246. Sets rf_out
# (stdout) and rf_status.
# shellcheck disable=SC2034  # read by the sourcing cases
rf_gate() {
  local cwd="${1:-$RF_PLAIN}" gate="${2:-$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh}"
  rf_out="$(cd "$cwd" && PATH="$RF_BIN:$PATH" "$gate" 246 2>/dev/null)"
  rf_status=$?
}

# rf_findings: number of non-empty lines in rf_out.
rf_findings() {
  if [ -z "$rf_out" ]; then echo 0; else printf '%s\n' "$rf_out" | grep -c .; fi
}

#!/usr/bin/env bash
# test/fixtures/ce-review-helpers.sh — a recording fake gh for
# compliance-evidence.sh gate 2 (PR 279, closing issues #265/#266), shared by
# S194/S195. Source after sandbox_create and test/compliance-evidence-fixture.sh.
# A marker containing a newline is sent as the \001 sentinel the collector
# decodes back into a newline (a real multi-line comment body).
# Bash 3.2.

SHA="cccccccccccccccccccccccccccccccccccccccc"

# emit <body-var-name>: the fake-gh lines that print each marker of a
# newline-separated list as a TEXT record, or fail when the list is FAIL.
emit() {
  local list="$1" m
  if [ "$list" = "FAIL" ]; then
    printf '    echo "simulated failure" >&2\n    exit 1 ;;\n'
    return
  fi
  if [ -n "$list" ]; then
    while IFS= read -r m; do
      m="${m//$'\n'/$'\001'}"
      [ -n "$m" ] && printf "    printf 'TEXT\\\\t%%s\\\\n' '%s'\n" "$m"
    done <<<"$list"
  fi
  printf '    exit 0 ;;\n'
}

# ce <title> <pr-comment markers|FAIL> <issue-265 markers|FAIL> [<issue-266 markers|FAIL>]
# Runs the collector; sets ce_out.
ce() {
  local title="$1" prc="$2" c265="$3" c266="${4-}"
  {
    echo 'case "$*" in'
    echo '  __CALL_A__)'
    printf "    printf 'HEAD\\\\t%s\\\\n'\n" "$SHA"
    echo "    printf 'STATE\\tOPEN\\n'"
    printf "    printf 'TITLE\\\\t%%s\\\\n' '%s'\n" "$title"
    echo "    printf 'TEXT\\t\\n'"
    echo '    exit 0 ;;'
    echo '  __CALL_A_COMMENTS__)'
    emit "$prc"
    echo '  __CALL_A_REVIEWS__)'
    echo "    printf ''"
    echo '    exit 0 ;;'
    echo '  __CALL_B__)'
    printf "    printf 'check\\\\tSUCCESS\\\\tpass\\\\n'\n"
    echo '    exit 0 ;;'
    echo '  __CALL_C265__)'
    emit "$c265"
    if [ -n "$c266" ]; then
      echo '  __CALL_C266__)'
      emit "$c266"
    fi
    echo 'esac'
    echo 'exit 1'
  } | run_build_fake_gh "$SHA"
  local bin
  bin="$(cat "$FAKEGH_OUT")"
  ce_out="$(PATH="$bin:$PATH" "$script" 279 2>/dev/null)"
}

mk() { # stage model effort [extra]
  printf '<!-- model-record: stage=%s model="%s" effort="%s"%s -->' "$1" "$2" "$3" "${4:+ $4}"
}
FB='floor-basis="stronger model, the diff is a mechanical rename"'

# check <label> <want status> <pr comment markers> [issue265 [issue266 [title]]]
check() {
  local label="$1" want="$2" prc="$3" c265="${4-}" c266="${5-}" title="${6:-Closes #265}"
  ce "$title" "$prc" "$c265" "$c266"
  assert_table_shape "${CE_ID} $label" "$ce_out"
  got="$(row_status "$ce_out" 2)"
  [ "$got" = "$want" ] || fail "${CE_ID} — $label: gate 2 should be '$want', got '$got' ($(row_evidence "$ce_out" 2))"
}


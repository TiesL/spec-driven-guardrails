#!/usr/bin/env bash
# S376 — pipeline-override.sh posts one valid, live record per scope, and refuses everything else before posting.
# Covers: F38
#
# Issue #564, AC1-AC5, AC9, AC10 and the AC2 mutation arms. Seam: the script
# itself, run with an injected `gh` (PIPELINE_OVERRIDE_GH, one executable
# path) that records argv and stdin and never touches the network. The
# record is read back with the gate's own reader (lib/model-record.sh
# rec_scan / rec_field), so the grammar is not restated here.
#
# Mutation arms need two marked regions in pipeline-override.sh (a contract
# between this test and the script; the S274 pattern of editing a scratch copy):
#   # BEGIN field-checks ... # END field-checks   the per-field and scope checks
#   # BEGIN read-back    ... # END read-back      the rec_scan/rec_field net
# Each region is replaced by a `:` line in a sandbox copy. A region that is
# missing fails the test (the arm cannot run), and a mutant that does not
# let a hostile value reach the stub fails with "mutation not detected".
#
# Falsifiers: sanitizing or trimming instead of refusing, truncating instead
# of refusing, posting before validating, one comment per scope, a default or
# environment fallback for decided-by/reason, a dry-run that calls gh, equal
# exit codes for different failures, a net that only exists in the pre-checks.

set -uo pipefail
# shellcheck disable=SC2016,SC2059,SC2015
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../../lib/model-record.sh disable=SC1091
. "$TEST_REPO_ROOT/lib/model-record.sh"

SCRIPT="$TEST_REPO_ROOT/pipeline-override.sh"

sandbox_create
trap sandbox_destroy EXIT

export STUB_DIR="$SANDBOX/stub"
mkdir -p "$STUB_DIR"
STUB="$STUB_DIR/gh"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/calls"
cat >> "$STUB_DIR/stdin"
if [ -n "${STUB_FAIL:-}" ]; then
  echo "stub gh: boom" >&2
  exit "$STUB_FAIL"
fi
echo "https://github.example.invalid/o/r/issues/42#issuecomment-1"
STUBEOF
chmod +x "$STUB"

# run_po [args...]: runs $PO (default the real script) with the stub gh.
# Sets po_rc; stdout/stderr/stdin of the call are files under $SANDBOX/run.
PO="$SCRIPT"
run_po() {
  rm -f "$STUB_DIR/calls" "$STUB_DIR/stdin"
  mkdir -p "$SANDBOX/run"
  PIPELINE_OVERRIDE_GH="${GH_UNDER_TEST:-$STUB}" "$PO" "$@" > "$SANDBOX/run/out" 2> "$SANDBOX/run/err"
  po_rc=$?
}
calls() { if [ -f "$STUB_DIR/calls" ]; then wc -l < "$STUB_DIR/calls" | tr -d ' '; else echo 0; fi; }
errlines() { awk 'END { print NR }' "$SANDBOX/run/err"; }
posted() { cat "$STUB_DIR/stdin" 2>/dev/null; }

# refuse <label> <field> args...: the AC2/AC3 refusal contract.
refuse() {
  local label="$1" field="$2"
  shift 2
  run_po "$@"
  [ "$po_rc" -eq 2 ] || fail "S376/$label — expected exit 2, got $po_rc (stderr: $(head -c 300 "$SANDBOX/run/err"))"
  [ ! -s "$SANDBOX/run/out" ] || fail "S376/$label — a refusal printed on stdout: $(head -c 300 "$SANDBOX/run/out")"
  [ "$(errlines)" = 1 ] || fail "S376/$label — expected exactly one stderr line, got $(errlines)"
  grep -qiF -- "$field" "$SANDBOX/run/err" || fail "S376/$label — stderr does not name the field '$field': $(head -c 300 "$SANDBOX/run/err")"
  [ "$(calls)" = 0 ] || fail "S376/$label — gh was called for a refused input"
}

# --- 0. The script exists and is executable ---------------------------------
[ -x "$SCRIPT" ] || fail "S376/0 — pipeline-override.sh is missing or not executable at the repo root"

# --- 1. AC1: one comment, one record line per scope, in order ----------------
run_po 42 --scope skip=Planning --scope skip=Test --decided-by TiesL --reason 'only specs'
[ "$po_rc" -eq 0 ] || fail "S376/1 — valid call: expected exit 0, got $po_rc (stderr: $(head -c 300 "$SANDBOX/run/err"))"
[ "$(calls)" = 1 ] || fail "S376/1 — gh must be called exactly once, was called $(calls) times"
[ "$(cat "$STUB_DIR/calls" 2>/dev/null)" = "issue comment 42 --body-file -" ] \
  || fail "S376/1 — wrong gh call shape: '$(cat "$STUB_DIR/calls" 2>/dev/null)'"
body="$(posted)"
n_lines="$(awk 'END { print NR }' "$STUB_DIR/stdin" 2>/dev/null)"
[ "${n_lines:-0}" = 4 ] || fail "S376/1 — two scopes must give 4 lines (2 records, blank, 1 text), got ${n_lines:-0}"
l1="$(sed -n 1p "$STUB_DIR/stdin" 2>/dev/null)"; l2="$(sed -n 2p "$STUB_DIR/stdin" 2>/dev/null)"
l3="$(sed -n 3p "$STUB_DIR/stdin" 2>/dev/null)"; l4="$(sed -n 4p "$STUB_DIR/stdin" 2>/dev/null)"
case "$l1" in '<!--'*) : ;; *) fail "S376/1 — line 1 must start in column 0 with a record, got '$l1'" ;; esac
case "$l2" in '<!--'*) : ;; *) fail "S376/1 — line 2 must start in column 0 with a record, got '$l2'" ;; esac
[ -z "$l3" ] || fail "S376/1 — line 3 must be blank, got '$l3'"
case "$l4" in '') fail "S376/1 — line 4 (plain text) is empty" ;; '<'*) fail "S376/1 — line 4 must be plain text, not a tag: '$l4'" ;; esac
case "$l4" in *'"only specs"'*) : ;; *) fail "S376/1 — the plain-text line must quote the reason: '$l4'" ;; esac
scan="$(rec_scan pipeline-override "$body")"
ok_rows="$(printf '%s\n' "$scan" | awk -F'\t' '$2 == "ok"' | awk 'END { print NR }')"
all_rows="$(printf '%s' "$scan" | awk 'END { print NR }')"
[ "$ok_rows" = 2 ] && [ "$all_rows" = 2 ] || fail "S376/1 — rec_scan must see exactly 2 ok rows, saw $ok_rows ok of $all_rows: $scan"
[ "$(rec_field "$l1" scope)" = skip=Planning ] || fail "S376/1 — first record scope is '$(rec_field "$l1" scope)', want skip=Planning (order given)"
[ "$(rec_field "$l2" scope)" = skip=Test ] || fail "S376/1 — second record scope is '$(rec_field "$l2" scope)', want skip=Test"
[ "$(rec_field "$l1" decided-by)" = TiesL ] && [ "$(rec_field "$l2" decided-by)" = TiesL ] || fail "S376/1 — decided-by not TiesL on both records"
[ "$(rec_field "$l1" reason)" = 'only specs' ] && [ "$(rec_field "$l2" reason)" = 'only specs' ] || fail "S376/1 — reason not 'only specs' on both records"
# success message: echoes the reason (AC10) and says the closing keyword is needed (AC9)
all_out="$(cat "$SANDBOX/run/out" "$SANDBOX/run/err")"
case "$all_out" in *'only specs'*) : ;; *) fail "S376/1 — the success message must echo the recorded reason (AC10): $all_out" ;; esac
case "$all_out" in *'Closes #42'*) : ;; *) fail "S376/1 — the success message must say the PR needs 'Closes #42' (AC9): $all_out" ;; esac
case "$all_out" in *'issuecomment-1'*) : ;; *) fail "S376/1 — gh's stdout (the comment URL) must be passed through: $all_out" ;; esac

# single-session alone: exactly one record line
run_po 7 --scope single-session --decided-by TiesL --reason 'one session please'
[ "$po_rc" -eq 0 ] || fail "S376/1b — single-session: exit $po_rc"
[ "$(awk 'END { print NR }' "$STUB_DIR/stdin" 2>/dev/null)" = 3 ] || fail "S376/1b — one scope must give 3 lines (record, blank, text)"
[ "$(rec_field "$(sed -n 1p "$STUB_DIR/stdin" 2>/dev/null)" scope)" = single-session ] || fail "S376/1b — scope is not single-session"

# --- 1c. values that pass are posted byte for byte --------------------------
byte_for_byte() { # label decided-by reason
  run_po 42 --scope skip=Test --decided-by "$2" --reason "$3"
  [ "$po_rc" -eq 0 ] || { fail "S376/$1 — a legal value was refused: $(head -c 300 "$SANDBOX/run/err")"; return; }
  local line
  line="$(sed -n 1p "$STUB_DIR/stdin" 2>/dev/null)"
  [ "$(rec_field "$line" reason)" = "$3" ] || fail "S376/$1 — reason was altered: '$(rec_field "$line" reason)'"
  [ "$(rec_field "$line" decided-by)" = "$2" ] || fail "S376/$1 — decided-by was altered: '$(rec_field "$line" decided-by)'"
}
byte_for_byte 1c-spaces "Ties L" '  spaced out  '
byte_for_byte 1c-shellish TiesL 'a `tick` $HOME | & \ ~~~ ``` ok'
byte_for_byte 1c-utf8 TiesL 'caf'$'\xc3\xa9'' '$'\xe6\x97\xa5\xe6\x9c\xac'
byte_for_byte 1c-max-reason TiesL "$(printf 'a%.0s' $(seq 1 1000))"
byte_for_byte 1c-max-decided-by "$(printf 'b%.0s' $(seq 1 100))" 'fine'
byte_for_byte 1c-max-bytes-utf8 TiesL "$(printf '\xc3\xa9%.0s' $(seq 1 500))"

# --- 2. AC2: grammar refusals, one subcase per class -------------------------
V=(--scope skip=Planning)
ls=$'\xe2\x80\xa8'
for f in reason decided-by; do
  rest() { if [ "$f" = reason ]; then echo "--decided-by TiesL --reason"; else echo "--reason fine --decided-by"; fi; }
  while IFS='|' read -r name val; do
    # val uses printf escapes
    v="$(printf "$val")"
    # shellcheck disable=SC2046
    refuse "2-$f-$name" "--$f" 42 "${V[@]}" $(rest) "$v"
  done <<'CLASSES'
dquote|a\x22b
lt|a<b
gt|a>b
tab|a\tb
newline|a\nb
soh|a\x01b
del|a\x7fb
c1|a\xc2\x85b
ls|a\xe2\x80\xa8b
ps|a\xe2\x80\xa9b
bidi-rlo|a\xe2\x80\xaeb
bidi-lri|a\xe2\x81\xa6b
CLASSES
done
# blank values and length, with explicit quoting
for f in reason decided-by; do
  for blank in '' ' ' '   '; do
    if [ "$f" = reason ]; then refuse "2-$f-blank(${#blank})" "--reason" 42 "${V[@]}" --decided-by TiesL --reason "$blank"
    else refuse "2-$f-blank(${#blank})" "--decided-by" 42 "${V[@]}" --reason fine --decided-by "$blank"; fi
  done
done
refuse 2-reason-1001-bytes --reason 42 "${V[@]}" --decided-by TiesL --reason "$(printf 'a%.0s' $(seq 1 1001))"
refuse 2-reason-1002-bytes-501-chars --reason 42 "${V[@]}" --decided-by TiesL --reason "$(printf '\xc3\xa9%.0s' $(seq 1 501))"
refuse 2-decided-by-101-bytes --decided-by 42 "${V[@]}" --reason fine --decided-by "$(printf 'b%.0s' $(seq 1 101))"
for s in skip=Deploy skip= single skip=planning single-sessions ''; do
  refuse "2-scope($s)" "--scope" 42 --scope "$s" --decided-by TiesL --reason fine
done
refuse 2-scope-duplicate "--scope" 42 --scope skip=Test --scope skip=Test --decided-by TiesL --reason fine
refuse 2-scope-mixed "--scope" 42 --scope single-session --scope skip=Test --decided-by TiesL --reason fine
refuse 2-scope-mixed-reversed "--scope" 42 --scope skip=Test --scope single-session --decided-by TiesL --reason fine
refuse 2-scope-none "--scope" 42 --decided-by TiesL --reason fine
for i in 0 abc -1 07; do refuse "2-issue($i)" issue "$i" --scope skip=Test --decided-by TiesL --reason fine; done
refuse 2-issue-empty issue '' --scope skip=Test --decided-by TiesL --reason fine
refuse 2-issue-missing issue --scope skip=Test --decided-by TiesL --reason fine
refuse 2-unknown-flag "--bogus" 42 --scope skip=Test --decided-by TiesL --reason fine --bogus
refuse 2-extra-positional "43" 42 43 --scope skip=Test --decided-by TiesL --reason fine
refuse 2-repeated-reason "--reason" 42 --scope skip=Test --decided-by TiesL --reason a --reason b
refuse 2-repeated-decided-by "--decided-by" 42 --scope skip=Test --decided-by TiesL --decided-by X --reason a
refuse 2-swallowed-flag "--reason" 42 --scope skip=Test --decided-by TiesL --reason --dry-run
refuse 2-flag-without-value "--reason" 42 --scope skip=Test --decided-by TiesL --reason

# --- 3. AC3: no decision is invented -----------------------------------------
refuse 3-no-decided-by "--decided-by" 42 --scope skip=Test --reason 'words'
refuse 3-no-reason "--reason" 42 --scope skip=Test --decided-by TiesL
DECIDED_BY=TiesL PIPELINE_OVERRIDE_REASON='from the env' USER=TiesL refuse 3-env-fallback-decided-by "--decided-by" 42 --scope skip=Test --reason 'words'
DECIDED_BY=TiesL PIPELINE_OVERRIDE_REASON='from the env' USER=TiesL refuse 3-env-fallback-reason "--reason" 42 --scope skip=Test --decided-by TiesL
DECIDED_BY=TiesL PIPELINE_OVERRIDE_REASON='from the env' USER=TiesL refuse 3-env-fallback-both "--decided-by" 42 --scope skip=Test

# --- 4. AC4: dry-run ----------------------------------------------------------
run_po 42 --scope skip=Planning --scope skip=Test --decided-by TiesL --reason 'only specs'
cp "$STUB_DIR/stdin" "$SANDBOX/real-body" 2>/dev/null || : > "$SANDBOX/real-body"
run_po 42 --scope skip=Planning --scope skip=Test --decided-by TiesL --reason 'only specs' --dry-run
[ "$po_rc" -eq 0 ] || fail "S376/4 — dry-run: exit $po_rc"
cmp -s "$SANDBOX/run/out" "$SANDBOX/real-body" && [ -s "$SANDBOX/real-body" ] || fail "S376/4 — dry-run stdout must be exactly the body a real run posts"
[ "$(errlines)" = 1 ] && grep -qxF 'dry-run: nothing posted' "$SANDBOX/run/err" || fail "S376/4 — dry-run stderr must be the single line 'dry-run: nothing posted', got: $(cat "$SANDBOX/run/err")"
[ "$(calls)" = 0 ] || fail "S376/4 — dry-run called gh"
bundle="$(rec_scan_bundle pipeline-override "$(cat "$SANDBOX/run/out")"$'\036')"
[ "$(printf '%s\n' "$bundle" | awk -F'\t' '$2 == "ok"' | awk 'END { print NR }')" = 2 ] || fail "S376/4 — the dry-run body must read as 2 ok records through rec_scan_bundle: $bundle"
STUB_FAIL=1 run_po 42 --scope skip=Test --decided-by TiesL --reason 'x' --dry-run
[ "$po_rc" -eq 0 ] && [ "$(calls)" = 0 ] || fail "S376/4 — dry-run with a failing gh: exit $po_rc, calls $(calls)"
GH_UNDER_TEST="$SANDBOX/no-such-gh" run_po 42 --scope skip=Test --decided-by TiesL --reason 'x' --dry-run
[ "$po_rc" -eq 0 ] || fail "S376/4 — dry-run needs no gh at all, got exit $po_rc"
refuse 4-dry-run-invalid --reason 42 --scope skip=Test --decided-by TiesL --reason 'a"b' --dry-run
refuse 4-dry-run-missing --decided-by 42 --scope skip=Test --reason 'words' --dry-run

# --- 5. AC5: distinct exit codes ----------------------------------------------
STUB_FAIL=1 run_po 42 --scope skip=Test --decided-by TiesL --reason 'x'
[ "$po_rc" -eq 4 ] || fail "S376/5 — gh failing must give exit 4, got $po_rc"
[ "$(calls)" = 1 ] || fail "S376/5 — gh must have been called once"
grep -qF 'stub gh: boom' "$SANDBOX/run/err" || fail "S376/5 — gh's stderr must be passed through"
grep -qiF 'nothing recorded' "$SANDBOX/run/err" || fail "S376/5 — stderr must say 'nothing recorded'"
GH_UNDER_TEST="$SANDBOX/no-such-gh" run_po 42 --scope skip=Test --decided-by TiesL --reason 'x'
[ "$po_rc" -eq 3 ] || fail "S376/5 — a missing gh path must give exit 3, got $po_rc"
: > "$SANDBOX/not-exec"
GH_UNDER_TEST="$SANDBOX/not-exec" run_po 42 --scope skip=Test --decided-by TiesL --reason 'x'
[ "$po_rc" -eq 3 ] || fail "S376/5 — a non-executable gh must give exit 3, got $po_rc"
GH_UNDER_TEST="no-such-gh-command-xyz" run_po 42 --scope skip=Test --decided-by TiesL --reason 'x'
[ "$po_rc" -eq 3 ] || fail "S376/5 — a gh name not on PATH must give exit 3, got $po_rc"

# a sandbox copy of the repo: the script next to its lib (found from its own real directory)
mkcopy() { # dir
  rm -rf "$1"
  mkdir -p "$1"
  cp -R "$TEST_REPO_ROOT/lib" "$1/lib"
  cp "$SCRIPT" "$1/pipeline-override.sh" 2>/dev/null || return 1
  chmod +x "$1/pipeline-override.sh"
}
mkcopy "$SANDBOX/copy-nolib" || fail "S376/5 — cannot copy pipeline-override.sh (missing)"
rm -rf "$SANDBOX/copy-nolib/lib"
PO="$SANDBOX/copy-nolib/pipeline-override.sh" run_po 42 --scope skip=Test --decided-by TiesL --reason 'x'
[ "$po_rc" -eq 3 ] && [ "$(calls)" = 0 ] || fail "S376/5 — missing lib/model-record.sh must give exit 3 without a gh call, got exit $po_rc, calls $(calls)"
# drift: a stricter grammar than the script builds for. The net must refuse (exit 1), gh must not be called.
mkcopy "$SANDBOX/copy-strict" || fail "S376/5 — cannot copy pipeline-override.sh (missing)"
printf '\nPO_STRICT_ERE=%s\n' "'^never-matches\$'" >> "$SANDBOX/copy-strict/lib/model-record.sh"
PO="$SANDBOX/copy-strict/pipeline-override.sh" run_po 42 --scope skip=Test --decided-by TiesL --reason 'x'
[ "$po_rc" -eq 1 ] || fail "S376/5 — a body the grammar does not read back must give exit 1, got $po_rc"
[ "$(calls)" = 0 ] || fail "S376/5 — drift: gh was called although the read-back failed"
grep -qiF 'internal check failed' "$SANDBOX/run/err" || fail "S376/5 — stderr must say 'internal check failed'"

# --- 6. AC9/AC10/AC8: usage text ---------------------------------------------
PO="$SCRIPT" run_po --help
usage="$(cat "$SANDBOX/run/out" "$SANDBOX/run/err")"
[ "$(calls)" = 0 ] || fail "S376/6 — --help called gh"
grep -qi 'single quote' <<<"$usage" || fail "S376/6 — usage text must tell the caller to pass --reason in single quotes (AC10)"
grep -qF 'Closes #' <<<"$usage" || fail "S376/6 — usage text must say the gate sees the record only via a closing keyword 'Closes #<issue>' (AC9)"
grep -qi 'before the first commit' <<<"$usage" || fail "S376/6 — usage text must say to post before the first commit or PR (AC8)"

# --- 7. Mutation arms (AC2): the tests above must go red without the checks ---
# strip <file> <region>: replace "# BEGIN <region>" .. "# END <region>" by ':'
strip() {
  awk -v r="$2" '
    $0 ~ "# BEGIN " r { print ":"; skip = 1; found = 1; next }
    $0 ~ "# END " r { skip = 0; next }
    !skip { print }
    END { exit found ? 0 : 3 }' "$1" > "$1.new" && mv "$1.new" "$1" && chmod +x "$1"
}
mutant() { # name regions...
  local name="$1" r
  shift
  mkcopy "$SANDBOX/mut-$name" || { fail "S376/7 — cannot copy pipeline-override.sh (missing)"; return 1; }
  for r in "$@"; do
    strip "$SANDBOX/mut-$name/pipeline-override.sh" "$r" || { fail "S376/7 — region '$r' markers not found in pipeline-override.sh, mutation arm cannot run"; return 1; }
  done
  bash -n "$SANDBOX/mut-$name/pipeline-override.sh" || { fail "S376/7 — mutant '$name' does not parse"; return 1; }
}
hostile_args=(
  '--reason|a"b'
  '--reason|a<b'
  '--decided-by|x>y'
  '--reason|two'$'\n''lines'
  "--reason|a${ls}b"
)
# baseline: the mutant with nothing removed behaves like the script
if mutant none; then
  PO="$SANDBOX/mut-none/pipeline-override.sh" run_po 42 --scope skip=Test --decided-by TiesL --reason 'ok'
  [ "$po_rc" -eq 0 ] && [ "$(calls)" = 1 ] || fail "S376/7 — an unmutated copy does not post a valid record (exit $po_rc)"
fi
# (a) only the per-field checks removed: the read-back still holds (exit 1, nothing posted)
if mutant a field-checks; then
  PO="$SANDBOX/mut-a/pipeline-override.sh" run_po 42 --scope skip=Test --decided-by TiesL --reason 'a"b'
  { [ "$po_rc" -eq 1 ] && [ "$(calls)" = 0 ]; } || fail "S376/7a — without the field checks the read-back must still refuse (exit 1, no gh call); got exit $po_rc, calls $(calls)"
fi
# (b) only the read-back removed: the field checks still refuse (exit 2, nothing posted)
if mutant b read-back; then
  for h in "${hostile_args[@]}"; do
    flag="${h%%|*}"; val="${h#*|}"
    if [ "$flag" = --reason ]; then set -- --decided-by TiesL --reason "$val"; else set -- --reason fine --decided-by "$val"; fi
    PO="$SANDBOX/mut-b/pipeline-override.sh" run_po 42 --scope skip=Test "$@"
    { [ "$po_rc" -eq 2 ] && [ "$(calls)" = 0 ]; } || fail "S376/7b — without the read-back the field checks must still refuse; got exit $po_rc, calls $(calls) for '$val'"
  done
fi
# (c) both removed: hostile values must reach the stub, or this test cannot see a dropped validation
if mutant c field-checks read-back; then
  for h in "${hostile_args[@]}"; do
    flag="${h%%|*}"; val="${h#*|}"
    if [ "$flag" = --reason ]; then set -- --decided-by TiesL --reason "$val"; else set -- --reason fine --decided-by "$val"; fi
    PO="$SANDBOX/mut-c/pipeline-override.sh" run_po 42 --scope skip=Test "$@"
    [ "$(calls)" = 1 ] || fail "S376/7c — mutation not detected: with validation removed, the hostile value '$val' did not reach the gh stub (exit $po_rc)"
  done
  PO="$SANDBOX/mut-c/pipeline-override.sh" run_po 42 --scope skip=Deploy --decided-by TiesL --reason 'ok'
  [ "$(calls)" = 1 ] || fail "S376/7c — mutation not detected: scope skip=Deploy did not reach the gh stub without the checks"
fi

test_done

#!/usr/bin/env bash
# S375 — ./check shellchecks the real tree once and runs the suite with the nested shellcheck skipped.
# Covers: F38
#
# Issue #563, AC4. Seam: the real `check` and the real `test/run.sh` copied
# into a sandbox project of three trivial cases, with a recording fake
# `shellcheck` first on PATH. Cheap by construction (no 17-minute run); the
# full-size equivalent is the CI-log verification in AC4 (`check: shellcheck`
# once, `Tests: N passed` with N = number of test/cases files).
#
# Falsifiers: the suite runs without CHECK_SKIP_SHELLCHECK (every nested
# `check` would shellcheck the whole tree again), the variable leaking in
# before the outer pass (the real tree would not be shellchecked at all), a
# case dropped from the run, or a second outer pass.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

proj="$SANDBOX/proj"
mkdir -p "$proj/test/cases" "$proj/settings" "$SANDBOX/bin"
cp "$TEST_REPO_ROOT/check" "$proj/check"
cp "$TEST_REPO_ROOT/test/run.sh" "$proj/test/run.sh"
echo '{}' > "$proj/settings/session-hooks.json"

# Each case records what the suite's environment says about the skip.
for n in a b c; do
  cat > "$proj/test/cases/${n}_probe.sh" <<PROBE
#!/usr/bin/env bash
echo "\${CHECK_SKIP_SHELLCHECK:-unset}" > "$SANDBOX/seen_$n"
exit 0
PROBE
done
chmod +x "$proj/check" "$proj/test/run.sh"

# Fake shellcheck: logs each script it is asked to check, always succeeds.
cat > "$SANDBOX/bin/shellcheck" <<FAKE
#!/usr/bin/env bash
echo "\${!#}" >> "$SANDBOX/shellcheck_calls"
exit 0
FAKE
chmod +x "$SANDBOX/bin/shellcheck"

out="$SANDBOX/out"
( unset CHECK_SKIP_SHELLCHECK; PATH="$SANDBOX/bin:$PATH" "$proj/check" ) > "$out" 2>&1
status=$?

[ "$status" -eq 0 ] || fail "check on the sandbox project exited $status: $(tail -5 "$out")"

# Outer pass: announced once, and it really checked the real tree.
passes="$(grep -c '^check: shellcheck$' "$out")"
[ "$passes" -eq 1 ] || fail "expected the outer 'check: shellcheck' pass exactly once, saw $passes"
for script in check test/run.sh test/cases/a_probe.sh; do
  grep -qx "$proj/$script" "$SANDBOX/shellcheck_calls" 2>/dev/null \
    || fail "outer shellcheck pass did not cover $script (the variable must not be set before step 4)"
done

# Every test still runs: Tests: N passed with N = files in test/cases.
files="$(find "$proj/test/cases" -name '*.sh' | wc -l | tr -d ' ')"
grep -qx "Tests: $files passed\\." "$out" || fail "expected 'Tests: $files passed.' in output"

# The suite ran with the nested shellcheck skipped.
for n in a b c; do
  seen="$(cat "$SANDBOX/seen_$n" 2>/dev/null || echo missing)"
  [ "$seen" = "1" ] || fail "case $n saw CHECK_SKIP_SHELLCHECK=$seen, expected 1 (nested check would shellcheck the whole tree again)"
done

# Static pin on the command line itself, independent of the fixture.
# shellcheck disable=SC2016  # the pattern is a literal "$target", not an expansion
grep -Eq '^[[:space:]]*(if ! )?CHECK_SKIP_SHELLCHECK=1 "\$target/test/run\.sh"' "$TEST_REPO_ROOT/check" \
  || fail "check step 5 does not run \"\$target/test/run.sh\" with CHECK_SKIP_SHELLCHECK=1 on its own command line"

test_done

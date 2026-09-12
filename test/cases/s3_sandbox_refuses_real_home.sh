#!/usr/bin/env bash
# S3 — The test sandbox refuses to run with the real HOME.
# Covers: F1

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Given: a test whose sandbox setup did not redirect HOME.
# When/Then: the guard refuses, with an explicit message.
output="$(HOME="$TEST_REAL_HOME" sandbox_guard 2>&1)"
status=$?

if [ "$status" -eq 0 ]; then
  fail "S3 — sandbox_guard let the real HOME through"
fi
assert_contains "S3" "ABORTED" "$output"
assert_contains "S3" "real home" "$output"

# And an empty HOME is just as much not a sandbox.
output_empty="$(HOME="" sandbox_guard 2>&1)"
status_empty=$?
if [ "$status_empty" -eq 0 ]; then
  fail "S3 — sandbox_guard let an empty HOME through"
fi
assert_contains "S3 (empty HOME)" "ABORTED" "$output_empty"

# And: nothing was written outside the temporary directory. The guard runs
# before every write action, so a refused setup leaves no traces.
sandbox_create
trap sandbox_destroy EXIT
if [ "$HOME" = "$TEST_REAL_HOME" ]; then
  fail "S3 — sandbox_create did not redirect HOME"
fi
case "$HOME" in
  "$SANDBOX"*) ;;
  *) fail "S3 — HOME does not point into the sandbox: $HOME" ;;
esac

# The And clause was so far inferred from the control flow rather than
# demonstrated. A canary proves it: write to $HOME and confirm the file ends
# up in the sandbox and not in the real home. The check on the real home is
# purely read-only - by definition we don't write there.
canary="canary-$$-$(date +%s)"
echo "sandbox" > "$HOME/$canary"

if [ ! -e "$SANDBOX/home/$canary" ]; then
  fail "S3 — the write to \$HOME did not end up in the sandbox"
fi
if [ -e "$TEST_REAL_HOME/$canary" ]; then
  fail "S3 — something was written to the real home ($TEST_REAL_HOME/$canary)"
fi

test_done

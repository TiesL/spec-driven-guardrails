#!/usr/bin/env bash
# S710 — The behavior runner stays direct and refuses an inherited proxy URL (#707; AC11, runner half)
# Covers: F75
#
# Seam: the stub CLAUDE_BIN and fixture repository of S315/S316
# (test/fixtures/behavior-runner-helpers.sh); the stub's call log. Entry
# points that start CLAUDE_BIN, enumerated from orchestrator_diff.py: `run`,
# `run --baseline` and `run --calibrate` (check-scenarios and stamp-check
# start nothing).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/behavior-runner-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/behavior-runner-helpers.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

PY="$TEST_REPO_ROOT/test/behavior/orchestrator_diff.py"

bf_init "$SANDBOX/bf"
bf_case 1 aa stop 0 stop,stop,stop stop,stop,stop stop,stop,stop
bf_build

entry() { # <name> -> runner args
  case "$1" in
    run) echo "--runs 3" ;;
    baseline) echo "--runs 3 --baseline" ;;
    calibrate) echo "--runs 3 --calibrate --mutant-rule OR40" ;;
  esac
}

for value in http://127.0.0.1:8787/w/claude https://api.anthropic.com.evil.example https://api.anthropic.com/ ''; do
  for ep in run baseline calibrate; do
    bf_reset
    bf_case 1 aa stop 0 stop,stop,stop stop,stop,stop stop,stop,stop
    bf_build
    export ANTHROPIC_BASE_URL="$value"
    # shellcheck disable=SC2046
    bf_run $(entry "$ep")
    unset ANTHROPIC_BASE_URL
    label="S710/[$value]/$ep"
    [ "$bf_status" != 0 ] || fail "$label — the runner did not refuse"
    [ ! -e "$STUB_DIR/n" ] || fail "$label — the stub was called $(cat "$STUB_DIR/n") time(s) before the refusal"
    grep -q ANTHROPIC_BASE_URL <<<"$bf_err" || fail "$label — the message does not name ANTHROPIC_BASE_URL: $bf_err"
    grep -qiE 'refus' <<<"$bf_err" && grep -qi 'routed' <<<"$bf_err" \
      || fail "$label — the message does not say the run is refused because it would be routed: $bf_err"
    git -C "$BF_REPO" checkout -q -- . 2>/dev/null
  done
done

# Controls: unset and exactly first-party run as before (same stub arguments).
for value in UNSET https://api.anthropic.com; do
  for ep in run baseline calibrate; do
    bf_reset
    bf_case 1 aa stop 0 stop,stop,stop stop,stop,stop stop,stop,stop
    bf_build
    [ "$value" = UNSET ] || export ANTHROPIC_BASE_URL="$value"
    # shellcheck disable=SC2046
    bf_run $(entry "$ep")
    unset ANTHROPIC_BASE_URL
    label="S710/control-$value/$ep"
    [ -e "$STUB_DIR/n" ] || fail "$label — the stub was never called (exit $bf_status, $bf_err)"
    case "$bf_err" in *ANTHROPIC_BASE_URL*) fail "$label — refused: $bf_err" ;; esac
    # The system-prompt file lives in a fresh temporary directory per run:
    # compare its name, not its directory.
    python3 -I - "$STUB_DIR/call-1.args" "$SANDBOX/args-$ep-$(printf '%s' "$value" | tr -c 'a-zA-Z' _)" <<'PY'
import os, sys
args = open(sys.argv[1], "rb").read().split(b"\0")
args = [os.path.basename(a) if i and args[i - 1] == b"--system-prompt-file" else a for i, a in enumerate(args)]
open(sys.argv[2], "wb").write(b"\0".join(args))
PY
  done
  rm -f "$BF_REPO/$BF_STAMP_REL"
done
for ep in run baseline calibrate; do
  cmp -s "$SANDBOX/args-$ep-UNSET" "$SANDBOX/args-$ep-https___api_anthropic_com" \
    || fail "S710/control/$ep — the stub arguments differ between unset and first-party"
done

# --- the runner never routes itself ---------------------------------------------------
grep -q 'route-child' "$PY" && fail "S710 — orchestrator_diff.py mentions route-child.sh"
mkdir -p "$SANDBOX/runner-only/x"
git -C "$SANDBOX/runner-only" init -q -b main
cp "$PY" "$SANDBOX/runner-only/x/runner.py"
git -C "$SANDBOX/runner-only" add x/runner.py
out="$(rc_route_scan "$SANDBOX/runner-only")" || fail "S710 — orchestrator_diff.py assigns a route: $out"

test_done

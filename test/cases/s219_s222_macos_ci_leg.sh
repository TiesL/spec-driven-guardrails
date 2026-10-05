#!/usr/bin/env bash
# S219, S222 — The macOS CI leg lives in its own workflow file, pinned whole,
# and the Linux job in ci.yml is as it was (#422, slice V1 of #411, A35c D1-D3,
# AC1).
# Covers: F43
#
# S219 does not parse YAML (A35c D2, hardened by A35d). Two rules, in order.
# D1, byte alphabet: `.github/workflows/macos.yml` may hold only LF (0x0A) and
# printable ASCII (0x20-0x7E); `LC_ALL=C grep -an '[^ -~]'` finding anything
# is red. That makes grep's idea of a line the same as YAML's (a CR, NEL or LS
# cannot hide a key inside a "comment"), and it excludes tab, CR, form feed,
# NUL, a BOM and every non-ASCII byte. D2, header-only comments: only the
# leading run of blank and full-line-comment lines (the header, before
# `name:`) is stripped, with
# `LC_ALL=C awk 'started || !/^[[:space:]]*(#|$)/ { started = 1; print }'`;
# from `name: CI macOS` to the end the file must be byte-identical to the
# block below, so a comment or blank line after `name:` is red (it could sit
# inside an open `run: |` block). Header comment edits are green. Changing
# the pinned block is a deliberate spec change that also edits TEST-SCENARIOS
# S219. The tools and the locale are judged at run time by S229, not here.
# CI_MACOS_YML_UNDER_TEST points S219 at a scratch candidate, CI_YML_UNDER_TEST
# points S222 at one (mutation proofs).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../ci-workflow-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../ci-workflow-lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# --- S219: the whole of macos.yml is the pinned block -----------------------
macos_yml="${CI_MACOS_YML_UNDER_TEST:-$TEST_REPO_ROOT/.github/workflows/macos.yml}"
if [ ! -f "$macos_yml" ]; then
  fail "S219 — $macos_yml does not exist: the macOS leg must live in its own workflow file"
else
  cat > "$SANDBOX/expected.yml" <<'PINNED'
name: CI macOS
on:
  pull_request:
  push:
    branches: [main]
jobs:
  macos:
    runs-on: macos-latest
    permissions:
      contents: read
    env:
      LANG: en_US.UTF-8
      LC_ALL: en_US.UTF-8
    steps:
      - uses: actions/checkout@v4
      - name: Platform tools first on PATH
        run: |
          echo "/bin" >> "$GITHUB_PATH"
          echo "/usr/bin" >> "$GITHUB_PATH"
      - name: Install mawk (S153 only)
        run: brew install mawk
      - name: Full test suite (bash 3.2)
        run: /bin/bash test/run.sh
PINNED
  # D1: byte alphabet, checked on the raw file before anything else.
  bad_lines="$(LC_ALL=C grep -an '[^ -~]' "$macos_yml" | LC_ALL=C cut -d: -f1 | head -3)"
  if [ -n "$bad_lines" ]; then
    shown=""
    for n in $bad_lines; do
      shown="$shown line $n: $(LC_ALL=C sed -n "${n}l" "$macos_yml")"
    done
    fail "S219 — $macos_yml has bytes outside LF and printable ASCII (first offending lines through sed -n l):$shown"
  else
    # D2: strip the leading header only; everything from the first
    # non-comment line on is compared byte for byte.
    LC_ALL=C awk 'started || !/^[[:space:]]*(#|$)/ { started = 1; print }' "$macos_yml" > "$SANDBOX/actual.yml"
    if ! cmp -s "$SANDBOX/expected.yml" "$SANDBOX/actual.yml"; then
      fail "S219 — from the first non-comment line on, $macos_yml is not the pinned block (comments and blank lines are allowed only in the header before name:; diff, expected then actual): $(diff "$SANDBOX/expected.yml" "$SANDBOX/actual.yml" | LC_ALL=C sed -n l | head -20 | tr '\n' '~')"
    fi
  fi
fi

# --- S222: regression, the Linux job is as it was, and ci.yml has no macOS job
yml="$(ci_yml_path)"
[ -f "$yml" ] || { fail "S222 — $yml is missing"; test_done; }

if [ "$(ci_job_count ubuntu-latest)" != "1" ]; then
  fail "S222 — expected exactly one job with runs-on: ubuntu-latest, found $(ci_job_count ubuntu-latest)"
fi
if [ "$(grep -v '^[[:space:]]*#' "$yml" | grep -ci 'macos' || true)" != "0" ]; then
  fail "S222 — ci.yml mentions macos on a non-comment line: the macOS leg lives in macos.yml (A35c D1, A35d)"
fi
lin="$(ci_job_block ubuntu-latest)"
case "$lin" in
  *"- run: ./check"*) ;;
  *) fail "S222 — the Linux job no longer runs ./check" ;;
esac
case "$lin" in
  *"gitleaks git"*) ;;
  *) fail "S222 — the Linux job lost its gitleaks step" ;;
esac
case "$lin" in
  *"check-pr-issue-link.sh"*"check-main-via-pr.sh"*) ;;
  *) fail "S222 — the Linux job lost its PR-link or main-via-PR step" ;;
esac
case "$lin" in
  *"fetch-depth: 0"*) ;;
  *) fail "S222 — the Linux job lost fetch-depth: 0" ;;
esac
case "$lin" in
  *"issues: read"*"pull-requests: read"*|*"pull-requests: read"*"issues: read"*) ;;
  *) fail "S222 — the Linux job lost its issues:read / pull-requests:read permissions" ;;
esac

test_done

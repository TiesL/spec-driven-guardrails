#!/usr/bin/env bash
# S154 — classify-review-depth.sh classifies a PR quick/thorough by
# Reviewer's six trigger categories (issue #328).
# Covers: F36
#
# Single-file, S152-style inline fixtures: this script has one call shape
# family per PR (changed-file paths + title/body) and one output line, so
# a separate shared *-fixture.sh file doesn't buy anything here either.
#
# Every fixture below fixes a distinct PR number (never a real issue in
# this repo) per subcase. The exact argv strings (CALL_*_ARGS below) were
# captured by running classify-review-depth.sh's own real argv against a
# recording fake gh, never retyped from the source by hand (this repo's
# fixture-hygiene convention, #296/#302, same discipline S150-S153 already
# use) — a drift in the script's endpoints or --jq expressions shows up
# here as a fallthrough failure, not a silent false pass.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/classify-review-depth.sh"
[ -x "$script" ] || { fail "S154 — classify-review-depth.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# --- Fixed argv patterns (captured, not retyped — see header). Single-
# quoted defensively: none of these contain a literal `$`, but the
# convention costs nothing and keeps every future edit to this file safe
# by construction if one ever does.
files_args() {
  echo "api repos/{owner}/{repo}/pulls/$1/files --paginate --jq .[].filename"
}
titlebody_args() {
  echo 'api repos/{owner}/{repo}/pulls/'"$1"' --jq (.title//"")+"\u0001"+(.body//"")'
}

FAKEGH_OUT="$SANDBOX/fakegh-out"
WITNESS="$SANDBOX/witness"

# Single-quote-escapes $1 for embedding as a literal inside a
# single-quoted shell string in the generated fake gh script below (one
# fixture body, S154.3's description text, contains a real apostrophe —
# "a partner's API" — so this can't be skipped the way s152's fixtures,
# which never quote user text back out, could).
sq() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

# Builds a fake gh answering exactly the two calls for PR $1 (files: $2,
# title: $3, body: $4), with the same centrally-supplied witness/exit-1
# fallthrough discipline s152 uses — any call this fixture has no arm for
# falls through to the witness line and exit 1, which is how a lookup
# "fails" for that test. The files/title/body VALUES are substituted here,
# at generation time, into single-quoted printf literals in the written
# fake gh script — not left as `$files`-style variable references, which
# would never be set inside that separate script process.
build_fake_gh() {
  local pr="$1" files="$2" title="$3" body="$4"
  local files_pattern titlebody_pattern files_q title_q body_q script_body
  files_pattern="$(files_args "$pr")"
  titlebody_pattern="$(titlebody_args "$pr")"
  files_q="$(sq "$files")"
  title_q="$(sq "$title")"
  body_q="$(sq "$body")"
  # Built as a plain array of lines, joined with printf — NOT a heredoc
  # inside $(...): bash 3.2 (this repo's own portability floor, and
  # macOS's stock /bin/bash) mis-parses a `$(cat <<EOF ... EOF)` whose
  # heredoc body contains literal parens (titlebody_pattern's own
  # `(.title//"")+...` shape) — a known old-bash heredoc/paren-counting
  # bug that silently dropped a `)` from the first case arm and corrupted
  # quoting further down when tried here. The array form below sidesteps
  # it entirely: each line is an ordinary quoted string, no heredoc
  # parsing involved. files_pattern/titlebody_pattern reproduce the same
  # argv string already confirmed byte-for-byte against a live run of
  # classify-review-depth.sh (see the header) — this is the "copy the
  # exact observed argv" step.
  local lines=(
    'case "$*" in'
    "  '$files_pattern')"
    "    printf '%s\\n' '$files_q'"
    "    exit 0 ;;"
    "  '$titlebody_pattern')"
    "    printf '%s\\x01%s' '$title_q' '$body_q'"
    "    exit 0 ;;"
    'esac'
    "printf 'UNEXPECTED: %s\\n' \"\$*\" >> '$WITNESS'"
    'exit 1'
  )
  script_body="$(printf '%s\n' "${lines[@]}")"
  : > "$WITNESS"
  fake_gh_bin "$script_body" > "$FAKEGH_OUT"
}

# Builds a fake gh where the files call for PR $1 fails (simulates a REST
# lookup failure) — no arm at all for either call, so both/either fall
# through to the witness+exit-1 fallthrough, exactly like scenario 8's
# "one call fails" and #10's fallthrough-witness discipline expect.
build_fake_gh_failing() {
  local pr="$1"
  local lines=(
    "printf 'UNEXPECTED: %s\\n' \"\$*\" >> '$WITNESS'"
    'exit 1'
  )
  local script_body
  script_body="$(printf '%s\n' "${lines[@]}")"
  : > "$WITNESS"
  fake_gh_bin "$script_body" > "$FAKEGH_OUT"
}

# ===========================================================================

echo "S154.1: quick, zero trigger-match names zero categories explicitly"
build_fake_gh 900 'docs/README.md' 'Fix a typo' 'Fixes a typo in the README.'
out="$(PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" 900 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] || fail "S154.1 — exit code $status, expected 0"
[ "$out" = "review-depth: quick" ] || fail "S154.1 — output was '$out', expected 'review-depth: quick' (no category name at all)"

echo "S154.2: real trigger match, Secrets/credentials (file-path signal)"
build_fake_gh 901 'config/credentials.yml' 'Rotate config credentials' 'Rotates the stored credentials file.'
out="$(PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" 901 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] || fail "S154.2 — exit code $status, expected 0"
[ "$out" = "review-depth: thorough (Secrets/credentials)" ] || fail "S154.2 — output was '$out'"

echo "S154.3: real trigger match, Untrusted input (description-text signal)"
build_fake_gh 902 'src/api/handler.py' 'Handle partner webhook' "Adds handling for external webhook payloads from a partner's API."
out="$(PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" 902 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] || fail "S154.3 — exit code $status, expected 0"
[ "$out" = "review-depth: thorough (Untrusted input)" ] || fail "S154.3 — output was '$out'"

echo "S154.4: multiple categories matched at once, no short-circuit"
build_fake_gh 903 '.github/workflows/deploy.yml' 'Update deploy workflow' 'This step reads secrets.DEPLOY_TOKEN to log in to the registry.'
out="$(PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" 903 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] || fail "S154.4 — exit code $status, expected 0"
[ "$out" = "review-depth: thorough (Secrets/credentials, Deploy/CI configuration)" ] || fail "S154.4 — output was '$out'"

echo "S154.5: --force-thorough overrides a zero-match PR, evidence says forced"
build_fake_gh 900 'docs/README.md' 'Fix a typo' 'Fixes a typo in the README.'
out="$(PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" 900 --force-thorough 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] || fail "S154.5 — exit code $status, expected 0"
[ "$out" = "review-depth: thorough (forced)" ] || fail "S154.5 — output was '$out', expected the override to be distinguishable from a real match"

echo "S154.6: --force-thorough is additive on a real-match PR, never masks evidence"
build_fake_gh 903 '.github/workflows/deploy.yml' 'Update deploy workflow' 'This step reads secrets.DEPLOY_TOKEN to log in to the registry.'
out="$(PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" 903 --force-thorough 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] || fail "S154.6 — exit code $status, expected 0"
[ "$out" = "review-depth: thorough (Secrets/credentials, Deploy/CI configuration)" ] || fail "S154.6 — output was '$out' — the override must not paper over real matched categories with just 'forced'"

echo "S154.7: evidence surface never emits a dispatch count or multiplier"
for pr_fixture in \
  '900|docs/README.md|Fix a typo|Fixes a typo in the README.|--force-thorough' \
  '902|src/api/handler.py|Handle partner webhook|Adds handling for external webhook payloads.' \
  '903|.github/workflows/deploy.yml|Update deploy workflow|This step reads secrets.DEPLOY_TOKEN to log in to the registry.'
do
  IFS='|' read -r pr files title body force <<<"$pr_fixture"
  build_fake_gh "$pr" "$files" "$title" "$body"
  if [ -n "$force" ]; then
    out="$(PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" "$pr" "$force" 2>/dev/null)"
  else
    out="$(PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" "$pr" 2>/dev/null)"
  fi
  case "$out" in
    *[0-9]*)
      fail "S154.7 — output '$out' for PR #$pr contains a digit; the classifier's own stdout must never print a count/multiplier (only category names/'forced')"
      ;;
  esac
done

echo "S154.8: REST lookup failure fails open toward thorough, not quick"
build_fake_gh_failing 904
out="$(PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" 904 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] || fail "S154.8 — exit code $status, expected 0 (a verdict must still print on a lookup failure)"
[ "$out" = "review-depth: thorough (lookup-failed)" ] || fail "S154.8 — output was '$out', expected the fail-open-toward-thorough verdict with lookup-failed evidence, not a false claim of a real category match"

echo "S154.9: no gh on PATH is a harder failure — non-zero exit, nothing on stdout"
NOGH_BIN="$SANDBOX/nogh"
mkdir -p "$NOGH_BIN"
for t in bash sh grep sed tr cat printf mktemp rm chmod mkdir; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$NOGH_BIN/$t"
done
out="$(PATH="$NOGH_BIN" "$script" 900 2>/dev/null)"
status=$?
[ "$status" -ne 0 ] || fail "S154.9 — exit code was 0 with no gh on PATH, expected non-zero"
[ -z "$out" ] || fail "S154.9 — stdout was '$out' with no gh on PATH, expected nothing (distinct from S154.8's 'got an answer, chose caution' case)"

echo "S154.10: no write path anywhere, verified with a reachable fallthrough witness"
# Positive control first: PR #999 has no answering arm at all, so its gh
# calls must actually reach the witness+exit-1 fallthrough (S152's own
# F-2 finding: an earlier version of that witness was dead code — never
# actually reachable — so this checks the witness fires, not just that
# its file exists).
build_fake_gh_failing 999
PATH="$(cat "$FAKEGH_OUT"):$PATH" "$script" 999 >/dev/null 2>&1
if [ ! -s "$WITNESS" ]; then
  fail "S154.10 — the fallthrough witness never fired for an unanswered PR #999 call; the witness itself may be dead (S152's own F-2 finding, guarded against here)"
else
  witness_calls="$(cat "$WITNESS")"
  case "$witness_calls" in
    *' label '*|*' comment '*|*' edit '*|*' merge '*|*'-X '*|*'--method '*)
      fail "S154.10 — a write-shaped gh call was made: $witness_calls"
      ;;
  esac
fi
if grep -qE "gh (issue|pr) (edit|comment|merge)|gh api .*(-X|--method)|gh .* label" "$script"; then
  fail "S154.10 — classify-review-depth.sh's own source contains a write-shaped gh invocation"
fi

test_done

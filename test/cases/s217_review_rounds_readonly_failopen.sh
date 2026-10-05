#!/usr/bin/env bash
# S217 — review-rounds.sh is read-only, REST-only, never blocks; a failed fetch is a visible warning.
# Covers: F42
#
# Issue #410, AC4 (Architect A28: "run by path, needs gh, fails open, never
# writes", not a gate; A25: no script carries its own marker extraction; A37:
# the round definition lives in one small function, `rr_rounds`, so the lib
# can take it over). Seam: the real script against a recording fake gh, plus
# static checks of the script text for what a behaviour test cannot show
# (portability, no wiring). Red now: the script does not exist.
#
# Mutations that turn this red (tag in the message):
#  readonly    make the script call `gh api -X POST`, `gh pr comment`, or `gh pr view`/graphql
#  exit-zero   exit 1 when gh fails
#  warn        delete the failed-fetch warning, or print 'review-rounds: 0' after a failed fetch
#  partial     ignore the failing reviews (or comments) endpoint without a warning
#  nogh        crash (exit non-zero / silent) when gh is missing
#  usage       run without an argument or with a malformed number without printing usage; or call gh with the malformed number
#  one-owner   add a model-record regex of its own to the script, or stop reading through lib/model-record.sh
#  portable    use `declare -A`, `mapfile`, `${x,,}`, `grep -P`, `sed -i`, `date -d` anywhere in the script
#  bash32      use a bash 4 feature (the /bin/bash 3.2 run fails)
#  fn          inline rr_rounds away, or define it twice
#  not-gate    reference review-rounds.sh from a hook, settings, check or a gate script
#  writes      create a file in the working directory

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/review-rounds-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-rounds-helpers.sh"

RR_SCRIPT="$TEST_REPO_ROOT/review-rounds.sh"
[ -x "$RR_SCRIPT" ] || { fail "S217 — review-rounds.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S217 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup

rr_out="" rr_err=""
rr_status=0 # set by rr_run
NL=$'\n'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z
rev="$(rr_review)"
seed() {
  rr_reset
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}${rev}" "$T2" "r2${NL}${rev}"
}

# --- behaviour: read-only, REST, GET only -------------------------------------
seed
: > "$RR_LOG"
rr_run "$RR_PR" "$RR_ISSUE"
[ "$rr_status" -eq 0 ] || fail "S217/exit-zero — exit $rr_status with two rounds, expected 0 (never blocks)"
[ "$(rr_lines '^review-rounds: ')" = "review-rounds: 2" ] || fail "S217/readonly — baseline run did not count two rounds: $rr_out"
calls="$(wc -l < "$RR_LOG" | tr -d ' ')"
[ "$calls" -ge 2 ] || fail "S217/readonly — the script made $calls gh calls (expected the PR comments and the PR reviews at least), so the checks below would be vacuous"
grep -q "issues/$RR_PR/comments" "$RR_LOG" || fail "S217/readonly — the PR's comments (issues/$RR_PR/comments) were not fetched"
grep -q "pulls/$RR_PR/reviews" "$RR_LOG" || fail "S217/readonly — the PR's reviews (pulls/$RR_PR/reviews) were not fetched"
while IFS= read -r call; do
  [ -n "$call" ] || continue
  case "$call" in
    "api "*) ;;
    *) fail "S217/readonly — a gh call other than 'gh api' (GraphQL-backed or a write): gh $call" ;;
  esac
  if grep -qE -- '(^| )(-X|--method|-f|-F|--field|--raw-field|--input)( |=|$)|graphql' <<<"$call"; then
    fail "S217/readonly — a gh api call that is not a plain GET: gh $call"
  fi
done < "$RR_LOG"
[ -z "$(find "$RR_CWD" -mindepth 1 2>/dev/null)" ] || fail "S217/writes — the script left files in its working directory: $(ls "$RR_CWD")"

# --- fail open, visibly --------------------------------------------------------
seed
FAKE_GH_FAIL=1 rr_run "$RR_PR" "$RR_ISSUE"
[ "$rr_status" -eq 0 ] || fail "S217/exit-zero — exit $rr_status when gh fails, expected 0 (fail open)"
grep -qiE 'warning' <<<"$rr_err" || fail "S217/warn — a failed fetch printed no warning on stderr (silent success): stderr='$rr_err'"
[ -z "$(rr_lines '^review-rounds: ')" ] || fail "S217/warn — a failed fetch still printed a review-rounds summary ('$(rr_lines '^review-rounds: ')'), which reads as a count"

for gone in "reviews-$RR_PR" "comments-$RR_PR"; do
  seed
  rm -f "${FAKE_GH_DATA:?}/${gone:?}.json"
  rr_run "$RR_PR" "$RR_ISSUE"
  [ "$rr_status" -eq 0 ] || fail "S217/partial — exit $rr_status with $gone unreadable, expected 0"
  grep -qiE 'warning' <<<"$rr_err" || fail "S217/partial — $gone unreadable and no warning on stderr: the count would be silently incomplete"
done
seed
rm -f "${FAKE_GH_DATA:?}/comments-${RR_ISSUE:?}.json"
rr_run "$RR_PR" "$RR_ISSUE"
[ "$rr_status" -eq 0 ] || fail "S217/partial — exit $rr_status with the issue's comments unreadable, expected 0"
grep -qiE 'warning' <<<"$rr_err" || fail "S217/partial — the issue's comments unreadable and no warning on stderr"

# gh missing: a PATH of everything in /usr/bin and /bin except gh (and jq, which
# the fake gh needs)
seed
nogh="$SANDBOX/nogh"
mkdir -p "$nogh"
for p in /usr/bin/* /bin/*; do
  b="${p##*/}"
  [ "$b" = gh ] && continue
  [ -e "$nogh/$b" ] || ln -s "$p" "$nogh/$b" 2>/dev/null
done
if [ -z "$(PATH="$nogh" command -v gh 2>/dev/null)" ]; then
  nogh_out="$(cd "$RR_CWD" && PATH="$nogh" "$RR_SCRIPT" "$RR_PR" 2>"$SANDBOX/nogh-err")"
  nogh_status=$?
  [ "$nogh_status" -eq 0 ] || fail "S217/nogh — exit $nogh_status without gh, expected 0"
  grep -qiE 'warning' "$SANDBOX/nogh-err" || fail "S217/nogh — no warning on stderr without gh"
  if grep -q '^review-rounds: ' <<<"$nogh_out"; then fail "S217/nogh — a summary was printed without gh"; fi
fi

# usage: no argument, and a PR number that is not a number never reaches gh
# shellcheck disable=SC2016  # a literal command substitution is the point
for bad in "" "abc" "246/../../x" "246;id" '$(id)'; do
  seed
  : > "$RR_LOG"
  if [ -z "$bad" ]; then rr_run; else rr_run "$bad"; fi
  grep -qi 'usage' <<<"$rr_err" || fail "S217/usage — argument '$bad' printed no usage on stderr: '$rr_err'"
  [ -z "$(rr_lines '^review-rounds: ')" ] || fail "S217/usage — argument '$bad' printed a summary"
  [ ! -s "$RR_LOG" ] || fail "S217/usage — argument '$bad' reached gh: $(cat "$RR_LOG")"
done
seed
: > "$RR_LOG"
rr_run "$RR_PR" "x;id"
grep -qi 'usage' <<<"$rr_err" || fail "S217/usage — a malformed issue number printed no usage"
[ ! -s "$RR_LOG" ] || fail "S217/usage — a malformed issue number reached gh: $(cat "$RR_LOG")"

# --- macOS bash 3.2, when this machine has it as /bin/bash ----------------------
if [ -x /bin/bash ] && /bin/bash -c '[ "${BASH_VERSINFO[0]}" -lt 4 ]' 2>/dev/null; then
  seed
  rr_run "$RR_PR" "$RR_ISSUE"
  want="$rr_out"
  b32="$(cd "$RR_CWD" && PATH="$RR_BIN:$PATH" /bin/bash "$RR_SCRIPT" "$RR_PR" "$RR_ISSUE" 2>"$SANDBOX/b32-err")"
  [ "$b32" = "$want" ] || fail "S217/bash32 — under /bin/bash 3.2 the output differs or the script failed: $(cat "$SANDBOX/b32-err")"
fi

# --- static: what the behaviour cannot show ---------------------------------------
code="$(grep -vE '^[[:space:]]*#' "$RR_SCRIPT")"
grep -q 'lib/model-record\.sh' <<<"$code" || fail "S217/one-owner — the script does not source lib/model-record.sh (A25: no script carries its own marker extraction)"
reader="$(grep -oE '\bmarker_[a-z_]+' <<<"$code" | grep -vE '^marker_(emit|fail)$' | head -1)"
if [ -z "$reader" ]; then
  fail "S217/one-owner — the script calls no reader (marker_*) of lib/model-record.sh"
elif ! grep -qE "^$reader\(\)" "$TEST_REPO_ROOT/lib/model-record.sh"; then
  fail "S217/one-owner — the script calls $reader, which lib/model-record.sh does not define"
fi
if grep -qE 'model-record:|stage=' <<<"$code"; then
  fail "S217/one-owner — the script carries marker text of its own (model-record:, stage=): $(grep -nE 'model-record:|stage=' <<<"$code" | head -2)"
fi
# the only HTML-comment text allowed is the legacy done marker (not a model-record marker)
other="$(grep -E '<!--' <<<"$code" | grep -vE 'pre-merge-review:done' || true)"
if [ -n "$other" ]; then
  fail "S217/one-owner — the script carries an HTML-comment marker pattern other than the legacy pre-merge-review:done: $other"
fi
bad='declare -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)|grep -[a-zA-Z]*P|sed -[a-zA-Z]*i|sed -[a-zA-Z]*r|date -d|readlink -f|xargs -r|stat -c|\\b'
if grep -qE "$bad" <<<"$code"; then
  fail "S217/portable — the script uses a bash 4 or GNU-only construct: $(grep -nE "$bad" <<<"$code" | head -2)"
fi
n="$(grep -cE '^rr_rounds\(\)|^function rr_rounds' <<<"$code")"
[ "$n" -eq 1 ] || fail "S217/fn — the round definition must be ONE function named rr_rounds (A37: the lib takes it over); found $n definitions"
[ "$(head -1 "$RR_SCRIPT")" = '#!/usr/bin/env bash' ] || fail "S217/portable — the shebang is not '#!/usr/bin/env bash'"
grep -qE '^set -[a-z]*u' <<<"$code" || fail "S217/portable — the script does not set -u (the other evidence scripts do)"
if grep -qE '(^|[^a-z])eval ' <<<"$code"; then
  fail "S217/readonly — the script uses eval; PR comment text is not under its control"
fi
if grep -qE 'gh (pr|issue) (view|comment|edit|merge|close|review|create)|gh label|gh api graphql' <<<"$code"; then
  fail "S217/readonly — the script has a gh call that is GraphQL-backed or a write: $(grep -nE 'gh (pr|issue) |gh label|graphql' <<<"$code" | head -2)"
fi

# --- not a gate: nothing wires it in ---------------------------------------------------
wired="$(cd "$TEST_REPO_ROOT" && grep -rlE 'review-rounds' hooks settings check check-commit .github skills/pre-merge-review/*.sh skills/*/*.sh compliance-evidence.sh role-label-staleness.sh classify-review-depth.sh wait-for-ci.sh epic-auto-close.sh 2>/dev/null | grep -v 'review-rounds\.sh$' || true)"
[ -z "$wired" ] || fail "S217/not-gate — review-rounds is referenced from a hook, check or gate script (A28: it is not a gate): $wired"

test_done

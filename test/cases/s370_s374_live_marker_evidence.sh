#!/usr/bin/env bash
# S370-S374 — live Markdown evidence in both consumers and adopted entry points.
# Covers: F8, F9, F23, F28, F40
# Markdown fixtures intentionally contain literal backticks.
# shellcheck disable=SC2016
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck disable=SC1091
# shellcheck source=../fixtures/pipeline-371-helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck disable=SC1091
# shellcheck source=../fixtures/review-floor-helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck disable=SC1091
# shellcheck source=../fixtures/review-rounds-helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-rounds-helpers.sh"
sandbox_create
trap sandbox_destroy EXIT
rr_setup
rr_status=0
project="$(fresh_project 'marker project')"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work
mkdir -p "$project/subdir"
GUARD="$TEST_REPO_ROOT/hooks/git-guardrails"
GATE="$TEST_REPO_ROOT/skills/pre-merge-review/finding-carryforward-gate.sh"
merge_bin="$SANDBOX/merge-bin"
mkdir -p "$merge_bin"
export MERGE_DATA="$SANDBOX/merge.json" MERGE_LOG="$SANDBOX/merge.log"
cat > "$merge_bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MERGE_LOG"
case "$*" in
  'pr view --json comments,headRefOid') cat "$MERGE_DATA" ;;
  'pr checks --json bucket,name') printf '[]' ;;
  'api repos/{owner}/{repo}/pulls --paginate --jq '*) printf '41\tfeature/work\n' ;;
  'api repos/{owner}/{repo}/pulls/41 --jq .base.ref'*) printf 'main\t1111111111111111111111111111111111111111\n' ;;
  'api repos/{owner}/{repo}/compare/'*) printf '0\n' ;;
  'api repos/{owner}/{repo}/pulls/41 --jq '*) printf '\001\003' ;;
  'api repos/{owner}/{repo}/pulls/41/commits '*) printf '\002' ;;
  *) exit 1 ;;
esac
GH
chmod +x "$merge_bin/gh"
NL=$'\n'
approval='<!-- pre-merge-review:done sha=1111111111111111111111111111111111111111 -->'
open='<!-- finding:quote-test status=open -->'
resolved='<!-- finding:quote-test status=resolved -->'
review="$(rr_review)"

# Literal, independently expected quoting fixtures, shared only as input.
quote() {
  case "$1" in
    fence) printf '```text\n%s\n```' "$2" ;;
    inline) printf '`%s`' "$2" ;;
    blockquote) printf '> %s' "$2" ;;
  esac
}
merge_run() {
  local bodies=() b
  for b in "$@"; do bodies+=("$(jq -cn --arg b "$b" '{body:$b}')"); done
  printf '%s\n' "${bodies[@]}" | jq -s '{headRefOid:"1111111111111111111111111111111111111111",comments:.}' > "$MERGE_DATA"
  : > "$MERGE_LOG"
  output="$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"gh pr merge"}}' "$project/subdir" | PATH="$merge_bin:$PATH" "$GUARD" 2>&1)"
  status=$?
  assert_contains 'comments/head request reached' 'pr view --json comments,headRefOid' "$(cat "$MERGE_LOG")"
}
merge_check() {
  local label="$1" want="$2"
  shift 2
  merge_run "$@"
  [ "$status" -eq "$want" ] || fail "$label — wanted exit $want, got $status: $output"
  if [ "$want" -eq 2 ]; then assert_contains "$label missing HEAD" 'current HEAD' "$output"; fi
  case "$output" in *"couldn't interpret"*) fail "$label — unexpected Markdown read failure: $output" ;; esac
}
carry_run() {
  local args=() i=1 b
  rr_reset
  for b in "$@"; do
    args+=("2026-10-0${i}T10:00:00Z" "${review}${NL}${b}")
    i=$((i + 1))
  done
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "${args[@]}"
  : > "$RR_LOG"
  rr_script_run "$GATE" "$RR_PR"
  [ "$rr_status" -eq 0 ] || fail "carry exit $rr_status: $rr_err"
  assert_contains 'REST comments reached' "issues/$RR_PR/comments" "$(cat "$RR_LOG")"
}
carry_check() {
  local label="$1" round="$2" want=''
  shift 2
  carry_run "$@"
  if [ -n "$round" ]; then want="finding-carryforward: quote-test was open in the previous round and is missing from this one (round $round)"; fi
  [ "$rr_out" = "$want" ] || fail "$label — expected [$want], got [$rr_out], stderr [$rr_err]"
  [ -z "$rr_err" ] || fail "$label — unexpected warning: $rr_err"
}
core_matrix() {
  local prefix="$1" form
  for form in fence inline blockquote; do
    merge_check "$prefix/$form approval" 2 "$(quote "$form" "$approval")"
    carry_check "$prefix/$form resolution" 2 "$open" "$(quote "$form" "$resolved")"
    carry_check "$prefix/$form quoted open" '' "$(quote "$form" "$open")" none
  done
  merge_check "$prefix/live" 0 "$approval"
  merge_check "$prefix/prose" 0 "reviewed $approval thanks"
  merge_check "$prefix/mixed" 0 "$(quote inline "$approval") $approval"
  carry_check "$prefix/live" '' "$open" "$resolved"
  carry_check "$prefix/prose" '' "$open" "fixed $resolved thanks"
  carry_check "$prefix/mixed" '' "$open" "$(quote inline "$resolved") $resolved"
}
core_matrix S370-S371
merge_check stale 2 '<!-- pre-merge-review:done sha=2222222222222222222222222222222222222222 -->'
carry_check plain-mention '' "$open" 'see finding:quote-test here'
carry_check live-open 3 "$open" "$open" none
carry_check gap-cleared '' "$open" none "$resolved"
carry_check quoted-gap 2 "$open" none "$(quote inline "$resolved")"

# S372: both seams get fixed expected outcomes, never parser-generated oracles.
parity() {
  local label="$1" expected="$2" before="$3" after="$4"
  merge_check "S372/$label" "$expected" "$before$approval$after"
  if [ "$expected" -eq 2 ]; then
    carry_check "S372/$label" 2 "$open" "$before$resolved$after"
  else
    carry_check "S372/$label" '' "$open" "$before$resolved$after"
  fi
}
parity four-backticks 2 $'````\n```\n' $'\n```\n````'
parity tilde 2 $'~~~\n```\n' $'\n~~~'
parity invalid-close 2 $'```\n```info\n' $'\n```'
parity balanced-span-live 0 '`example` ' ''
parity unmatched-backtick 0 '`unmatched ' ''
parity CRLF 2 $'```\r\n' $'\r\n```\r\n'
parity quoted-fence 0 $'> ```\n' ''
merge_check per-body-state 0 $'```\nexample' "$approval"
carry_check per-body-state '' "$open${NL}"'```' "$resolved"

# S374: invoke genuinely installed paths from the adopter's subdirectory.
clone="$(sandbox_copy_repo 'workflow clone')"
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" --runtime codex "$project" > "$SANDBOX/adopt.log" 2>&1 || {
  fail "S374 adoption: $(cat "$SANDBOX/adopt.log")"; test_done;
}
GUARD="$project/.guardrails/source/hooks/git-guardrails"
GATE="$project/.agents/skills/pre-merge-review/finding-carryforward-gate.sh"
# shellcheck disable=SC2034  # consumed by rr_script_run/rr_run
RR_CWD="$project/subdir"
[ ! -e "$project/lib/markdown.sh" ] || fail 'S374 adopter has private Markdown library'
core_matrix S374

# S373: mutate only the scratch source. Restore after each fault. The marker
# file proves the injected failure was reached rather than a different gate.
cp "$clone/lib/markdown.sh" "$SANDBOX/markdown.original"
export FAULT_HIT="$SANDBOX/fault-hit"
fault_check() {
  local label="$1"
  rm -f "$FAULT_HIT"
  merge_run "$approval"
  [ "$status" -eq 0 ] || fail "S373/$label merge did not fail open: $output"
  assert_contains "S373/$label merge warning" "couldn't interpret" "$output"
  [ -f "$FAULT_HIT" ] || fail "S373/$label merge fault not reached"
  rm -f "$FAULT_HIT"
  # A prior gap exists before the failing third body: no partial verdict.
  carry_run "$open" none trigger-failure
  [ -z "$rr_out" ] || fail "S373/$label partial verdict: $rr_out"
  assert_contains "S373/$label carry warning" 'warning:' "$rr_err"
  [ -f "$FAULT_HIT" ] || fail "S373/$label carry fault not reached"
}
cat >> "$clone/lib/markdown.sh" <<'FAULT'
live_text() { printf reached >> "$FAULT_HIT"; return 7; }
FAULT
fault_check nonzero-parser
cp "$SANDBOX/markdown.original" "$clone/lib/markdown.sh"
cat > "$clone/lib/markdown.sh" <<'FAULT'
printf reached >> "$FAULT_HIT"
return 8
FAULT
fault_check source-failure
cp "$SANDBOX/markdown.original" "$clone/lib/markdown.sh"
# Missing library: prove disappearance, then verify observable fail-open.
mv "$clone/lib/markdown.sh" "$clone/lib/markdown.missing"
merge_run "$approval"
[ "$status" -eq 0 ] || fail 'S373 missing library merge refusal'
assert_contains 'S373 missing library merge warning' "couldn't interpret" "$output"
carry_run "$open" none
[ -z "$rr_out" ] || fail 'S373 missing library carry verdict'
assert_contains 'S373 missing library carry warning' 'warning:' "$rr_err"
mv "$clone/lib/markdown.missing" "$clone/lib/markdown.sh"

# Child launch failure: Python injection affects only subprocess.run, preserving
# JSON decoding and the actual guard entry point. Its hit file proves execution.
mkdir -p "$SANDBOX/python-fault"
cat > "$SANDBOX/python-fault/sitecustomize.py" <<'PY'
import os, subprocess

def fail_launch(*args, **kwargs):
    with open(os.environ['FAULT_HIT'], 'w') as f:
        f.write('launch attempted')
    raise OSError('injected launch failure')
subprocess.run = fail_launch
PY
rm -f "$FAULT_HIT"
export PYTHONPATH="$SANDBOX/python-fault"
merge_run "$approval"
unset PYTHONPATH
[ "$status" -eq 0 ] || fail 'S373 child-launch did not fail open'
assert_contains 'S373 launch warning' "couldn't interpret" "$output"
[ -f "$FAULT_HIT" ] || fail 'S373 child launch fault not reached'

# Only fail consumer capture on round 3 (record selection uses no live_text for
# valid Review records). Overriding printf corrupts the consumer sentinel; it
# cannot turn an earlier finding into a partial verdict.
for fault in missing corrupt; do
  cp "$SANDBOX/markdown.original" "$clone/lib/markdown.sh"
  cat >> "$clone/lib/markdown.sh" <<'FAULT'
live_text() {
  case "$1" in
    *trigger-failure*)
      printf reached >> "$FAULT_HIT"
      printf() {
        case "$1" in
          'x%s') [ "$CAPTURE_FAULT" = missing ] || builtin printf 'corrupt'; return 0 ;;
          *) builtin printf "$@" ;;
        esac
      }
      ;;
    *) builtin printf '%s' "$1" ;;
  esac
}
FAULT
  export CAPTURE_FAULT="$fault"
  rm -f "$FAULT_HIT"
  carry_run "$open" none trigger-failure
  [ -f "$FAULT_HIT" ] || fail "S373/$fault sentinel fault not reached"
  [ -z "$rr_out" ] || fail "S373/$fault sentinel partial verdict: $rr_out"
  assert_contains "S373/$fault sentinel warning" 'warning:' "$rr_err"
done
unset CAPTURE_FAULT
cp "$SANDBOX/markdown.original" "$clone/lib/markdown.sh"
# Empty successful filtering remains ordinary absence of evidence.
merge_check S373-empty 2 "$(quote inline "$approval")"
carry_check S373-no-live-findings 2 "$open" "$(quote inline "$resolved")"
test_done

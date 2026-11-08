#!/usr/bin/env bash
# S102-S107, S594-S603 — An epic auto-closes once every issue naming it as
# its Epic is closed; stays open otherwise; never crashes on malformed input;
# a failed close is reported, not treated as success. S594-S603 (#683, A55):
# before closing, a still-live release branch or open release PR for the epic
# keeps it open; a failed release query leaves it open, loudly; the workflow
# token carries pull-requests: read.
# Covers: F20

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

script="$TEST_REPO_ROOT/epic-auto-close.sh"
[ -x "$script" ] || { fail "S102 — epic-auto-close.sh is missing or not executable"; test_done; }

fixtures="$SANDBOX/fixtures"
mkdir -p "$fixtures/body" "$fixtures/state"

set_body() { printf '%s' "$2" > "$fixtures/body/$1"; }
set_state() { printf '%s' "$2" > "$fixtures/state/$1"; }
set_issue_list() { printf '%s' "$1" > "$fixtures/issue-list.json"; }

# The fake `gh api` (#683, A55) is a helper script so the quoting stays
# readable. It behaves like the real command for what the script can observe:
# the ref prefix of matching-refs and the state/base parameters of the pulls
# endpoint are honoured as the server does (unless the "overbroad" switch is
# set), a fixture dir of page files is served as pages under --paginate (only
# the first page without it), --jq is applied to each page, a per-query mode
# file (fail, empty, malformed, 403) switches failure shapes, and every call
# is logged. Without any fixture it answers one well-formed empty page.
cat > "$fixtures/fake-api.sh" <<'FAKEAPI'
#!/usr/bin/env bash
FIX="$1"; shift; shift
paginate=0; endpoint=""; expr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paginate) paginate=1 ;;
    --jq) shift; expr="$1" ;;
    repos/*) endpoint="$1" ;;
  esac
  shift
done
printf "%s\n" "$endpoint" >> "$FIX/api.log"
case "$endpoint" in
  */matching-refs/*) kind=branches ;;
  */pulls\?*|*/pulls) kind=pulls ;;
  *) exit 1 ;;
esac
mode=""
[ -f "$FIX/api/$kind.mode" ] && mode="$(cat "$FIX/api/$kind.mode")"
case "$mode" in
  fail) exit 1 ;;
  empty) exit 0 ;;
  malformed) echo "not json {"; exit 0 ;;
  403) echo "gh: HTTP 403: Resource not accessible by integration" >&2; exit 1 ;;
esac
filter="."
if [ ! -f "$FIX/api/overbroad" ]; then
  if [ "$kind" = branches ]; then
    prefix="${endpoint#*matching-refs/heads/}"
    filter="map(select(.ref | startswith(\"refs/heads/$prefix\")))"
  else
    st="$(sed -n "s/.*[?&]state=\([^&]*\).*/\1/p" <<<"$endpoint")"
    bs="$(sed -n "s/.*[?&]base=\([^&]*\).*/\1/p" <<<"$endpoint")"
    filter="map(select(.state == \"$st\" and .base.ref == \"$bs\"))"
  fi
fi
pages="$(ls "$FIX/api/$kind"/*.json 2>/dev/null)"
[ -n "$pages" ] || { mkdir -p "$FIX/api"; echo "[]" > "$FIX/api/empty-page.json"; pages="$FIX/api/empty-page.json"; }
for f in $pages; do
  page="$(jq -c "$filter" "$f")" || exit 1
  if [ -n "$expr" ]; then jq -r "$expr" <<<"$page" || exit 1; else echo "$page"; fi
  [ "$paginate" -eq 1 ] || break
done
FAKEAPI
chmod +x "$fixtures/fake-api.sh"

fakebin="$(fake_gh_bin '
case "$1 $2" in
  "api "*)
    exec "'"$fixtures"'/fake-api.sh" "'"$fixtures"'" "$@" ;;
  "issue view")
    n="$3"
    case "$*" in
      *"--json body"*)
        f="'"$fixtures"'/body/$n"
        [ -f "$f" ] && { cat "$f"; exit 0; }
        exit 1 ;;
      *"--json state"*)
        f="'"$fixtures"'/state/$n"
        [ -f "$f" ] && { cat "$f"; exit 0; }
        exit 1 ;;
    esac
    exit 1 ;;
  "issue list")
    f="'"$fixtures"'/issue-list.json"
    [ -f "$f" ] && { cat "$f"; exit 0; }
    exit 1 ;;
  "issue close")
    [ -f "'"$fixtures"'/close-should-fail" ] && exit 1
    n="$3"
    shift 3
    printf "%s|%s\n" "$n" "$*" >> "'"$fixtures"'/closed-log"
    exit 0 ;;
esac
exit 1
')"

run() {
  PATH="$fakebin:$PATH" "$script" "$1" 2>&1
}

closed_log() { cat "$fixtures/closed-log" 2>/dev/null; }
reset_log() { rm -f "$fixtures/closed-log"; }

# AC3 — a non-work-item issue (no Epic field) does nothing.
set_body 30 "Just a plain bug report, no epic field at all."
reset_log
output="$(run 30)"; status=$?
[ "$status" -eq 0 ] || fail "S102/AC3 — plain issue close exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/AC3 — an epic was closed for an issue with no Epic field"

# AC5 (malformed) — a work item naming itself as its own epic is skipped.
set_body 31 "**Epic:** #31"
reset_log
output="$(run 31)"; status=$?
[ "$status" -eq 0 ] || fail "S102/self-reference — exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/self-reference — an epic was closed"

# AC5 (dangling) — the named epic doesn't exist / can't be looked up.
set_body 32 "**Epic:** #999"
reset_log
output="$(run 32)"; status=$?
[ "$status" -eq 0 ] || fail "S102/dangling epic — exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/dangling epic — an epic was closed"

# AC4 — an already-closed epic is left alone (no duplicate close attempt).
set_body 40 "**Epic:** #10"
set_state 10 "CLOSED"
reset_log
output="$(run 40)"; status=$?
[ "$status" -eq 0 ] || fail "S102/AC4 — exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/AC4 — a close was attempted on an already-closed epic"

# AC2 — closing a work item with an open sibling leaves the epic open.
set_body 50 "**Epic:** #20"
set_body 51 "**Epic:** #20"
set_state 20 "OPEN"
set_issue_list '[
  {"number": 20, "state": "OPEN",   "body": "the epic itself, no Epic field"},
  {"number": 50, "state": "CLOSED", "body": "**Epic:** #20"},
  {"number": 51, "state": "OPEN",   "body": "**Epic:** #20"}
]'
reset_log
output="$(run 50)"; status=$?
[ "$status" -eq 0 ] || fail "S102/AC2 — exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/AC2 — the epic closed while a sibling work item is still open"

# AC1 — closing the last open work item closes the epic, with both
# work items named in the comment.
set_body 60 "**Epic:** #21"
set_body 61 "**Epic:** #21"
set_state 21 "OPEN"
set_issue_list '[
  {"number": 21, "state": "OPEN",   "body": "the epic itself, no Epic field"},
  {"number": 60, "state": "CLOSED", "body": "**Epic:** #21"},
  {"number": 61, "state": "CLOSED", "body": "**Epic:** #21"}
]'
reset_log
output="$(run 61)"; status=$?
[ "$status" -eq 0 ] || fail "S102/AC1 — exited $status: $output"
log="$(closed_log)"
case "$log" in
  21\|*) ;;
  *) fail "S102/AC1 — epic #21 was not closed (log: $log)" ;;
esac
assert_contains "S102/AC1 — comment names #60" "#60" "$log"
assert_contains "S102/AC1 — comment names #61" "#61" "$log"

# A failed `gh issue close` call (network blip, permissions) is reported
# as a loud failure, not silently treated as success — found during
# pre-merge-review of PR #220.
touch "$fixtures/close-should-fail"
output="$(run 61)"; status=$?
rm -f "$fixtures/close-should-fail"
[ "$status" -ne 0 ] || fail "S102/close-failure — a failed gh issue close was reported as success"

# gh missing entirely: a loud, non-zero failure, not a silent no-op — this
# script has no fail-open the way the merge guard does (see its own header
# comment for why).
nogh="$(path_without_gh)"
output="$(PATH="$nogh" "$script" 60 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S102 — gh missing gave exit 0 instead of a loud failure"

# ---------------------------------------------------------------------------
# S594-S603 (#683, A55) — release-aware close. Everything below runs in the
# same fake-gh seam; a sentinel `gh` behind the fake on PATH records any call
# that would have escaped to a real gh.
# ---------------------------------------------------------------------------
sentinel="$SANDBOX/sentinel"
mkdir -p "$sentinel"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/sentinel-calls"\nexit 1\n' "$SANDBOX" > "$sentinel/gh"
chmod +x "$sentinel/gh"

api="$fixtures/api"
reset_api() { rm -rf "$api" "$fixtures/api.log"; mkdir -p "$api/branches" "$api/pulls"; }
api_log() { cat "$fixtures/api.log" 2>/dev/null; }
set_mode() { printf '%s' "$2" > "$api/$1.mode"; }  # kind: branches|pulls
overbroad() { : > "$api/overbroad"; }
page_n=0
# add_page <kind> <json-array>: appends one page of the fixture.
add_page() { page_n=$((page_n + 1)); printf '%s' "$2" > "$api/$1/$(printf '%03d' "$page_n").json"; }
br() { printf '{"ref":"refs/heads/%s"}' "$1"; }
# pr <state> <base> <head-ref> <head-repo>
pr() { printf '{"state":"%s","base":{"ref":"%s","repo":{"full_name":"TiesL/r"}},"head":{"ref":"%s","repo":{"full_name":"%s"}}}' "$1" "$2" "$3" "$4"; }

# setup_epic <epic> [child1 child2]: epic open, both children closed.
setup_epic() {
  local e="$1" c1="${2:-9001}" c2="${3:-9002}"
  set_body "$c2" "**Epic:** #$e"
  set_state "$e" "OPEN"
  set_issue_list '[
    {"number": '"$e"', "state": "OPEN",   "body": "the epic itself"},
    {"number": '"$c1"', "state": "CLOSED", "body": "**Epic:** #'"$e"'"},
    {"number": '"$c2"', "state": "CLOSED", "body": "**Epic:** #'"$e"'"}
  ]'
  reset_log; reset_api; page_n=0
}

run_split() {
  PATH="$fakebin:$sentinel:$PATH" "$script" "$1" >"$fixtures/out" 2>"$fixtures/err"
  status=$?
  out="$(cat "$fixtures/out")"; err="$(cat "$fixtures/err")"
}

expect_open() {  # label epic child
  run_split "$3"
  [ "$status" -eq 0 ] || fail "$1 — exit $status instead of 0: $err"
  [ -z "$(closed_log)" ] || fail "$1 — epic was closed: $(closed_log)"
}
expect_close() {
  run_split "$3"
  [ "$status" -eq 0 ] || fail "$1 — exit $status instead of 0: $err"
  case "$(closed_log)" in
    "$2|"*) ;;
    *) fail "$1 — epic #$2 was not closed (log: $(closed_log), stderr: $err)" ;;
  esac
}
expect_failed_query() {  # label epic child query-word
  run_split "$3"
  [ "$status" -ne 0 ] || fail "$1 — exit 0 on a failed $4 query"
  [ -z "$(closed_log)" ] || fail "$1 — epic closed despite a failed $4 query"
  assert_contains "$1 — message names the epic" "#$2" "$err"
  assert_contains "$1 — message names the failed query" "$4 query failed" "$err"
}

# S594 — a remote release branch keeps the epic open and skips the PR query.
setup_epic 607
add_page branches "[$(br release/607-panel-mechanisms)]"
set_mode pulls fail
expect_open "S594" 607 9002
[ "$(printf '%s\n' "$err" | grep -c .)" -le 1 ] || fail "S594 — more than one stderr line: $err"
assert_contains "S594 — note names the epic" "607" "$err"
assert_contains "S594 — note names the branch" "release/607-panel-mechanisms" "$err"
case "$(api_log)" in *pulls*) fail "S594 — the open-PR query was issued after a branch was found" ;; esac
set_mode pulls ""; rm -f "$api/pulls.mode"; reset_log; rm -f "$fixtures/api.log"
expect_open "S594/control (working PR query)" 607 9002
assert_contains "S594/control — note names the branch" "release/607-panel-mechanisms" "$err"

# S595 — an open release PR alone keeps the epic open.
setup_epic 607
add_page pulls "[$(pr open main release/607-panel-mechanisms TiesL/r)]"
expect_open "S595" 607 9002

# S596 — nothing found closes with the unchanged comment.
setup_epic 21 60 61
expect_close "S596/empty lists" 21 61
[ "$(closed_log)" = "21|--comment Auto-closed: every issue naming this as its Epic is closed (#60,#61)." ] \
  || fail "S596 — comment bytes changed: $(closed_log)"
setup_epic 21 60 61
add_page branches "[$(br feature/1-x)]"
page_n=0; add_page pulls "[$(pr open main feature/1-x TiesL/r)]"
expect_close "S596/unrelated entries" 21 61

# S597 — exact number match, both directions, with and without an
# over-broad server.
for variant in strict overbroad; do
  setup_epic 607; [ $variant = overbroad ] && overbroad
  add_page branches "[$(br release/6070-other)]"
  expect_close "S597/A ($variant)" 607 9002
  setup_epic 607; [ $variant = overbroad ] && overbroad
  add_page pulls "[$(pr open main release/6070-other TiesL/r)]"
  expect_close "S597/B ($variant)" 607 9002
  setup_epic 60; [ $variant = overbroad ] && overbroad
  add_page branches "[$(br release/607-panel-mechanisms)]"
  expect_close "S597/C ($variant)" 60 9002
  setup_epic 60; [ $variant = overbroad ] && overbroad
  add_page pulls "[$(pr open main release/607-panel-mechanisms TiesL/r)]"
  expect_close "S597/D ($variant)" 60 9002
  setup_epic 6070; [ $variant = overbroad ] && overbroad
  add_page branches "[$(br release/607-panel-mechanisms)]"
  expect_close "S597/E ($variant)" 6070 9002
  setup_epic 607; [ $variant = overbroad ] && overbroad
  add_page branches "[$(br release/607-x)]"
  expect_open "S597/F control ($variant)" 607 9002
done

# S598 — only an open, same-repository PR against main counts.
for variant in strict overbroad; do
  setup_epic 607; [ $variant = overbroad ] && overbroad
  add_page pulls "[$(pr open develop release/607-panel-mechanisms TiesL/r)]"
  expect_close "S598/a other base ($variant)" 607 9002
  setup_epic 607; [ $variant = overbroad ] && overbroad
  add_page pulls "[$(pr closed main release/607-panel-mechanisms TiesL/r)]"
  expect_close "S598/b closed ($variant)" 607 9002
  setup_epic 607; [ $variant = overbroad ] && overbroad
  add_page pulls "[$(pr closed main release/607-panel-mechanisms TiesL/r | sed 's/}$/,"merged_at":"2026-11-01T00:00:00Z"}/')]"
  expect_close "S598/c merged ($variant)" 607 9002
  setup_epic 607; [ $variant = overbroad ] && overbroad
  add_page pulls "[$(pr open main release/607-panel-mechanisms someone/fork)]"
  expect_close "S598/d fork ($variant)" 607 9002
  setup_epic 607; [ $variant = overbroad ] && overbroad
  add_page pulls "[$(pr open main release/607-panel-mechanisms TiesL/r)]"
  expect_open "S598/e control ($variant)" 607 9002
done

# S599 — matches on a later page are found; non-matching pages close.
filler_b() { jq -nc --arg p "$1" '[range(0;100) | {ref: ("refs/heads/" + $p + "\(.)")}]'; }
filler_p() { jq -nc '[range(0;100) | {state:"open", base:{ref:"main", repo:{full_name:"TiesL/r"}}, head:{ref:"release/6070-x\(.)", repo:{full_name:"TiesL/r"}}}]'; }
setup_epic 607
add_page branches "$(filler_b release/6070-x)"; add_page branches "$(filler_b release/6070-y)"
add_page branches "[$(br release/607-panel-mechanisms)]"
expect_open "S599/A branch on page 3" 607 9002
setup_epic 607
add_page pulls "$(filler_p)"; add_page pulls "$(filler_p)"
add_page pulls "[$(pr open main release/607-panel-mechanisms TiesL/r)]"
expect_open "S599/B PR on page 3" 607 9002
setup_epic 607; overbroad
add_page branches "$(filler_b release/6070-x)"; add_page branches "$(filler_b release/6070-y)"
add_page branches "$(filler_b release/6070-z)"
add_page pulls "$(filler_p)"
expect_close "S599/C control, non-matching pages only" 607 9002

# S600 — a failed query leaves the epic open, loudly (eight shapes).
for m in fail empty malformed 403; do
  setup_epic 607; set_mode branches "$m"
  expect_failed_query "S600/branch $m" 607 9002 branch
  setup_epic 607; set_mode pulls "$m"
  expect_failed_query "S600/PR $m" 607 9002 open-PR
done
setup_epic 607
expect_close "S600/e control, two well-formed empty lists" 607 9002

# S601 — epics that do not reach the close issue no release query, and the
# straight-to-main epic still closes on the default api answer (S102 above
# already keeps its outcome under that default).
setup_epic 70 9001 9002; set_issue_list '[{"number":70,"state":"OPEN","body":"epic"},{"number":9001,"state":"CLOSED","body":"**Epic:** #70"},{"number":9002,"state":"OPEN","body":"**Epic:** #70"}]'
set_body 9001 "**Epic:** #70"
expect_open "S601/open child" 70 9001
set_body 9003 "**Epic:** #71"; set_state 71 OPEN; set_issue_list '[{"number":71,"state":"OPEN","body":"epic"}]'
expect_open "S601/no children" 71 9003
set_body 9004 "**Epic:** #72"; set_state 72 CLOSED
expect_open "S601/already closed" 72 9004
set_body 9005 "**Epic:** #9005"
expect_open "S601/self-reference" 9005 9005
set_body 9006 "**Epic:** #99999"
expect_open "S601/dangling" 99999 9006
[ -z "$(api_log)" ] || fail "S601 — a release query was issued for an epic that was not about to close: $(api_log)"
setup_epic 80
expect_close "S601/straight-to-main epic" 80 9002

# S602 — nothing escaped to a real gh.
[ ! -s "$SANDBOX/sentinel-calls" ] || fail "S602 — a case reached real gh: $(cat "$SANDBOX/sentinel-calls")"

# S603 — the workflow token carries pull-requests: read and nothing more.
perms="$(awk '/^    permissions:/{f=1;next} f&&/^      [a-z-]+:/{print $1 $2;next} f{exit}' "$TEST_REPO_ROOT/.github/workflows/epic-auto-close.yml" | sort | tr '\n' ' ')"
[ "$perms" = "contents:read issues:write pull-requests:read " ] \
  || fail "S603 — workflow permissions are not exactly contents:read, issues:write, pull-requests:read (got: $perms)"

test_done

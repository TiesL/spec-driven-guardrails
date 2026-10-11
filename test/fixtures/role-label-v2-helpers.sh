#!/usr/bin/env bash
# Private REST adapter for the public staleness CLI; real jq evaluates its argv.
sandbox_create
trap sandbox_destroy EXIT
export ROLE_V2_DATA="$SANDBOX/data" ROLE_V2_LOG="$SANDBOX/calls" ROLE_V2_UNEXPECTED="$SANDBOX/unexpected"
mkdir -p "$ROLE_V2_DATA" "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ROLE_V2_LOG"
[ "${1:-}" = api ] || { printf '%s\n' "$*" >> "$ROLE_V2_UNEXPECTED"; exit 1; }
endpoint="$2"; shift 2
case "$endpoint" in
 repos/\{owner\}/\{repo\}) file=repo;;
 repos/\{owner\}/\{repo\}/issues/400) file=issue;;
 repos/\{owner\}/\{repo\}/issues/400/comments) file=issue-comments;;
 repos/\{owner\}/\{repo\}/issues/400/timeline) file=timeline;;
 repos/\{owner\}/\{repo\}/pulls/501) file=pr;;
 repos/\{owner\}/\{repo\}/pulls/502) file=pr2;;
 repos/\{owner\}/\{repo\}/issues/502/comments) file=comments2;;
 repos/\{owner\}/\{repo\}/pulls/502/reviews) file=reviews2;;
 repos/\{owner\}/\{repo\}/issues/501/comments) file=comments;;
 repos/\{owner\}/\{repo\}/pulls/501/reviews) file=reviews;;
 *) printf '%s\n' "$endpoint" >> "$ROLE_V2_UNEXPECTED"; exit 1;;
esac
while [ "$#" -gt 0 ]; do
 case "$1" in --paginate) shift;; --jq) query="$2"; shift 2;; *) printf '%s\n' "$*" >> "$ROLE_V2_UNEXPECTED"; exit 1;; esac
done
exec jq -r "$query" "$ROLE_V2_DATA/$file.json"
GH
chmod +x "$SANDBOX/bin/gh"
r_good='<!-- model-record: stage=Review model="claude-sonnet-5" -->'
r_bad='<!-- model-record: stage=Review-->'
r_early=2026-10-01T10:00:00Z
r_late=2026-10-01T11:00:00Z
r_script="${ROLE_V2_SCRIPT:-$TEST_REPO_ROOT/role-label-staleness.sh}"
r_rows() {
 local file="$1"; shift
 jq -n '$ARGS.positional as $a | [range(0;($a|length);2) as $i | {created_at:$a[$i],submitted_at:$a[$i],body:$a[$i+1]}]' --args "$@" > "$ROLE_V2_DATA/$file.json"
}
r_issue() { jq -n --arg label "$1" --arg body "${2:-}" --arg time "${3:-$r_early}" '{body:$body,created_at:$time,updated_at:"2026-12-01T00:00:00Z",labels:[{name:$label}]}' > "$ROLE_V2_DATA/issue.json"; }
r_pr() { jq -n --arg body "$1" --arg time "${2:-$r_early}" '{title:"Closes #400",body:$body,created_at:$time,updated_at:"2026-12-01T00:00:00Z"}' > "$ROLE_V2_DATA/pr.json"; }
r_base() {
 : > "$ROLE_V2_LOG"; : > "$ROLE_V2_UNEXPECTED"
 r_issue role:architect
 printf '{"full_name":"owner/repo"}\n' > "$ROLE_V2_DATA/repo.json"
 printf '[]\n' > "$ROLE_V2_DATA/timeline.json"
 r_pr ''; r_rows issue-comments; r_rows comments; r_rows reviews; r_rows comments2; r_rows reviews2
 cp "$ROLE_V2_DATA/pr.json" "$ROLE_V2_DATA/pr2.json"
}
r_link() { printf '[{"event":"cross-referenced","source":{"issue":{"number":501,"repository":{"full_name":"owner/repo"},"pull_request":{}}}}]\n' > "$ROLE_V2_DATA/timeline.json"; }
r_run() {
 r_out="$(PATH="${r_path:-$SANDBOX/bin:$PATH}" /bin/bash "$r_script" 400 2> "$SANDBOX/stderr")"; r_rc=$?
 [ "$r_rc" -eq 0 ] || fail "CLI exit $r_rc: $(cat "$SANDBOX/stderr")"
 [ "$(printf '%s\n' "$r_out" | wc -l | tr -d ' ')" = 1 ] || fail "stdout not one line: $r_out"
 case "$r_out" in 'role-label-staleness: issue #400 — '*' ('*')') :;; *) fail "CLI shape: $r_out";; esac
 [ ! -s "$ROLE_V2_UNEXPECTED" ] || fail "unmatched REST call: $(cat "$ROLE_V2_UNEXPECTED")"
 for endpoint in issues/400 issues/400/comments issues/400/timeline; do
  grep -F "$endpoint " "$ROLE_V2_LOG" >/dev/null || fail "not reached: $endpoint"
 done
}
r_has() { case "$r_out" in *"$1"*) :;; *) fail "missing '$1': $r_out";; esac; }
r_absent() { case "$r_out" in *"$1"*) fail "unexpected '$1': $r_out";; esac; }
r_status() { r_has " — $1 ("; }

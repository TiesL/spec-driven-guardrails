#!/usr/bin/env bash
# Private REST fixture: real jq evaluates production query strings.
sandbox_create
trap sandbox_destroy EXIT
. "$TEST_REPO_ROOT/test/compliance-evidence-fixture.sh"
export CV_DATA="$SANDBOX/data" CV_LOG="$SANDBOX/calls" CV_UNEXPECTED="$SANDBOX/unexpected"
mkdir -p "$CV_DATA" "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CV_LOG"
[ "${1:-}" = api ] || exit 1
endpoint="$2"; shift 2
case "$endpoint" in
 repos/\{owner\}/\{repo\}/pulls/279|repos/\{owner\}/\{repo\}/pulls/280) file=pr;;
 repos/\{owner\}/\{repo\}/issues/279/comments|repos/\{owner\}/\{repo\}/issues/280/comments) file=comments;;
 repos/\{owner\}/\{repo\}/pulls/279/reviews|repos/\{owner\}/\{repo\}/pulls/280/reviews) file=reviews;;
 repos/\{owner\}/\{repo\}/issues/265/comments) file=issue265;;
 repos/\{owner\}/\{repo\}/issues/266/comments) file=issue266;;
 repos/\{owner\}/\{repo\}/commits/*/check-runs) file=checks;;
 *) printf '%s\n' "$endpoint" >> "$CV_UNEXPECTED"; exit 1;;
esac
while [ "$#" -gt 0 ]; do
 case "$1" in --paginate) shift;; --jq) query="$2"; shift 2;; *) printf '%s\n' "$*" >> "$CV_UNEXPECTED"; exit 1;; esac
done
exec jq -r "$query" "$CV_DATA/$file.json"
GH
chmod +x "$SANDBOX/bin/gh"
cv_early=2026-10-01T10:00:00Z
cv_late=2026-10-01T11:00:00Z
cv_model=claude-sonnet-5
cv_mark() { printf '<!-- model-record: stage=%s model="%s" -->' "$1" "${2:-$cv_model}"; }
cv_pr() {
 jq -n --arg body "$1" --arg title "${2:-}" --arg t "${3:-$cv_early}" '{head:{sha:"6e00a8c38bf18f19cd53084b5c77ae476c1e74e6"},state:"open",title:$title,body:$body,created_at:$t,updated_at:"2027-01-01T00:00:00Z"}' > "$CV_DATA/pr.json"
}
cv_rows() {
 local file="$1"; shift
 jq -n '$ARGS.positional as $a | [range(0;($a|length);2) as $i | {created_at:$a[$i],submitted_at:$a[$i],body:$a[$i+1]}]' --args "$@" > "$CV_DATA/$file.json"
}
cv_base() {
 : > "$CV_LOG"; : > "$CV_UNEXPECTED"
 cv_pr "$(cv_mark Discovery)
$(cv_mark Planning)
$(cv_mark Test)
$(cv_mark Implementation)"
 cv_rows comments "$cv_early" "$(cv_mark Review)"; cv_rows reviews; cv_rows issue265; cv_rows issue266
 printf '{"check_runs":[]}\n' > "$CV_DATA/checks.json"
}
cv_run() {
 : > "$CV_LOG"; : > "$CV_UNEXPECTED"
 cv_out="$(PATH="$SANDBOX/bin:$PATH" /bin/bash "${CV_SCRIPT:-$TEST_REPO_ROOT/compliance-evidence.sh}" "${1:-279}" 2> "$SANDBOX/stderr")"; cv_rc=$?
 [ "$cv_rc" -eq 0 ] || fail "collector exit $cv_rc: $(cat "$SANDBOX/stderr")"
 assert_table_shape CV "$cv_out"
 [ ! -s "$CV_UNEXPECTED" ] || fail "unmatched endpoint $(cat "$CV_UNEXPECTED")"
 for endpoint in pulls/"${1:-279}" issues/"${1:-279}"/comments pulls/"${1:-279}"/reviews check-runs; do
  [ "$(grep -cF "$endpoint " "$CV_LOG")" -eq 1 ] || fail "endpoint not consumed exactly once: $endpoint"
 done
}
cv_status() { [ "$(row_status "$cv_out" "$1")" = "$2" ] || fail "gate $1 expected $2: $cv_out"; }
cv_has() { case "$(row_evidence "$cv_out" "$1")" in *"$2"*) :;; *) fail "gate $1 missing $2: $cv_out";; esac; }
cv_absent() { case "$(row_evidence "$cv_out" "$1")" in *"$2"*) fail "gate $1 unexpected $2: $cv_out";; esac; }

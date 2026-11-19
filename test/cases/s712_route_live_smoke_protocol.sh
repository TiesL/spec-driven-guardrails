#!/usr/bin/env bash
# S712 — Live smoke test through the real proxy: protocol checked mechanically, a PASS or FAIL claim needs a complete, plausible record (#707; AC12)
# Covers: F75
#
# Seam: the structure of test/behavior/model-routing-smoke.md only. Nothing
# real runs here: no claude, codex, curl to the proxy, sqlite3 or network
# call. The recorded PASS or FAIL is the maintainer-side orchestrator's claim,
# backed by the #707 comment; no scenario here establishes it. Either state of
# the real file passes when it is consistent; the case does not pin which.
# Mutants run against a synthetic UNRUN and a synthetic PASS baseline built
# from the real file, so results do not depend on which state it is in.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

P="$TEST_REPO_ROOT/test/behavior/model-routing-smoke.md"
[ -f "$P" ] || { fail "S712 — test/behavior/model-routing-smoke.md does not exist"; test_done; }

# check <file>: one line per structural problem; empty when the protocol holds.
check() {
  python3 -I - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
flat = re.sub(r"\s+", " ", text)
problems = []
m = re.search(r"^Status: \*\*([A-Z]+)\*\*", text, re.M)
if not m:
    problems.append("no 'Status: **...**' line")
    status = None
else:
    status = m.group(1)
    if text.find(m.group(0)) > 400:
        problems.append("Status line is not among the first lines")
if status not in ("UNRUN", "PASS", "FAIL"):
    problems.append("status is not UNRUN, PASS or FAIL: %s" % status)
record = {}
for field in ("Date", "Head SHA", "Proxy version", "Row ids"):
    r = re.search(r"^- %s: *(.*)$" % re.escape(field), text, re.M)
    if not r:
        problems.append("record field '%s' is missing" % field)
    record[field] = (r.group(1).strip() if r else "")
filled = [f for f, v in record.items() if v and v.lower() not in ("none", "-", "n/a")]
if status in ("PASS", "FAIL") and len(filled) != 4:
    problems.append("status %s claimed without date, head SHA, proxy version and row ids" % status)
if status in ("PASS", "FAIL"):
    plausible = {
        "Date": r"\d{4}-\d{2}-\d{2}",
        "Head SHA": r"[0-9a-f]{40}",
        "Proxy version": r".*\d+\.\d+\.\d+.*",
        "Row ids": r"\d+(-\d+)?(, ?\d+(-\d+)?)*",
    }
    for f, rx in plausible.items():
        v = record[f]
        if v and v.lower() in ("none", "-", "n/a"):
            continue  # already reported as missing evidence above
        if not re.fullmatch(rx, v):
            problems.append("record field '%s' is implausible: %r" % (f, v))
if status == "UNRUN" and filled:
    problems.append("UNRUN but evidence is recorded: %s" % ", ".join(filled))
# The steps, in this order.
steps = [
    ("precondition: routing on", r"process-model-routing.{0,40}\byes\b"),
    ("precondition: proxy listening", r"proxy.{0,60}listen"),
    ("contract file", r"copy of `?skills/role-contracts/SKILL\.md"),
    ("claude child", r"route-child\.sh\"? claude -- claude -p --model haiku"),
    ("codex child", r"route-child\.sh\"? codex -- codex exec --ephemeral"),
    ("codex off", r"SDG_MODEL_ROUTE=off \"?\$?[A-Za-z_{}\"/]*route-child\.sh\"? codex -- codex exec"),
    ("read-only counts", r"read-only.{0,80}caveman\.db.{0,80}requests"),
]
pos = 0
for name, rx in steps:
    s = re.search(rx, flat[pos:], re.I)
    if not s:
        problems.append("step missing or out of order: " + name)
    else:
        pos += s.end()
for name, rx in [
    ("no contents", r"never read request or response contents"),
    ("provider anthropic", r"provider `?anthropic`?"),
    ("provider chatgpt-subscription", r"provider `?chatgpt-subscription`?"),
    ("eligibility", r"compression_eligible ?= ?0"),
    ("equal hashes", r"raw_request_sha256.{0,40}equals.{0,40}transformed_request_sha256"),
    ("no orchestrator row", r"no row for the Orchestrator"),
    ("off adds zero rows", r"off.{0,60}adds zero rows"),
    ("no elision marker", r"no elision marker"),
    ("not in check", r"not run by `?\./check`? or CI"),
]:
    if not re.search(rx, flat, re.I):
        problems.append("pass condition or rule missing: " + name)
if re.search(r"select \*|request_body|response_body", flat, re.I):
    problems.append("the protocol reads contents")
print("\n".join(problems))
PY
}

# Baselines: the real file with the Status word and the four record fields set.
# base <out> <status> <date> <sha> <version> <rows>
base() {
  python3 -I - "$P" "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
st, date, sha, ver, rows = sys.argv[3:8]
t = re.sub(r"^Status: \*\*[A-Z]+\*\*", "Status: **%s**" % st, t, count=1, flags=re.M)
for f, v in (("Date", date), ("Head SHA", sha), ("Proxy version", ver), ("Row ids", rows)):
    t = re.sub(r"^- %s: .*$" % f, lambda m: "- %s: %s" % (f, v), t, count=1, flags=re.M)
open(sys.argv[2], "w", encoding="utf-8").write(t)
PY
}
GOODSHA=4525fc501410075ec14633d90311a512a9515350
base "$SANDBOX/unrun.md" UNRUN none none none none
base "$SANDBOX/pass.md" PASS 2026-11-19 "$GOODSHA" "4.1.0 (bin-v4.1.0)" 3708-3713

# Positive controls: the real file and both synthetic baselines are clean.
for c in "$P" "$SANDBOX/unrun.md" "$SANDBOX/pass.md"; do
  got="$(check "$c")"
  [ -z "$got" ] || fail "S712 — the protocol does not hold (${c##*/}):
$got"
done

MUTANTS=0
# mutant <label> <baseline file> <python expression over text t>: must be caught.
mutant() {
  MUTANTS=$((MUTANTS + 1))
  python3 -I - "$2" "$SANDBOX/m.md" "$3" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
t = eval(sys.argv[3])
open(sys.argv[2], "w", encoding="utf-8").write(t)
PY
  [ -n "$(check "$SANDBOX/m.md")" ] || fail "S712/neg — '$1' was not caught"
}
# accept <label> <baseline file> <python expression>: must stay clean.
accept() {
  MUTANTS=$((MUTANTS + 1))
  python3 -I - "$2" "$SANDBOX/m.md" "$3" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
t = eval(sys.argv[3])
open(sys.argv[2], "w", encoding="utf-8").write(t)
PY
  [ -z "$(check "$SANDBOX/m.md")" ] || fail "S712/pos — '$1' was wrongly rejected"
}
PASSF="$SANDBOX/pass.md"
UNRUNF="$SANDBOX/unrun.md"
for f in "Date" "Head SHA" "Proxy version" "Row ids"; do
  mutant "pass-$f-none" "$PASSF" "__import__('re').sub(r'^- $f: .*\$', '- $f: none', t, count=1, flags=__import__('re').M)"
done
mutant pass-all-none "$PASSF" "t.replace('2026-11-19','none').replace('$GOODSHA','none').replace('4.1.0 (bin-v4.1.0)','none').replace('3708-3713','none')"
mutant pass-sha-39 "$PASSF" "t.replace('$GOODSHA', '${GOODSHA:1}')"
mutant pass-sha-nonhex "$PASSF" "t.replace('$GOODSHA', 'g${GOODSHA:1}')"
mutant pass-sha-upper "$PASSF" "t.replace('$GOODSHA', '$GOODSHA'.upper())"
mutant pass-sha-short "$PASSF" "t.replace('$GOODSHA', '4525fc5')"
mutant pass-date-dmy "$PASSF" "t.replace('2026-11-19', '19-11-2026')"
mutant pass-version-latest "$PASSF" "t.replace('4.1.0 (bin-v4.1.0)', 'latest')"
mutant pass-version-two-part "$PASSF" "t.replace('4.1.0 (bin-v4.1.0)', '4.1')"
mutant pass-rows-abc "$PASSF" "t.replace('3708-3713', 'abc')"
mutant pass-rows-none "$PASSF" "t.replace('3708-3713', 'none')"
mutant pass-rows-open-range "$PASSF" "t.replace('3708-3713', '3708-')"
mutant pass-rows-negative "$PASSF" "t.replace('3708-3713', '-3')"
mutant fail-with-none "$PASSF" "t.replace('Status: **PASS**', 'Status: **FAIL**').replace('3708-3713', 'none')"
mutant pass-no-status-line "$PASSF" "t.replace('Status: **PASS**', 'Status is fine')"
mutant status-passed "$PASSF" "t.replace('Status: **PASS**', 'Status: **PASSED**')"
mutant status-maybe "$PASSF" "t.replace('Status: **PASS**', 'Status: **MAYBE**')"
mutant status-late "$PASSF" "t.replace('Status: **PASS**', 'x').replace('## Preconditions', 'Status: **PASS**\n## Preconditions')"
mutant status-late-pad "$PASSF" "t.replace('Status: **PASS**', 'x' * 450 + '\nStatus: **PASS**', 1)"
for f in "Date:2026-11-19" "Head SHA:$GOODSHA" "Proxy version:4.1.0" "Row ids:3708-3713"; do
  mutant "unrun-with-${f%%:*}" "$UNRUNF" "__import__('re').sub(r'^- ${f%%:*}: .*\$', '- ${f%%:*}: ${f#*:}', t, count=1, flags=__import__('re').M)"
done
accept pass-rows-list "$PASSF" "t.replace('3708-3713', '3708-3710, 3711-3713')"
accept pass-rows-single "$PASSF" "t.replace('3708-3713', '3708')"
accept pass-version-prefixed "$PASSF" "t.replace('4.1.0 (bin-v4.1.0)', 'Caveman 4.1.0')"
accept fail-complete "$PASSF" "t.replace('Status: **PASS**', 'Status: **FAIL**')"
# Unchanged against the real file.
mutant drop-off-zero "$P" 't.replace("adds zero rows", "adds rows")'
mutant drop-orchestrator "$P" 't.replace("no row for the Orchestrator", "rows")'
mutant drop-hashes "$P" 't.replace("equals", "and")'
mutant drop-marker "$P" 't.replace("no elision marker", "nothing")'
mutant reads-contents "$P" 't + "\nSELECT * FROM requests;\n"'
mutant drop-no-contents "$P" 't.replace("Never read request or response contents", "read anything")'
[ "$MUTANTS" -ge 30 ] || fail "S712 — the mutant loop ran only $MUTANTS times (guard: at least 30)"

# No case of this work item starts a real model, Codex or the proxy.
for f in "$TEST_REPO_ROOT"/test/cases/s70[0-9]_*.sh "$TEST_REPO_ROOT"/test/cases/s71[0-3]_*.sh; do
  hit="$(grep -nE '(^|[;&|(]|\$\()[[:space:]]*(claude|codex|caveman|caveman-proxy|sqlite3)([[:space:]]|$)' "$f" | grep -v '^[0-9]*:[[:space:]]*#')"
  [ -z "$hit" ] || fail "S712 — ${f#"$TEST_REPO_ROOT"/} starts a real model, Codex, the proxy or sqlite3: $hit"
done

test_done

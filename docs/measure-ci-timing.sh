#!/usr/bin/env bash
# docs/measure-ci-timing.sh — Read-only CI timing measurement (#563 AC1/AC2/AC4).
#
# Rerunnable record of how long the `CI` and `CI macOS` workflows take: per job
# and per step durations, queue time, wall time, the static-checks versus
# test-suite split inside the `./check` step, and per-test duration sums
# reconstructed from the `ok <name>` completion lines. Only reads (`gh run
# list`, `gh run view`, `git ls-tree`); it changes nothing in GitHub or in the repo.
# Lives in docs/ because the repo has no other measurement helper and docs/
# already holds the repo's recorded evidence.
#
# Usage:
#   docs/measure-ci-timing.sh runs [WORKFLOW] [LIMIT]       # default: CI, 20
#       per-job/per-step min/median/max/spread over the last LIMIT successful runs
#   docs/measure-ci-timing.sh log RUN_ID [ATTEMPT] [WORKERS]
#       phase split and per-test sums for one run attempt (WORKERS: 4 Linux, 3 macOS)
#   docs/measure-ci-timing.sh counts [SHA...]               # test/cases files per commit
#
# Environment: REPO (default TiesL/spec-driven-guardrails). Needs gh, jq, python3.
# Per-test durations assume test/run.sh starts cases in byte order of their
# names, WORKERS at a time, as each slot frees (xargs -P); start of case i is
# the completion of the (i-WORKERS)th finished case. A negative value would
# mean the assumption failed and is reported.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

REPO="${REPO:-TiesL/spec-driven-guardrails}"
mode="${1:-}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "measure-ci-timing: $1 is required" >&2; exit 1; }; }
need gh; need jq; need python3

case "$mode" in
  runs)
    workflow="${2:-CI}"
    limit="${3:-20}"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    gh run list -R "$REPO" --workflow "$workflow" --status success --limit "$limit" \
      --json databaseId,createdAt,updatedAt,event,headBranch,headSha > "$tmp/runs.json" || exit 1
    for id in $(jq -r '.[].databaseId' "$tmp/runs.json"); do
      gh run view -R "$REPO" "$id" --json jobs > "$tmp/job_$id.json" || exit 1
    done
    python3 -I - "$tmp" <<'PY'
import json, glob, os, sys, statistics
from datetime import datetime
d = sys.argv[1]
t = lambda s: datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
runs = json.load(open(os.path.join(d, "runs.json")))
rows = {}
def add(k, v): rows.setdefault(k, []).append(v)
for r in runs:
    j = json.load(open(os.path.join(d, "job_%d.json" % r["databaseId"])))["jobs"][0]
    add("wall (run created -> updated)", (t(r["updatedAt"]) - t(r["createdAt"])).total_seconds())
    add("queue (run created -> job started)", (t(j["startedAt"]) - t(r["createdAt"])).total_seconds())
    add("job total", (t(j["completedAt"]) - t(j["startedAt"])).total_seconds())
    for s in j["steps"]:
        add("step: " + s["name"], (t(s["completedAt"]) - t(s["startedAt"])).total_seconds())
print("runs: %d (%s); events: %s" % (len(runs), ", ".join(str(r["databaseId"]) for r in runs[:3]) + ", ...",
      ", ".join("%s=%d" % (e, sum(1 for r in runs if r["event"] == e)) for e in sorted(set(r["event"] for r in runs)))))
print("%-44s %6s %6s %6s %7s" % ("seconds", "min", "median", "max", "spread"))
for k, v in rows.items():
    print("%-44s %6d %6d %6d %7d" % (k, min(v), statistics.median(v), max(v), max(v) - min(v)))
PY
    ;;
  log)
    id="${2:?run id}"
    attempt="${3:-}"
    workers="${4:-4}"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    if [ -n "$attempt" ]; then
      gh run view -R "$REPO" "$id" --attempt "$attempt" --log > "$tmp" || exit 1
    else
      gh run view -R "$REPO" "$id" --log > "$tmp" || exit 1
    fi
    python3 -I - "$tmp" "$workers" <<'PY'
import re, sys, statistics
from datetime import datetime
log, W = sys.argv[1], int(sys.argv[2])
ts = lambda s: datetime.strptime(s[:26], "%Y-%m-%dT%H:%M:%S.%f").timestamp()
marks, oks, region, tests = {}, [], "?", ""
for line in open(log, errors="replace"):
    parts = line.rstrip("\n").split("\t", 2)
    if len(parts) < 3: continue
    m = re.match(r"(\d{4}-\d\d-\d\dT[\d:.]+)Z (.*)$", parts[2].replace("\r", "").replace("\ufeff", ""))
    if not m: continue
    when, text = ts(m.group(1)), m.group(2)
    if text.startswith("Region:"): region = text.split(None, 1)[1]
    for key in ("check: bash -n", "check: shellcheck", "check: test suite"):
        if text == key: marks[key] = when
    if text.startswith("Tests:"): marks["end"] = when; tests = text
    mo = re.match(r"  ok    (\S+)$", text)
    if mo: oks.append((when, mo.group(1)))
    if re.match(r"  FAIL  \S+$", text): print("FAIL line:", text)
if "check: test suite" in marks:
    t0, ts_, te = marks.get("check: bash -n"), marks["check: test suite"], marks["end"]
    sc = marks.get("check: shellcheck")
    print("region %s; %s" % (region, tests))
    if t0 and sc: print("static checks before shellcheck: %.0f s; outer shellcheck: %.0f s" % (sc - t0, ts_ - sc))
    print("test suite: %.0f s; static share of ./check: %.1f%%" % (te - ts_, 100.0 * (ts_ - t0) / (te - t0) if t0 else 0))
else:
    print("region %s; %s (no 'check: test suite' marker: macOS-style log, suite measured from first ok line)" % (region, tests))
    ts_ = min(w for w, _ in oks) if oks else 0
oks.sort()
start_of_suite = ts_
completion = {n: w for w, n in oks}
glob_order = sorted(completion)
by_time = [n for w, n in oks]
dur, negative = {}, 0
for i, n in enumerate(glob_order):
    start = start_of_suite if i < W else completion[by_time[i - W]]
    dur[n] = completion[n] - start
    if dur[n] < 0: negative += 1
total = sum(dur.values())
span = max(completion.values()) - start_of_suite
heavy = [n for n in dur if re.match(r"(s124|s112|s39|s2|s121|s40|s41|s32|s5|s92|s274|s35|s1|s93)_", n)]
print("cases: %d; sum of per-test time: %.0f s; busy workers: %.2f of %d; negative durations: %d"
      % (len(dur), total, total / span if span else 0, W, negative))
print("the 14 check-calling cases (s124 s112 s39 s2 s121 s40 s41 s32 s5 s92 s274 s35 s1 s93): %.0f s = %.0f%% of the sum"
      % (sum(dur[n] for n in heavy), 100.0 * sum(dur[n] for n in heavy) / total if total else 0))
if negative: print("WARNING: %d negative durations: the glob-order assumption failed (macOS sorts by locale); per-test values below are NOT reliable, only the sum and busy workers are" % negative)
for p in ("s124_", "s2_", "s39_"):
    for n in sorted(dur):
        if n.startswith(p): print("  %-40s %6.0f s" % (n, dur[n]))
rest = [v for n, v in dur.items() if n not in heavy]
if rest: print("other %d cases: mean %.1f s, median %.1f s" % (len(rest), statistics.mean(rest), statistics.median(rest)))
PY
    ;;
  counts)
    shift
    for sha in "$@"; do
      printf '%s %s\n' "$sha" "$(gh api "repos/$REPO/git/trees/$sha?recursive=1" \
        --jq '[.tree[] | select(.path | test("^test/cases/[^/]+\\.sh$"))] | length')"
    done
    ;;
  *)
    sed -n '/^# Usage:/,/^# Environment/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d' >&2
    exit 2
    ;;
esac

#!/usr/bin/env python3
"""Differential runner for the orchestrator behavior scenarios (#499, A41).

Subcommands:
  check-scenarios  parse the scenario file against the closed schema
  stamp-check      compare the committed stamp with the current hashes
  run              compare the old and new ORCHESTRATOR.md on every scenario

The pure core (parse_scenarios, majority, verdict, mutate) takes data and
returns data; the adapter (run_claude) is the only code that starts `claude`
(or the stub named by CLAUDE_BIN). Python 3.9-compatible. Never uses `timeout`
(macOS has none).
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

ORCH_REL = "skills/role-contracts/ORCHESTRATOR.md"
SCEN_REL = "test/behavior/orchestrator-scenarios.md"
STAMP_REL = "test/behavior/orchestrator-diff.stamp"
MARKER = "<!-- session-context: slot -->"

ROLES = ["Product", "Architect", "QA", "Fullstack Developer", "Reviewer", "none"]
SCHEMA = {
    "next_action": ["dispatch", "continue_agent", "merge", "ask_human", "stop",
                    "answer_directly", "comply_and_record", "self_check",
                    "record_decision"],
    "next_role": ROLES,
    "starts_pipeline": ["true", "false"],
    "asks_human": ["true", "false"],
    "low_finding": ["fix_in_pr", "defer", "file_issue_now"],
    "model_choice": ["same_or_stronger", "weaker"],
    "run_scope": ["affected", "full", "hooks_only", "none"],
}

HEAD_RE = re.compile(r"^### (OB\d+) · (OR\d+(?:, OR\d+)*)$")
ITEM_RE = re.compile(r"^- (OB\d+) \((OR\d+(?:, OR\d+)*)\): (.*)$")
OR_RE = re.compile(r"\bOR\d+\b")


# --- pure core ---------------------------------------------------------------

def parse_scenarios(text, known_ids=None):
    """Return (scenarios, intended, errors).

    scenarios: ordered list of dicts {id, rules, given, when, then}; intended:
    dict OB -> rule list; errors: list of strings, each naming the defect.
    known_ids: set of existing OR IDs, or None to skip the existence check.
    """
    errors = []
    lines = text.split("\n")
    intended_at = None
    for i, line in enumerate(lines):
        if line.strip() == "## Intended changes":
            intended_at = i
            break
    body = lines if intended_at is None else lines[:intended_at]

    scenarios = []
    seen = {}
    cur = None

    def close_block():
        if cur is None:
            return
        name = cur["id"]
        for key in ("given", "when", "then"):
            if cur[key] is None:
                errors.append("%s: missing %s:" % (name, key.capitalize()))
        scenarios.append(cur)

    for line in body:
        if line.startswith("## "):
            close_block()
            cur = None
            continue
        if line.startswith("### "):
            close_block()
            cur = None
            if not line.startswith("### OB"):
                continue
            m = HEAD_RE.match(line)
            if not m:
                errors.append("malformed scenario heading: %s" % line)
                continue
            ob = m.group(1)
            if ob in seen:
                errors.append("%s: duplicate scenario number" % ob)
            seen[ob] = True
            cur = {"id": ob, "rules": m.group(2).split(", "), "given": None,
                   "when": None, "then": None, "then_raw": None}
            if known_ids is not None:
                for r in cur["rules"]:
                    if r not in known_ids:
                        errors.append("%s: cites unknown rule %s" % (ob, r))
            continue
        if cur is None or not line.strip():
            continue
        m = re.match(r"^(Given|When|Then): (.*)$", line)
        if not m:
            errors.append("%s: unexpected line: %s" % (cur["id"], line))
            continue
        key = m.group(1).lower()
        if cur[key] is not None:
            errors.append("%s: %s: given twice" % (cur["id"], m.group(1)))
            continue
        cur[key] = m.group(2)
    close_block()

    for sc in scenarios:
        for key in ("given", "when"):
            if sc[key] is not None:
                m = OR_RE.search(sc[key])
                if m:
                    errors.append("%s: %s cites rule ID %s" %
                                  (sc["id"], key.capitalize(), m.group(0)))
        if sc["then"] is not None:
            sc["then_fields"], terrs = parse_then(sc["then"])
            for e in terrs:
                errors.append("%s: %s" % (sc["id"], e))
        else:
            sc["then_fields"] = {}

    intended = {}
    if intended_at is not None:
        by_id = dict((s["id"], s) for s in scenarios)
        items = []
        for line in lines[intended_at + 1:]:
            if line.startswith("## "):
                errors.append("Intended changes is not the last section "
                              "(found: %s)" % line)
                break
            if line.startswith("- "):
                items.append([line])
            elif items and line.startswith((" ", "\t")) and line.strip():
                items[-1].append(line.strip())
            elif not line.strip():
                if items:
                    items[-1].append("")
        for it in items:
            first = it[0]
            m = ITEM_RE.match(first)
            if not m:
                errors.append("intended: malformed item: %s" % first)
                continue
            ob, rules, _ = m.group(1), m.group(2).split(", "), m.group(3)
            full = " ".join(x for x in it if x)
            if ob in intended:
                errors.append("%s: listed twice under Intended changes" % ob)
                continue
            if ob not in by_id:
                errors.append("intended: %s does not exist" % ob)
                continue
            if rules != by_id[ob]["rules"]:
                errors.append("intended: %s: OR list (%s) differs from the heading (%s)" %
                              (ob, ", ".join(rules), ", ".join(by_id[ob]["rules"])))
            if not re.search(r"#\d+", full):
                errors.append("intended: %s cites no #<n> decision" % ob)
            intended[ob] = rules
    return scenarios, intended, errors


def parse_then(raw):
    fields, errors = {}, []
    for part in raw.split(";"):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            errors.append("Then item without '=': %s" % part)
            continue
        k, v = part.split("=", 1)
        k, v = k.strip(), v.strip()
        if k not in SCHEMA:
            errors.append("Then field '%s' is not in the schema" % k)
            continue
        if v not in SCHEMA[k]:
            errors.append("Then %s=%s is not in the schema" % (k, v))
            continue
        fields[k] = v
    return fields, errors


def rule_ids(orch_text):
    ids = set()
    for line in orch_text.split("\n"):
        m = re.match(r"^\s*(?:[-*]\s+)?(OR\d+)\s", line)
        if m:
            ids.add(m.group(1))
    return ids


def majority(values, n):
    """Value reached by more than half of n runs, else None."""
    counts = {}
    for v in values:
        if v is not None:
            counts[v] = counts.get(v, 0) + 1
    for v, c in counts.items():
        if c * 2 > n:
            return v
    return None


def arm_majority(results, fields, n):
    """results: list of per-run dicts (or None). -> {field: value or None}."""
    out = {}
    for f in fields:
        vals = []
        for r in results:
            vals.append(str(r[f]).lower() if (r and f in r and isinstance(r[f], bool))
                        else (r.get(f) if r else None))
        out[f] = majority(vals, n)
    return out


def verdict(then, listed, old, new):
    """First match wins (A41)."""
    def equal(m):
        return all(m.get(f) == v for f, v in then.items())

    def unstable(m):
        return any(m.get(f) is None for f in then)

    if unstable(new):
        return "unstable"
    if listed and equal(new) and not equal(old):
        return "changed-as-intended"
    if unstable(old):
        return "unstable"
    if equal(old) and equal(new):
        return "same"
    if not equal(old):
        return "old-wrong"
    return "diverged"


def mutate(text, rule_id):
    """Remove one never/not from the item for rule_id. Returns (text, note).

    Raises ValueError when there is nothing to remove. When the text has no
    rule IDs at all (before the rewrite) the first line with never/not is used
    and the note says so.
    """
    lines = text.split("\n")
    note = ""
    target = None
    for i, line in enumerate(lines):
        if re.match(r"^\s*(?:[-*]\s+)?%s\s" % re.escape(rule_id), line):
            target = i
            break
    if target is None:
        if rule_ids(text):
            raise ValueError("rule %s not found in the new text" % rule_id)
        note = "no rule IDs in the text yet; mutated the first line with never/not"
        for i, line in enumerate(lines):
            if re.search(r"\b(never|not)\b", line, re.I):
                target = i
                break
    if target is None:
        raise ValueError("no never/not to remove")
    end = target + 1
    while end < len(lines) and lines[end].startswith((" ", "\t")) and lines[end].strip():
        end += 1
    for i in range(target, end):
        m = re.search(r"\s?\b(never|not)\b", lines[i], re.I)
        if m:
            lines[i] = lines[i][:m.start()] + lines[i][m.end():]
            return "\n".join(lines), note
    raise ValueError("rule %s has no never/not" % rule_id)


def drop_marker(text):
    return "\n".join(l for l in text.split("\n") if l.strip() != MARKER)


def schema_section(scen_text):
    lines = scen_text.split("\n")
    out, on = [], False
    for line in lines:
        if line.startswith("## Schema"):
            on = True
        elif on and line.startswith("## "):
            break
        if on:
            out.append(line)
    return "\n".join(out).rstrip("\n")


def build_preamble(scen_text):
    return (
        "# Behavior test preamble\n\n"
        "The rules above are your run rules. Each message gives a situation "
        "(Given) and a moment of decision (When). Decide the one next step "
        "your rules require, as the orchestrator, and answer only with the "
        "JSON object that matches the given schema. Read each field value "
        "as defined here.\n\n" + schema_section(scen_text) + "\n"
    )


def json_schema():
    props = {}
    for f, vals in SCHEMA.items():
        props[f] = {"type": "string", "enum": vals}
    props["reason"] = {"type": "string"}
    return json.dumps({"type": "object", "properties": props,
                       "required": list(SCHEMA) + ["reason"],
                       "additionalProperties": False})


def stamp_hash(orch_bytes, scen_bytes):
    return hashlib.sha256(orch_bytes + scen_bytes).hexdigest()


STAMP_RE = re.compile(r"^sha256=([0-9a-f]{64}) base=(\S+) model=(\S+) scenarios=(\d+)$")


# --- adapter -----------------------------------------------------------------

def run_claude(arm_file, prompt, model, scratch):
    """One call. Returns (fields dict or None, cost, resolved model or None)."""
    cmd = [os.environ.get("CLAUDE_BIN", "claude"), "-p", "--model", model,
           "--system-prompt-file", arm_file, "--tools", "",
           "--strict-mcp-config", "--setting-sources", "",
           "--settings", '{"disableAllHooks":true}',
           "--no-session-persistence", "--output-format", "json",
           "--json-schema", json_schema()]
    try:
        p = subprocess.run(cmd, input=prompt, cwd=scratch, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, universal_newlines=True)
    except OSError as e:
        sys.stderr.write("run: cannot start %s: %s\n" % (cmd[0], e))
        return None, 0.0, None
    try:
        data = json.loads(p.stdout)
    except ValueError:
        sys.stderr.write("run: not JSON (exit %d): %s\n" % (p.returncode, p.stdout[:200]))
        return None, 0.0, None
    cost = float(data.get("total_cost_usd") or 0.0)
    models = list((data.get("modelUsage") or {}).keys())
    out = data.get("structured_output")
    if data.get("is_error") or not isinstance(out, dict):
        return None, cost, (models[0] if models else None)
    return out, cost, (models[0] if models else None)


class Budget(Exception):
    pass


class Runner(object):
    def __init__(self, a_model, cap, n, scratch):
        self.model, self.cap, self.n, self.scratch = a_model, cap, n, scratch
        self.spent, self.calls, self.resolved = 0.0, 0, None

    def call(self, arm_file, prompt):
        if self.calls and self.spent + self.spent / self.calls > self.cap:
            raise Budget("budget cap USD %.2f reached after %d calls (spent %.4f); "
                         "stopping before the next call" % (self.cap, self.calls, self.spent))
        out, cost, model = run_claude(arm_file, prompt, self.model, self.scratch)
        self.calls += 1
        self.spent += cost
        if model and not self.resolved:
            self.resolved = model
        return out, cost

    def arm(self, arm_file, sc):
        prompt = "%s\n%s\n" % ("Given: " + sc["given"], "When: " + sc["when"])
        results, cost = [], 0.0
        for _ in range(self.n):
            out, c = self.call(arm_file, prompt)
            results.append(out)
            cost += c
        return arm_majority(results, sc["then_fields"].keys(), self.n), cost


# --- commands ----------------------------------------------------------------

def read(path):
    with open(path, "rb") as f:
        return f.read()


def cmd_check_scenarios(args):
    text = read(args.scenarios).decode("utf-8")
    known = None
    if args.orchestrator:
        known = rule_ids(read(args.orchestrator).decode("utf-8"))
        if not known:
            print("note: no rule IDs in %s yet; ID existence not checked" % args.orchestrator)
            known = None
    scenarios, intended, errors = parse_scenarios(text, known)
    for e in errors:
        print("ERROR: " + e)
    if errors:
        return 1
    print("scenarios=%d intended=%d" % (len(scenarios), len(intended)))
    return 0


def cmd_stamp_check(args):
    repo = os.path.abspath(args.repo)
    stamp_path = os.path.join(repo, STAMP_REL)
    if not os.path.isfile(stamp_path):
        print("stamp-check: no stamp yet (%s)" % STAMP_REL)
        return 0
    line = read(stamp_path).decode("utf-8").rstrip("\n")
    m = STAMP_RE.match(line)
    if not m or "\n" in line:
        print("stamp-check: malformed stamp: %s" % line)
        return 1
    orch = read(os.path.join(repo, ORCH_REL))
    scen = read(os.path.join(repo, SCEN_REL))
    if stamp_hash(orch, scen) != m.group(1):
        print("stamp-check: stale stamp: ORCHESTRATOR.md or the scenarios changed "
              "since the last passing differential run; run "
              "test/behavior/orchestrator-diff.sh again")
        return 1
    count = len(re.findall(r"^### OB\d+ ", scen.decode("utf-8"), re.M))
    if int(m.group(4)) != count:
        print("stamp-check: stamp says scenarios=%s, the file has %d" % (m.group(4), count))
        return 1
    print("stamp-check: stamp matches")
    return 0


def fmt_maj(m):
    return "; ".join("%s=%s" % (f, v if v is not None else "?") for f, v in m.items())


def cmd_run(args):
    repo = os.path.abspath(args.repo)
    scen_path = os.path.join(repo, SCEN_REL)
    orch_path = os.path.join(repo, ORCH_REL)
    scen_text = read(scen_path).decode("utf-8")
    scenarios, intended, errors = parse_scenarios(scen_text)
    if errors:
        for e in errors:
            sys.stderr.write("ERROR: %s\n" % e)
        return 2
    # The stamp records the commit the run compared against, not the ref text
    # (#542): origin/main moves, a SHA does not. An unresolvable base stops
    # the run before any stamp can be written.
    rp = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "--quiet",
                         "%s^{commit}" % args.base],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    base_sha = rp.stdout.decode("utf-8", "replace").strip()
    if rp.returncode != 0 or not base_sha:
        sys.stderr.write("run: cannot resolve --base %s to a commit in %s\n" % (args.base, repo))
        return 2
    p = subprocess.run(["git", "-C", repo, "show", "%s:%s" % (base_sha, ORCH_REL)],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        sys.stderr.write("run: cannot read %s at %s: %s\n" %
                         (ORCH_REL, args.base, p.stderr.decode("utf-8", "replace").strip()))
        return 2
    old_text = drop_marker(p.stdout.decode("utf-8"))
    new_raw = read(orch_path).decode("utf-8")
    if args.baseline or args.calibrate:
        new_text = old_text if args.baseline else drop_marker(new_raw)
    else:
        new_text = drop_marker(new_raw)
    preamble = build_preamble(scen_text)

    work = tempfile.mkdtemp(prefix="orch-diff-")
    scratch = os.path.join(work, "empty")
    os.mkdir(scratch)

    def write_arm(name, text):
        path = os.path.join(work, name)
        with open(path, "w") as f:
            f.write(text.rstrip("\n") + "\n\n" + preamble)
        return path

    old_file = write_arm("arm-old.txt", old_text)
    runner = Runner(args.model, args.max_budget_usd, args.runs, scratch)
    rows, status = [], None
    try:
        if args.calibrate:
            # A/A: old against old, the noise floor.
            aa_file = write_arm("arm-new.txt", old_text)
            aa = run_pairs(runner, scenarios, intended, old_file, aa_file, False)
            noisy = [r for r in aa if r["verdict"] != "same"]
            print("## Calibration, A/A noise floor (old against old)\n")
            print_table(aa, runner.resolved or "unknown")
            print("\nnoise floor: %d of %d scenarios not `same` in the old-against-old run.\n"
                  % (len(noisy), len(aa)))
            try:
                mut_text, note = mutate(drop_marker(new_raw), args.mutant_rule)
            except ValueError as e:
                sys.stderr.write("calibrate: %s\n" % e)
                return 2
            if note:
                sys.stderr.write("calibrate: %s\n" % note)
            mut_file = write_arm("arm-mut.txt", mut_text)
            targets = [s for s in scenarios if args.mutant_rule in s["rules"]] or scenarios
            mrows = []
            old_by_id = dict((r["id"], r["old"]) for r in aa)
            for sc in targets:
                mm, mc = runner.arm(mut_file, sc)
                mrows.append(make_row(sc, False, old_by_id[sc["id"]], mm, mc))
            print("## Calibration, mutant (%s with one never/not removed) against old\n" % args.mutant_rule)
            print_table(mrows, runner.resolved or "unknown")
            detected = [r for r in mrows if r["verdict"] == "diverged"]
            print("\nmutant detected: %s (%d of %d targeted scenarios diverged)" %
                  ("yes" if detected else "NO", len(detected), len(mrows)))
            footer(runner)
            return 0 if detected else 1
        rows = run_pairs(runner, scenarios, intended, old_file,
                         write_arm("arm-new.txt", new_text), args.baseline)
    except Budget as e:
        sys.stderr.write("run: %s\n" % e)
        footer(runner, sys.stderr)
        return 3
    print_table(rows, runner.resolved or "unknown")
    print("")
    footer(runner)
    if args.baseline:
        bad = [r for r in rows if not r["listed"] and r["verdict"] != "same"]
        print("baseline: %s" % ("pass" if not bad else
                                "FAIL, unlisted not `same`: " + ", ".join(r["id"] for r in bad)))
        print("listed scenarios are reported; their expected verdict here is old-wrong.")
        return 0 if not bad else 1
    ok = all(r["verdict"] in ("same", "changed-as-intended") for r in rows)
    if ok:
        digest = stamp_hash(read(orch_path), read(scen_path))
        line = "sha256=%s base=%s model=%s scenarios=%d\n" % (
            digest, base_sha, runner.resolved or "unknown", len(scenarios))
        tmp = os.path.join(repo, STAMP_REL + ".tmp")
        with open(tmp, "w") as f:
            f.write(line)
        os.replace(tmp, os.path.join(repo, STAMP_REL))
        print("stamp written: %s" % STAMP_REL)
    return 0 if ok else 1


def make_row(sc, listed, old, new, cost):
    return {"id": sc["id"], "old": old, "new": new, "then": sc["then_fields"],
            "listed": listed, "cost": cost,
            "verdict": verdict(sc["then_fields"], listed, old, new)}


def run_pairs(runner, scenarios, intended, old_file, new_file, baseline):
    rows = []
    for sc in scenarios:
        listed = sc["id"] in intended
        om, oc = runner.arm(old_file, sc)
        nm, nc = runner.arm(new_file, sc)
        rows.append(make_row(sc, listed, om, nm, oc + nc))
    return rows


def print_table(rows, model):
    print("| scenario | old | new | Then | verdict | model | cost |")
    print("|---|---|---|---|---|---|---|")
    for r in rows:
        print("| %s | %s | %s | %s | %s | %s | %.4f |" % (
            r["id"], fmt_maj(r["old"]), fmt_maj(r["new"]), fmt_maj(r["then"]),
            r["verdict"], model, r["cost"]))


def footer(runner, stream=None):
    stream = stream or sys.stdout
    stream.write("model: %s; calls: %d; cost: USD %.4f\n" %
                 (runner.resolved or "unknown", runner.calls, runner.spent))


def main(argv):
    ap = argparse.ArgumentParser(prog="orchestrator_diff.py")
    sub = ap.add_subparsers(dest="cmd")
    c = sub.add_parser("check-scenarios")
    c.add_argument("--scenarios", required=True)
    c.add_argument("--orchestrator")
    s = sub.add_parser("stamp-check")
    s.add_argument("--repo", required=True)
    r = sub.add_parser("run")
    r.add_argument("--repo", required=True)
    r.add_argument("--base", default="origin/main")
    r.add_argument("--runs", type=int, default=3)
    r.add_argument("--model", default="sonnet")
    r.add_argument("--max-budget-usd", type=float, default=5.0)
    r.add_argument("--calibrate", action="store_true")
    r.add_argument("--baseline", action="store_true")
    r.add_argument("--mutant-rule", default="OR43")
    args = ap.parse_args(argv)
    if args.cmd == "check-scenarios":
        return cmd_check_scenarios(args)
    if args.cmd == "stamp-check":
        return cmd_stamp_check(args)
    if args.cmd == "run":
        if args.runs < 1:
            sys.stderr.write("run: --runs must be a positive integer\n")
            return 2
        return cmd_run(args)
    ap.print_usage(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

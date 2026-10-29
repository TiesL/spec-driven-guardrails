#!/usr/bin/env python3
"""test/fixtures/orchestrator-core.py — shared structure harness for the
two-part ORCHESTRATOR.md core and its rule inventory (#499, A41; S311 and
the scenarios amended by AC14). A test fixture, not a session instruction.

Subcommands:
  check --orch F --tsv F --scen F [--pins F] --repo D --list-checks "a b ..."
        every A41 structure assertion; prints "ERROR <name>: <detail>" per
        failure, exit 1 when any; --pins adds the core-tier pin check
        (pin-mismatch, pin-missing, pin-extra; A41 amendment)
  item  --orch F ID     the item (its line plus indented continuation lines)
  line  --orch F ID     the item's first physical line only
  where --orch F ID     "<part> <depth>" (depth 0 = item, 1 = sub-item)
  row   --tsv F ID      "<tier>\t<part>\t<covered_by>"
  items --orch F        "<ID>\t<part>\t<depth>" per item, in file order
"""
import hashlib
import os
import re
import sys

MARKER = "<!-- session-context: slot -->"
PART_NAMES = {1: "fundamentals", 2: "procedure"}
ITEM_RE = re.compile(r"^( *)- (OR\d+) ")
HEADER_RE = "# Multi-agent pipeline run rules, part {n} of 2: {name}"
SENTENCE = ("Part {m} of 2 ({mname}) also applies; parts arrive in any order. "
            "Part {m} not in context: tell human before any dispatch or merge. "
            "`OR<n>` = stable rule ID; cross-part reference by ID only; never renumber.")
TIERS = ("judgment", "core", "retired")
# AC7: the rule names the inventory must hold (kebab-case labels).
REQUIRED_NAMES = [
    "role-session-guard", "work-item-definition", "first-request-behaviour",
    "stage-label-model-record-table", "continuation", "dispatch-shape-no-fork",
    "dispatch-shape-role-prefix", "fresh-reviewer-no-sendmessage",
    "review-round-brief-artifacts", "review-round-brief-reviewer-fields",
    "loop-back-routes", "any-stage-design-finding", "two-round-trigger",
    "override", "pipeline-log", "merge-self-check",
    "merge-self-check-design-step", "merge-self-check-two-round",
    "merge-self-check-no-orchestrator-marker", "merge-self-check-risk-note",
    "model-per-stage", "marker-line", "no-self-granted-shortcuts",
    "pipeline-override-record", "cannot-dispatch", "resume",
    "decided-without-asking-table", "decided-row-scratch-run",
    "decided-row-model", "decided-row-low-finding", "decided-row-naming",
    "decided-row-notice-location", "never-decided-list", "record-template",
    "recommendation-not-accepted",
]
# Files a session loads; none may point at the inventory.
SESSION_FILES = ["WORKFLOW.md", "skills/role-contracts/ORCHESTRATOR.md"]


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def parts(text):
    """[(part_no, [lines])] split at the marker line (dropped)."""
    out, cur = [], []
    for line in text.split("\n"):
        if line == MARKER:
            out.append(cur)
            cur = []
        else:
            cur.append(line)
    out.append(cur)
    return [(i + 1, p) for i, p in enumerate(out)]


def items(text):
    """[(id, part, depth, first_line, full_item_text)] in file order."""
    res = []
    for no, lines in parts(text):
        i = 0
        while i < len(lines):
            m = ITEM_RE.match(lines[i])
            if not m:
                i += 1
                continue
            depth = len(m.group(1)) // 2
            j = i + 1
            while (j < len(lines) and lines[j].strip() and lines[j].startswith(" ")
                   and not ITEM_RE.match(lines[j])):
                j += 1
            res.append((m.group(2), no, depth, lines[i], "\n".join(lines[i:j])))
            i = j
    return res


def read_tsv(path):
    rows, errors = [], []
    for n, line in enumerate(read(path).split("\n"), 1):
        if not line.strip():
            continue
        cols = line.split("\t")
        if n == 1:
            if cols != ["id", "name", "tier", "part", "covered_by"]:
                errors.append(("tsv-header", "first line must be id/name/tier/part/covered_by"))
            continue
        if len(cols) != 5:
            errors.append(("tsv-columns", "line %d has %d columns" % (n, len(cols))))
            continue
        rows.append(dict(zip(["id", "name", "tier", "part", "covered_by"], cols)))
    return rows, errors


def scenario_index(path):
    """{OB id: [OR ids]} from the headings."""
    idx = {}
    for line in read(path).split("\n"):
        m = re.match(r"^### (OB\d+) · (.+)$", line)
        if m:
            idx[m.group(1)] = [x.strip() for x in m.group(2).split(",")]
    return idx


def item_hash(full):
    """SHA-256 of the item text: from `OR<n> ` to the end, continuation lines
    joined by single spaces, trailing whitespace trimmed, no bullet."""
    ls = full.split("\n")
    first = ls[0][ls[0].index("OR"):]
    text = " ".join([first.rstrip()] + [l.strip() for l in ls[1:]]).rstrip()
    return hashlib.sha256(text.encode()).hexdigest()


def check_pins(its, rows, pins_path):
    errs, pins = [], {}
    for n, line in enumerate(read(pins_path).split("\n"), 1):
        if not line.strip():
            continue
        cols = line.split("\t")
        if n == 1:
            if cols != ["id", "sha256"]:
                errs.append(("pin-header", "first line must be id<TAB>sha256"))
            continue
        if len(cols) != 2:
            errs.append(("pin-columns", "line %d has %d columns" % (n, len(cols))))
            continue
        pins[cols[0]] = cols[1]
    core = [r["id"] for r in rows if r["tier"] == "core"]
    full = {}
    for rid, _, _, _, f in its:
        full.setdefault(rid, f)
    for rid in core:
        if rid not in pins:
            errs.append(("pin-missing", "%s is tier core but has no pin row" % rid))
        elif rid in full and item_hash(full[rid]) != pins[rid]:
            errs.append(("pin-mismatch", "%s differs from its pin; current text: %s"
                         % (rid, " ".join(l.strip() for l in full[rid].split("\n")))))
    for rid in pins:
        if rid not in core:
            errs.append(("pin-extra", "%s has a pin row but is not tier core" % rid))
    return errs


def check(orch, tsv, scen, repo, list_checks, pins=None):
    errs = []
    text = read(orch)
    markers = [l for l in text.split("\n") if l == MARKER]
    if len(markers) != 1:
        errs.append(("marker-count", "%d marker lines, expected exactly 1" % len(markers)))
    ps = parts(text)
    for no, lines in ps:
        if no not in PART_NAMES:
            continue
        m = 3 - no
        want = [HEADER_RE.format(n=no, name=PART_NAMES[no]), "",
                SENTENCE.format(m=m, mname=PART_NAMES[m])]
        if lines[:3] != want:
            errs.append(("part-header", "part %d does not open with its heading, a blank line and the fixed sentence" % no))
        for l in lines:
            if re.search(r"\b(above|below)\b", l, re.I):
                errs.append(("above-below", "part %d says above/below: %s" % (no, l.strip()[:60])))
    its = items(text)
    rows, terrs = read_tsv(tsv)
    errs += terrs
    by_id = {}
    for r in rows:
        if r["id"] in by_id:
            errs.append(("row-duplicate", "%s has two rows" % r["id"]))
        by_id[r["id"]] = r
        if not re.match(r"^OR\d+$", r["id"]):
            errs.append(("row-id", "bad id %r" % r["id"]))
        if not re.match(r"^[a-z0-9]+(-[a-z0-9]+)*$", r["name"]):
            errs.append(("row-name", "%s name %r is not a kebab-case label (no rule text)" % (r["id"], r["name"])))
        tier = r["tier"]
        if not (tier in TIERS or re.match(r"^hook:[a-z-]+(,[a-z-]+)*$", tier)
                or re.match(r"^gate:\S+$", tier)):
            errs.append(("row-tier", "%s tier %r" % (r["id"], tier)))
        if tier == "retired":
            if r["part"] != "-":
                errs.append(("retired-part", "%s retired but part %s" % (r["id"], r["part"])))
        elif r["part"] not in ("1", "2"):
            errs.append(("row-part", "%s part %r" % (r["id"], r["part"])))
        if tier.startswith("gate:") and not os.path.isfile(os.path.join(repo, tier[5:])):
            errs.append(("gate-missing", "%s gate script %s does not exist" % (r["id"], tier[5:])))
    seen = {}
    for rid, no, depth, first, full in its:
        seen.setdefault(rid, []).append(no)
        if rid not in by_id:
            errs.append(("item-no-row", "%s is in the core but has no inventory row" % rid))
    for rid, nos in seen.items():
        if len(nos) != 1:
            errs.append(("id-not-once", "%s starts %d items (parts %s)" % (rid, len(nos), nos)))
    for r in rows:
        rid = r["id"]
        if r["tier"] == "retired":
            if rid in seen or re.search(r"\b%s\b" % rid, text):
                errs.append(("retired-present", "%s is retired but occurs in the core" % rid))
            continue
        if rid not in seen:
            errs.append(("id-missing", "%s has a row but no item in the core" % rid))
        elif str(seen[rid][0]) != r["part"]:
            errs.append(("wrong-part", "%s sits in part %s, its row says %s" % (rid, seen[rid][0], r["part"])))
    for ref in set(re.findall(r"\bOR\d+\b", text)):
        if ref not in by_id:
            errs.append(("ref-unknown", "%s is cited in the core but has no row" % ref))
    full = {rid: f for rid, _, _, _, f in its}

    def need(rid, needle, name):
        if needle not in full.get(rid, ""):
            errs.append((name, "%s must contain %r" % (rid, needle)))
    need("OR21", "OR45", "xref-or21")
    need("OR37", "OR45", "xref-or37")
    need("OR31", "OR5", "xref-or31")
    need("OR31", "--role", "xref-or31")
    if not re.search(r"agree|match", full.get("OR31", ""), re.I):
        errs.append(("xref-or31", "OR31 must state emit role/stage agreement with the prefix role"))
    need("OR36", "in OR5 order", "xref-or36")
    or11 = full.get("OR11", "")
    # #516 (A43): approval for that PR, after the work or in advance; any
    # change lapses it; the human names no head SHA (old wording gone).
    if not re.search(r"Merge into `main` only with human's approval for that PR, given after work or in advance", or11) \
            or "new commit that changes the work lapses the approval" not in or11 \
            or "final head SHA" in or11:
        errs.append(("or11-wording", "OR11 must say merge into main only with the human's approval for that PR, given after the work or in advance, and that a new commit that changes the work lapses the approval"))
    names = {r["name"] for r in rows}
    for n in REQUIRED_NAMES:
        if n not in names:
            errs.append(("name-missing", "required rule name %s has no row" % n))
    hook_checks = []
    for r in rows:
        if r["tier"].startswith("hook:"):
            hook_checks += r["tier"][5:].split(",")
    if sorted(hook_checks) != sorted(list_checks):
        errs.append(("hook-checks", "inventory hook checks %s differ from --list-checks %s"
                     % (sorted(hook_checks), sorted(list_checks))))
    obs = scenario_index(scen)
    for ob, ors in obs.items():
        for o in ors:
            if o not in by_id or by_id[o]["tier"] == "retired":
                errs.append(("ob-unknown-id", "%s cites %s, which is not a live rule" % (ob, o)))
    for r in rows:
        cov = [c for c in r["covered_by"].split(",") if c]
        for c in cov:
            if not re.match(r"^(S\d+|OB\d+)$", c):
                errs.append(("covered-format", "%s covered_by %r" % (r["id"], c)))
            elif c.startswith("OB") and c not in obs:
                errs.append(("covered-unknown-ob", "%s names %s, which does not exist" % (r["id"], c)))
            elif c.startswith("OB") and r["id"] not in obs[c]:
                errs.append(("covered-ob-mismatch", "%s names %s, whose heading does not cite it" % (r["id"], c)))
            elif c.startswith("S") and not any(
                    re.match(r"^s%s_" % c[1:], f) for f in os.listdir(os.path.join(repo, "test/cases"))):
                errs.append(("covered-unknown-s", "%s names %s, which has no test" % (r["id"], c)))
        if r["tier"] == "judgment" and not any(c.startswith("OB") and c in obs for c in cov):
            errs.append(("judgment-no-ob", "%s is judgment but covered_by names no existing OB" % r["id"]))
    for rel in SESSION_FILES + sorted(
            os.path.relpath(os.path.join(d, f), repo)
            for d, _, fs in os.walk(os.path.join(repo, "skills")) for f in fs if f == "SKILL.md"):
        p = os.path.join(repo, rel)
        if os.path.isfile(p) and "orchestrator-rules.tsv" in read(p):
            errs.append(("inventory-pointer", "%s tells a session about the inventory" % rel))
    if pins:
        errs += check_pins(its, rows, pins)
    return errs


def arg(argv, flag):
    return argv[argv.index(flag) + 1]


def main(argv):
    cmd = argv[0] if argv else ""
    if cmd == "check":
        errs = check(arg(argv, "--orch"), arg(argv, "--tsv"), arg(argv, "--scen"),
                     arg(argv, "--repo"), arg(argv, "--list-checks").split(),
                     arg(argv, "--pins") if "--pins" in argv else None)
        for name, detail in errs:
            print("ERROR %s: %s" % (name, detail))
        return 1 if errs else 0
    if cmd in ("item", "line", "where"):
        rid = argv[-1]
        for i, no, depth, first, full in items(read(arg(argv, "--orch"))):
            if i == rid:
                print({"item": full, "line": first, "where": "%d %d" % (no, depth)}[cmd])
                return 0
        return 1
    if cmd == "items":
        for i, no, depth, _, _ in items(read(arg(argv, "--orch"))):
            print("%s\t%d\t%d" % (i, no, depth))
        return 0
    if cmd == "row":
        rows, _ = read_tsv(arg(argv, "--tsv"))
        for r in rows:
            if r["id"] == argv[-1]:
                print("%s\t%s\t%s" % (r["tier"], r["part"], r["covered_by"]))
                return 0
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

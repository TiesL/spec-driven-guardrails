#!/usr/bin/env python3
"""Document contract checks for issue #415's existing injected seam."""

import os
import re
import subprocess
import sys
from pathlib import Path


root = Path(sys.argv[1])
scenario = sys.argv[2]
orch = os.environ.get("DT415_ORCH", (root / "skills/role-contracts/ORCHESTRATOR.md").read_text())
roles = os.environ.get("DT415_ROLES", (root / "skills/role-contracts/SKILL.md").read_text())


def require(condition, explanation):
    if not condition:
        raise AssertionError(f"{scenario}: {explanation}")


def section(text, heading):
    match = re.search(rf"(?m)^## {re.escape(heading)}\s*$", text)
    require(match, f"missing section {heading}")
    end = re.search(r"(?m)^## ", text[match.end():])
    return text[match.end():match.end() + end.start()] if end else text[match.end():]


def clause(cell, anchor):
    """The one sentence of a cell (split on '.' not followed by 'md', and on ';') holding anchor."""
    parts = [p.strip() for p in re.split(r"\.(?!md\b)|;", cell)]
    hits = [p for p in parts if anchor in p]
    require(len(hits) == 1, f"exactly one clause holds {anchor!r} (found {len(hits)})")
    return hits[0]


def norm(text):
    return re.sub(r"\s+", " ", text)


if scenario == "s277":
    table = section(orch, "Decided without asking")
    rows = [r for r in table.splitlines() if r.startswith("|")]
    parsed = [[cell.strip() for cell in row.strip("|").split("|")] for row in rows]
    require(any(len(r) == 3 and r[0] == "Decision" and r[1] == "Rule" and r[2] == "Logged" for r in parsed), "three-column decision table")
    expected = {
        "scratch": (r"scratch (run|directory|repo)", r"available", r"scratch (directory|repo)", r"real repo|shared clone"),
        "model": (r"model.*role", r"cheapest", r"floor", r"model-choice"),
        "low finding": (r"low.severity finding",),
        "naming": (r"naming and numbering", r"existing convention", r"next free", r"answered"),
    }
    for name, patterns in expected.items():
        matches = [r for r in parsed if len(r) == 3 and re.search(patterns[0], r[0], re.I)]
        require(len(matches) == 1, f"one {name} row")
        row = matches[0]
        require(row[1] and row[2], f"{name} rule and log destination")
        for pattern in patterns[1:]:
            require(re.search(pattern, row[1], re.I), f"{name} rule missing {pattern}")
        require("log" in row[2].lower() or "record" in row[2].lower(), f"{name} log destination")
    low = next(r for r in parsed if len(r) == 3 and re.search(r"low.severity finding", r[0], re.I))
    rule = low[1]
    require("`Disposition`" in rule and re.search(r"scope-expansion", rule, re.I), "low finding: Disposition and scope-expansion kept")
    require(not re.search(r"pending|\bQ1\b|do not infer|if the maintainer", rule, re.I), "low finding: pending or conditional wording")
    require(not re.search(r"pending|\bQ[12]\b", low[2], re.I), "low finding: pending log wording")
elif scenario == "s288":
    # #488 AC1, AC11 (S288): the exact oracle of the low-severity row. Located by
    # its first cell; every phrase is matched inside that one row's cells.
    rows = [r for r in orch.splitlines() if r.startswith("|")]
    low_rows = [r for r in rows if re.search(r"low.severity finding", r.strip("|").split("|")[0], re.I)]
    require(len(low_rows) == 1, "exactly one physical low-severity row line")
    cells = [c.strip() for c in low_rows[0].strip("|").split("|")]
    require(len(cells) == 3, "low-severity row has decision, rule and log cells")
    rule, log = cells[1], cells[2]
    require(len(orch.splitlines()) <= 79, "file at most 79 lines (pre-change count; S180 cap is 80)")
    require("`Fix cost`" in rule and "SKILL.md" in rule, "rule names the `Fix cost` field and SKILL.md")
    sentences = [s for s in re.split(r"\.(?!md\b)", rule)]
    # Clause-local checks (#460/#464 lesson): every token is asserted inside its own clause.
    core = clause(rule, "tagged `trivial`")
    require("fixed in the PR" in core and "passes" in core, "R3 clause: trivial low that passes is fixed in the PR")
    other = clause(rule, "any other low finding")
    require("deferred" in other and "absent or doubtful" in other, "other-low clause: deferred, tag absent or doubtful")
    bundle = clause(rule, "filed after the last round")
    require("bundled" in bundle and "no `Disposition` of its own" in bundle, "bundle clause: only lows with no Disposition of their own")
    require("`issue`" not in bundle, "bundle clause: no Disposition `issue` value")
    route = clause(rule, "QA names")
    require("red check" in route and "Developer" in route, "route clause: QA red check, Developer commits")
    require("only a `code` or `test` low can be trivial" in route, "route clause: code and test are the only eligible classes")
    require("a `design` or `spec` low is deferred" in route, "route clause: design and spec lows are deferred")
    red = clause(rule, "CI is red")
    for needle in ("T1 or T2 fails after it exists", "revert", "defer that finding", "fresh review", "no second trivial"):
        require(needle in red, f"red-CI clause: {needle}")
    disp = clause(rule, "recorded `Disposition`")
    require("own issue" in disp and "immediately" in disp, "Disposition clause: issue-bound low is its own issue, immediately")
    require(any(re.search(r"\bone\b[^.;]*trivial-fix commit[^.;]*per PR", s) for s in sentences), "cap: one trivial-fix commit per PR")
    require(any(re.search(r"new low[^.]*delta[^.]*\bdeferred\b", s) for s in sentences), "cap: a new low found in the delta round is deferred")
    require(re.search(r"\bslug", rule), "delta re-review keeps earlier slugs")
    require("Pipeline log" in log, "log cell names the Pipeline log")
    require(re.search(r"\bfix", log + " " + rule, re.I) and re.search(r"\bdefer", log + " " + rule, re.I), "log requires fix-in-PR or deferred per finding")
    require(not re.search(r"never in a low-only round|File a low-severity finding as an issue by default|already required by a medium or high finding", rule, re.I), "old low-finding text is gone")
    require("`Disposition`" in rule and "scope-expansion" in rule, "Disposition and scope-expansion kept")
    require(not re.search(r"10 changed lines|2 files|1 hunk", rule), "row does not restate the T1-T6 limits")
elif scenario == "s289":
    # #488 AC2, AC2b (S289): the single Fix cost definition in SKILL.md.
    require(roles.count("**Fix cost**") == 1, "exactly one **Fix cost** field")
    start = roles.index("**Fix cost**")
    nxt = re.search(r"\n- \*\*", roles[start:])
    field = roles[start:start + nxt.start()] if nxt else roles[start:]
    for value in ("`trivial`", "`small`", "`large`"):
        require(value in field, f"Fix cost value {value}")
    require("`trivial`, `small` or `large`" in field, "Fix cost lists its three values together")
    for tag in ("T1", "T2", "T3", "T4", "T5", "T6"):
        require(re.search(rf"(?m)^\s*- {tag} ", field), f"Fix cost item {tag} as a labelled list item")
    first = re.search(r"(?m)^\s*- T1 ", field)
    lead = norm(field[:first.start()])
    parts = re.split(r"(?m)^\s*- (T[1-6]) ", field[first.start():])
    item = {parts[i]: norm(parts[i + 1]) for i in range(1, len(parts), 2)}
    require(sorted(item) == ["T1", "T2", "T3", "T4", "T5", "T6"], "six distinct items")
    lead_sentences = re.split(r"(?<=\.) ", lead)

    def lead_sentence(anchor):
        hits = [s for s in lead_sentences if anchor in s]
        require(len(hits) == 1, f"exactly one lead sentence holds {anchor!r}")
        return hits[0]

    elig = lead_sentence("Only a `code` or `test` low can be trivial")
    require("`design`" in elig and "`spec`" in elig and "deferred" in elig, "eligibility: design and spec lows are deferred")
    qa = lead_sentence("QA runs once per round")
    require("red check" in qa, "QA sentence: names the red check")
    require("QA adds no test" in lead, "QA sentence: adds no test, scenario or assertion")
    void = lead_sentence("no red check")
    require("void" in void and "deferred" in void, "QA sentence: void tag and deferred if no red check")
    single = lead_sentence("exactly one parent")
    require("git rev-list --parents -n 1" in single, "single parent: rev-list command")
    nonmeasurable = lead_sentence("folded into a blocking-fix commit")
    require("merge commit" in nonmeasurable and "not trivial" in nonmeasurable, "merge or folded fix is not trivial")
    require("<reviewed-sha>.." not in field and "<fix-sha>" not in field, "no <reviewed-sha>..<fix-sha> range remains")
    t1, t2, t3, t4, t5, t6 = (item[k] for k in ("T1", "T2", "T3", "T4", "T5", "T6"))
    for needle in ("git diff --name-only F^ F", "<base>...<reviewed-sha>", "any *.md file anywhere", "templates/*.sh", "`ci.yml`"):
        require(needle in t1, f"T1 item: {needle}")
    docs_part, code_part = t1.split("anything else is code or test", 1) if "anything else is code or test" in t1 else (t1, "")
    require("templates/*.sh" not in docs_part and "`ci.yml`" in code_part and "templates/*.sh" in code_part, "T1 item: templates scripts and ci.yml are code, not docs")
    for needle in ("git diff --numstat F^ F", "git diff -U0 F^ F", "grep -c '^@@'"):
        require(needle in t2, f"T2 item: {needle}")
    for digits, unit, where in (("2", "files", t1), ("10", "changed lines", t2), ("1", "hunk", t2)):
        require(re.search(rf"(?<![\w.]){digits} {unit}\b", where), f"numeric limit {digits} {unit}")
    require("Docs and comments" in t3 and "any wording" in t3, "T3 item keeps the docs allowance")
    require("Code and test" in t4 and "typo" in t4, "T4 item keeps the code and test allowance")
    for needle in ("new behavior", "assertion", "spec", "new file", "guard", "gate"):
        require(re.search(rf"\b{re.escape(needle)}\b", t5), f"T5 item: {needle}")
    for needle in ("`CONFIRMED`", "no test edited"):
        require(needle in (t4 if needle == "`CONFIRMED`" else t6), f"item text {needle}")
    for needle in ("T1 or T2 fails", "revert", "defer", "fresh review", "no second trivial"):
        require(needle in t6, f"T6 item: {needle}")
    require("@@" in t2, "T2 item counts hunks")
    require(any(re.search(r"\babsent\b|\bdoubtful\b", s) and "not trivial" in s for s in re.split(r"(?<=\.) ", norm(field))), "absent-or-doubtful rule")
elif scenario == "s278":
    decision = section(orch, "Decided without asking")
    require("**Never decided by the orchestrator:**" in decision, "never-list heading")
    never = decision.split("**Never decided by the orchestrator:**", 1)[1].split("**Record template", 1)[0]
    for label, pattern in {
        "main merge": r"merge.*main", "version bump": r"version bump",
        "spec content": r"PRD\.md.*ARCHITECTURE\.md.*TEST-SCENARIOS\.md",
        "outward-facing": r"outward-facing", "role recommendation": r"departure.*recommendation",
    }.items():
        require(re.search(pattern, never, re.I | re.S), label)
elif scenario == "s279":
    decision = section(orch, "Decided without asking")
    rule = decision.strip().split("\n\n", 1)[0]
    require(re.search(r"row.*only.*choice.*contracts.*leave open", rule, re.I | re.S), "bounded row")
    require(re.search(r"never waive.*contract rule", rule, re.I), "no contract waiver")
    require("fresh Reviewer" in rule and "design" in rule and "maintainer" in rule, "fresh review and design route examples")
    rows = [line for line in decision.splitlines() if line.startswith("|")]
    for row in rows[2:]:
        cells = [cell.strip() for cell in row.strip("|").split("|")]
        require(len(cells) == 3, "malformed decision row")
        choice = f"{cells[0]} {cells[1]}".lower()
        require(not re.search(r"\b(continue|reuse|resume)\b.{0,60}\b(previous|prior|same)\b.{0,30}\breviewer\b", choice), "row waives fresh Reviewer")
        require(not re.search(r"\b(fix|patch)\b.{0,60}\bdesign(?:-class)? finding\b.{0,60}\b(directly|in code)\b", choice), "row waives design route")
elif scenario == "s280":
    decision = section(orch, "Decided without asking")
    template = re.search(r"`<YYYY-MM-DD>[^`]+`", decision)
    require(template, "dated prose record template")
    require("Pipeline log" in decision and "Decisions by rule" in decision, "issue log destination")
    for token in ("YYYY-MM-DD", "row", "decision"):
        require(token in template.group(), f"record template {token}")
    require("model-record" not in template.group(), "template carries stage marker")
    require("until the change reaches `main`" in decision, "objection deadline: until the change reaches main")
    require(re.search(r"including after a work-item merge into a release branch", decision), "objection deadline covers release-branch work-item merge")
    require(not re.search(r"until the (release-branch )?merge\b", decision, re.I), "ambiguous merge deadline")
    require(not re.search(r"pending|\bQ2\b|Once Q", decision, re.I), "pending Q2 wording")
    require(re.search(r"object", decision, re.I), "objection rule stated")
elif scenario == "s281":
    shared = section(roles, "Shared, across all five roles")
    require("When your recommendation is not accepted" in shared, "pushback contract")
    shared = shared.split("**When your recommendation is not accepted", 1)[1].split("\n\n", 1)[0]
    for pattern in (r"once", r"before the decision is recorded", r"arguments", r"cost", r"numbered human decision links the pushback", r"fresh Reviewer"):
        require(re.search(pattern, shared, re.I), f"pushback rule {pattern}")
    require("pushback" in orch and "before" in orch, "orchestrator flow")
elif scenario == "s282":
    architect = section(roles, "Architect")
    for pattern in (r"Risk note", r"Decision", r"What is accepted", r"Likely consequence", r"Early signal", r"Revisit when", r"#410", r"Planning"):
        require(re.search(pattern, architect, re.I), f"Architect risk note {pattern}")
    require("risk note" in orch.lower() and "Architect" in orch, "Architect dispatch")
elif scenario == "s283":
    require(len(orch.splitlines()) <= 80, "S180 line cap")
    # Structure oracles (round 1, F44 / A29 "File structure").
    headings = re.findall(r"(?m)^## .*$", orch)
    require(headings and headings[-1] == "## Decided without asking", "decision section is not the last ## heading")
    head = re.search(r"(?m)^## Decided without asking\s*$", orch)
    require(head, "missing section Decided without asking")
    run_paragraphs = re.split(r"\n\s*\n", orch[:head.start()])
    for label, start in {
        "merge self-check": "**Before asking for a merge,**", "model per stage": "**Model per stage.**",
        "marker line": "**Marker line: never typed.**", "no self-granted shortcuts": "**No self-granted shortcuts.**",
        "cannot dispatch": "**Cannot dispatch**", "resume": "**Resume:**",
    }.items():
        require(any(p.startswith(start) for p in run_paragraphs), f"run rule not a paragraph before the decision section: {label}")
    override = [p for p in run_paragraphs if p.startswith("**Override.**")]
    require(len(override) == 1, "one Override paragraph before the decision section")
    require(not re.search(r"(?<![\w/])#\d+", override[0]), "Override paragraph carries a bare #<n> pointer")
    require("When a recommendation is not accepted" in override[0] and "SKILL.md" in override[0], "Override paragraph does not name the not-accepted paragraph and SKILL.md")
    lines = orch.splitlines()
    idx = [i for i, l in enumerate(lines) if l.startswith("**When a recommendation is not accepted:**")]
    require(len(idx) == 1, "one 'When a recommendation is not accepted' paragraph")
    i = idx[0]
    require(i > 0 and lines[i - 1].strip() == "", "no blank line before the not-accepted paragraph")
    require(i + 1 >= len(lines) or lines[i + 1].strip() == "", "no blank line after the not-accepted paragraph")
    require(not any(l.startswith("**Before asking for a merge,**") for l in lines[max(0, i - 1):i + 2]), "not-accepted paragraph adjacent to the merge self-check paragraph")
else:
    raise AssertionError(f"unknown scenario {scenario}")

# The same document checks must reject one controlled break in each rule or
# record. These are private test inputs; the injected document seam is unchanged.
if not os.environ.get("DT415_NEGATIVE"):
    mutations = {
        "s277": [
            ("Use an available tool", "Use any tool", "scratch rule"),
            ("Choose the cheapest model", "Choose the preferred model", "model rule"),
            ("`Disposition` and scope-expansion rules", "rules", "Disposition and scope-expansion dropped"),
            ("By `Fix cost`", "Pending maintainer Q1; by `Fix cost`", "pending wording returns"),
            ("next free number", "any number", "numbering rule"),
            ("| Tool for a scratch run |", "| Other choice |", "scratch row"),
            ("| Pipeline log |\n| Model", "| |\n| Model", "scratch log cell"),
        ],
        "s288": [
            ("By `Fix cost` (defined in `skills/role-contracts/SKILL.md`)", "File a low-severity finding as an issue by default; a narrow text-only fix may go in the PR only during a round already required by a medium or high finding, never in a low-only round", "row reverted to old text"),
            ("Cap: one trivial-fix commit per PR, separate from any blocking-fix commit; ", "", "cap sentence removed"),
            ("By `Fix cost` (defined in `skills/role-contracts/SKILL.md`)", "By cost (defined elsewhere)", "Fix cost pointer removed"),
            ("; the delta re-review is a fresh Reviewer round that carries every earlier slug", "", "slug carry-forward removed"),
            ("a new low found in the delta round is deferred, never fixed in the PR", "a new low found in the delta round is fixed", "delta-round low deferral removed"),
            ("revert it, defer that finding, run a fresh review of the new HEAD, and make no second trivial fix", "carry on", "red-CI sentence removed"),
            ("Pipeline log: per finding", "Issue log: per finding", "Pipeline log dropped"),
            ("| Pipeline log: per finding", "|\n| Pipeline log: per finding", "row split over two lines"),
            ("## Decided without asking", "\n" * 81 + "## Decided without asking", "file padded to 81 lines"),
            ("`Disposition` and scope-expansion rules", "rules", "Disposition and scope-expansion dropped"),
            ("By `Fix cost`", "By `Fix cost` (at most 10 changed lines)", "limit restated in the row"),
            ("a low finding tagged `trivial` that passes that definition is fixed in the PR", "every low finding is bundled", "R3 clause removed while trivial-fix and defer that finding remain"),
            ("any other low finding, and one whose tag is absent or doubtful, is deferred, ", "", "any-other-low-is-deferred removed while another defer remains"),
            ("only a `code` or `test` low can be trivial (a `design` or `spec` low is deferred), and ", "", "class restriction dropped"),
            ("QA names a red check for it on the reviewed sha before the ", "the ", "QA red check sentence removed"),
            (", or T1 or T2 fails after it exists, revert it", ", revert it", "T1/T2-after-commit sentence removed"),
            ("is filed as its own issue immediately, never bundled", "is filed later, never bundled", "own issue removed from the Disposition clause"),
            ("if it has no `Disposition` of its own", "including a low with `Disposition` `issue`", "bundled clause includes Disposition issue lows"),
            ([", or T1 or T2 fails after it exists, revert it"], ["; T1 or T2 fails after it exists; revert it"], "decoy: red-CI tokens moved into the wrong clause"),
        ],
        "s289": [
            ("at most 10 changed lines", "at most 20 changed lines", "limit digit changed"),
            ("2 files,", "files,", "2 files limit removed"),
            ("1 hunk in", "hunk in", "1 hunk limit removed"),
            ("- T3 Docs", "- X3 Docs", "T3 removed"),
            ("- T6 Evidence", "- X6 Evidence", "T6 removed"),
            ("new behavior, ", "", "T5 disqualifier list reduced"),
            ("`trivial`, `small` or `large`", "`trivial` or `large`", "three values reduced to two"),
            ("git diff --numstat", "git diff --stat", "numstat command changed"),
            ("**Fix cost**", "**Fix cost**: first.\n- **Fix cost**", "field duplicated"),
            ("any change to an existing assertion, expected value or oracle, any change to spec content\n    (PRD, ARCHITECTURE, TEST-SCENARIOS), ", "", "T5 assertion and spec disqualifiers deleted while T4 keeps the words"),
            ("git diff --numstat F^ F", "git diff --numstat <reviewed-sha>..<fix-sha>", "T2 range replaces F^ F"),
            ("exactly one parent (`git rev-list --parents -n 1 F` prints two fields)", "one parent", "single-parent sentence removed"),
            ("any *.md file anywhere", "any `*.md` file", "anywhere dropped from T1"),
            ("(including under templates/)", "(including templates/*.sh)", "templates scripts moved into the docs list"),
            ("Only a `code` or `test` low can be trivial", "Any low can be trivial", "eligibility widened"),
            ("names the red\n  check on the reviewed sha", "names a\n  failing run on the reviewed sha", "QA red check sentence removed"),
            (["If CI is red, or T1 or T2 fails then,\n    revert F, defer the finding, run a fresh review of the new HEAD, and make no second trivial fix:\n    the attempt is spent."], ["Nothing more."], "T6 failure path removed"),
            ("and make no second trivial fix:\n    the attempt is spent.", "and carry on.", "no second trivial fix removed from T6"),
            (["`CONFIRMED`, not `PLAUSIBLE`.", "If CI is red, or T1 or T2 fails then,\n    revert F, defer the finding, run a fresh review of the new HEAD, and make no second trivial fix:\n    the attempt is spent."], ["`CONFIRMED`, not `PLAUSIBLE`. If CI is red, or T1 or T2 fails then, revert F, defer the finding, run a fresh review of the new HEAD, and make no second trivial fix.", "Nothing more."], "decoy: AC12 failure path moved from T6 into T4"),
        ],
        "s278": [
            ("**Never decided by the orchestrator:**", "**Examples:**", "never-list heading"),
            ("merges into `main`", "merges into a branch", "main merge exclusion"),
            ("the version bump or a `CHANGES.md` meaning-version bump", "a changelog edit", "version exclusion"),
            ("content of `PRD.md`, `ARCHITECTURE.md`, or `TEST-SCENARIOS.md`", "content of a spec", "spec exclusion"),
            ("anything outward-facing", "things beyond this repo", "outward-facing exclusion"),
            ("any departure from a role's recommendation", "a change of mind", "recommendation exclusion"),
        ],
        "s279": [
            ("can never waive a contract rule", "can waive a contract rule", "no-waiver rule"),
            ("fresh Reviewer each round", "the previous Reviewer", "Reviewer example"),
            ("design-finding loop-back route", "usual route", "design example"),
            ("| Tool for a scratch run |", "| Review dispatch | Continue the previous Reviewer for the next round. | Pipeline log |\n| Tool for a scratch run |", "contradictory Reviewer row"),
            ("| Tool for a scratch run |", "| Design finding fix | Patch a design-class finding directly in code instead of routing to Architect. | Pipeline log |\n| Tool for a scratch run |", "contradictory design row"),
        ],
        "s280": [
            ("<decision>.` The maintainer", "<decision> <!-- model-record: stage=Review -->.` The maintainer", "marker in record"),
            ("until the change reaches `main`", "until the merge", "ambiguous until the merge"),
            ("until the change reaches `main`", "until the release-branch merge", "release-branch merge deadline"),
            (", including after a work-item merge into a release branch", "", "release-branch coverage dropped"),
            ("The maintainer may object to a decision by rule until the change reaches `main`, including after a work-item merge into a release branch.", "Log it.", "log-only rule, no deadline"),
            ("The maintainer may object", "Maintainer objection rule pending Q2; the maintainer may object", "pending wording"),
        ],
        "s281": [
            ("Before the decision is recorded", "After the decision is recorded", "pushback order"),
            ("numbered human decision links the pushback", "numbered human decision follows", "pushback link"),
            ("Reviewer is a fresh Reviewer", "Reviewer can continue", "fresh Reviewer"),
        ],
        "s282": [("**Likely consequence**", "**Possible outcome**", "risk-note field")],
        "s283": [
            ("## Decided without asking", "\n" * 81 + "## Decided without asking", "line cap"),
            ("Do not put a `model-record` marker in an orchestrator record.", "Do not put a `model-record` marker in an orchestrator record.\n\n## Run rules", "heading after the section"),
            ("\n\n**Cannot dispatch**", "\n\n## Decided without asking\n\n**Cannot dispatch**", "rule moved below the heading"),
            ("\n\n**Cannot dispatch**", "\n\nCannot dispatch", "rule removed"),
            ("\n\n**When a recommendation is not accepted:**", "\n**When a recommendation is not accepted:**", "adjacency re-created"),
            ("the A29 flow, defined in \"When a recommendation is not accepted\" below, applies", "the A29 (#415) flow applies", "bare #n in Override"),
            ("The Architect's risk-note format is in `SKILL.md`; this file", "The Architect's risk-note format is elsewhere; this file", "SKILL.md replaced"),
            ("defined in \"When a recommendation is not accepted\" below", "defined below", "paragraph name replaced"),
        ],
    }
    for old, new, label in mutations[scenario]:
        source = roles if scenario in ("s281", "s282", "s289") else orch
        olds, news = (old, new) if isinstance(old, list) else ([old], [new])
        mutated = source
        for o, n in zip(olds, news):
            require(o in mutated, f"mutation anchor absent: {label}")
            mutated = mutated.replace(o, n, 1)
        env = os.environ.copy()
        env["DT415_NEGATIVE"] = "1"
        env["DT415_ROLES" if scenario in ("s281", "s282", "s289") else "DT415_ORCH"] = mutated
        result = subprocess.run([sys.executable, __file__, str(root), scenario], env=env, capture_output=True, text=True)
        require(result.returncode != 0 and f"{scenario}:" in result.stderr, f"controlled break escaped: {label}")

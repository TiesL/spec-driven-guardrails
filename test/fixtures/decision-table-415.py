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


# #499 (AC14, A41): the core is now two parts of `OR<n>` list items; these
# locate a rule by ID instead of a table row or bold label.
MARKER = "<!-- session-context: slot -->"
tsv = os.environ.get("DT415_TSV", (root / "skills/role-contracts/orchestrator-rules.tsv").read_text())


def items(text):
    """{id: [(part, depth, item text)]}: first line plus indented continuation lines."""
    out, part, lines = {}, 1, text.split("\n")
    i = 0
    while i < len(lines):
        if lines[i] == MARKER:
            part += 1
        m = re.match(r"^( *)- (OR\d+) ", lines[i])
        if not m:
            i += 1
            continue
        j = i + 1
        while j < len(lines) and lines[j].strip() and lines[j].startswith(" ") and not re.match(r"^ *- OR\d+ ", lines[j]):
            j += 1
        out.setdefault(m.group(2), []).append((part, len(m.group(1)) // 2, "\n".join(lines[i:j])))
        i = j
    return out


def row(rid):
    for line in tsv.splitlines()[1:]:
        cols = line.split("\t")
        if cols and cols[0] == rid:
            return {"tier": cols[2], "part": cols[3]}
    require(False, f"{rid} has no inventory row")


def rule(rid, tier=None, part=None):
    """The one item of rid, checked against its tier and part; returns its text."""
    found = items(orch).get(rid, [])
    require(len(found) == 1, f"{rid} starts exactly one item (found {len(found)})")
    r = row(rid)
    if tier is not None:
        require(r["tier"] == tier, f"{rid} tier {r['tier']}, expected {tier}")
    require(str(found[0][0]) == r["part"], f"{rid} sits in part {found[0][0]}, inventory says {r['part']}")
    if part is not None:
        require(found[0][0] == part, f"{rid} sits in part {found[0][0]}, expected {part}")
    return found[0][2]


if scenario == "s277":
    # Amended by #499 (AC14, A41): the four seeded rows are items OR38-OR41
    # under `## Decided without asking` in part 2, tier judgment.
    sec = section(orch, "Decided without asking")
    for rid in ("OR38", "OR39", "OR40", "OR41"):
        text = rule(rid, "judgment", 2)
        require(text in sec, f"{rid} sits under ## Decided without asking")
    require("logged in Pipeline log" in rule("OR37"), "log destination: OR37 logs each row in the Pipeline log")
    rec = rule("OR44")
    require("Pipeline log" in rec and "Decisions by rule" in rec, "log destination: OR44's record")
    low = rule("OR40")
    require("`Disposition`" in low and re.search(r"scope-expansion", low, re.I), "low finding: Disposition and scope-expansion kept")
    for rid, entries in items(sec).items():
        for _, _, text in entries:
            require(not re.search(r"pending|\bQ[12]\b|do not infer|if the maintainer", text, re.I), f"{rid}: pending or conditional wording")
elif scenario == "s288":
    # #488 AC1; replaced by #499 AC14 (A41): the low-finding row is the item
    # OR40 in part 2; the table-cell locator and clause-local oracles are
    # retired, their behaviour moved to OB40-OB44 and the OR40 calibration
    # mutant. Kept deterministic: (a) tier, part, one physical line; (b) the
    # pointer; (h) old text gone; (i) Disposition and scope-expansion; no
    # restated T1-T6 limits.
    low = rule("OR40", "judgment", 2)
    require("\n" not in low, "(a) OR40 is one physical line")
    require("`Fix cost`" in low and "SKILL.md" in low, "(b) OR40 names the `Fix cost` field and SKILL.md")
    require(not re.search(r"never in a low-only round|File a low-severity finding as an issue by default|already required by a medium or high finding", low, re.I), "(h) old low-finding text is gone")
    require("`Disposition`" in low and "scope-expansion" in low, "(i) Disposition and scope-expansion kept")
    require(not re.search(r"10 changed lines|2 files|1 hunk", low), "OR40 does not restate the T1-T6 limits")
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
    # Amended by #499 (AC14, A41): the never-list is the item OR43 in part 1,
    # tier judgment, located by ID; the six-category phrase checks are
    # retired (behaviour OB47, OB48, OB9/OB10).
    rule("OR43", "judgment", 1)
elif scenario == "s279":
    # Amended by #499 (AC14, A41): the no-waiver rule is OR37 in part 2,
    # tier judgment, citing OR45; the bounded scan applies to OR38-OR42, OR44.
    require(re.search(r"\bOR45\b", rule("OR37", "judgment", 2)), "OR37 cites OR45")
    for rid in ("OR38", "OR39", "OR40", "OR41", "OR42", "OR44"):
        choice = rule(rid).lower()
        require(not re.search(r"\b(continue|reuse|resume)\b.{0,60}\b(previous|prior|same)\b.{0,30}\breviewer\b", choice), f"{rid} waives fresh Reviewer")
        require(not re.search(r"\b(fix|patch)\b.{0,60}\bdesign(?:-class)? finding\b.{0,60}\b(directly|in code)\b", choice), f"{rid} waives design route")
elif scenario == "s280":
    # Amended by #499 (AC14, A41): the record template is the item OR44,
    # with the tier and part its inventory row names.
    rec = rule("OR44")
    template = re.search(r"`<YYYY-MM-DD>[^`]+`", rec)
    require(template, "dated prose record template")
    require("Pipeline log" in rec and "Decisions by rule" in rec, "issue log destination")
    for token in ("YYYY-MM-DD", "row", "decision"):
        require(token in template.group(), f"record template {token}")
    require("<!-- model-record" not in rec, "record carries a stage marker")
    require("until change reaches `main`" in rec, "objection deadline: until the change reaches main")
    require(re.search(r"including after work-item merge into release branch", rec), "objection deadline covers release-branch work-item merge")
    require(not re.search(r"until the (release-branch )?merge\b", rec, re.I), "ambiguous merge deadline")
    require(not re.search(r"pending|\bQ2\b|Once Q", rec, re.I), "pending Q2 wording")
    require(re.search(r"object", rec, re.I), "objection rule stated")
elif scenario == "s281":
    shared = section(roles, "Shared, across all five roles")
    require("When your recommendation is not accepted" in shared, "pushback contract")
    shared = shared.split("**When your recommendation is not accepted", 1)[1].split("\n\n", 1)[0]
    for pattern in (r"once", r"before the decision is recorded", r"arguments", r"cost", r"numbered human decision links the pushback", r"fresh Reviewer"):
        require(re.search(pattern, shared, re.I), f"pushback rule {pattern}")
    require(re.search(r"Dispatch recommending role once for reasoned pushback before decision recorded;", norm(rule("OR45"))), "OR45: recommending role pushback before decision")
elif scenario == "s282":
    architect = section(roles, "Architect")
    for pattern in (r"Risk note", r"What is accepted", r"Likely consequence", r"Early signal", r"Revisit when", r"#410", r"Planning"):
        require(re.search(pattern, architect, re.I), f"Architect risk note {pattern}")
    require("**Decision** linking the numbered human decision" in norm(architect), "literal Decision field and decision link")
    require(re.search(r"Non-Architect role's overrule: dispatch Architect for issue risk note\.", norm(rule("OR45"))), "OR45: Architect risk-note dispatch")
elif scenario == "s283":
    # Structure oracles replaced by #499 (AC14, A41): placement by the
    # inventory part column, OR45 its own item in part 1, OR21 cites OR45.
    found = items(orch)
    for line in tsv.splitlines()[1:]:
        cols = line.split("\t")
        if len(cols) < 4 or cols[2] == "retired":
            continue
        entries = found.get(cols[0], [])
        require(len(entries) == 1, f"{cols[0]} in exactly one part (found {len(entries)})")
        require(str(entries[0][0]) == cols[3], f"{cols[0]} sits in part {entries[0][0]}, inventory says {cols[3]}")
    rule("OR45", "judgment", 1)
    ov = rule("OR21")
    require(re.search(r"\bOR45\b", ov), "OR21 cites OR45")
    require("SKILL.md" in ov, "OR21 names SKILL.md")
    require(not re.search(r"(?<![\w/])#\d+", ov), "OR21 carries a bare #<n> pointer")
else:
    raise AssertionError(f"unknown scenario {scenario}")

# The same document checks must reject one controlled break in each rule or
# record. These are private test inputs; the injected document seam is unchanged.
if not os.environ.get("DT415_NEGATIVE"):
    mutations = {
        "s277": [
            ("- OR38 ", "- XR38 ", "OR38 removed"),
            ("- OR41 ", "- XR41 ", "OR41 removed"),
            ("keeps `Disposition`, scope-expansion rules", "keeps rules", "Disposition and scope-expansion dropped"),
            ("by `Fix cost`", "pending maintainer Q1; by `Fix cost`", "pending wording returns"),
            ("Each row logged in Pipeline log.", "", "OR37 log destination dropped"),
            ("- OR39 ", "## Elsewhere\n\n- OR39 ", "OR39 moved out of the section"),
        ],
        "s288": [
            ("by `Fix cost` (`SKILL.md`)", "File a low-severity finding as an issue by default; never in a low-only round (`Fix cost`, `SKILL.md`)", "row reverted to old text"),
            ("by `Fix cost` (`SKILL.md`)", "by cost (defined elsewhere)", "Fix cost pointer removed"),
            ("Cap: one trivial-fix commit per PR", "\n  Cap: one trivial-fix commit per PR", "item split over two lines"),
            ("keeps `Disposition`, scope-expansion rules", "keeps rules", "Disposition and scope-expansion dropped"),
            ("by `Fix cost` (`SKILL.md`)", "by `Fix cost` (`SKILL.md`, at most 10 changed lines)", "limit restated in the item"),
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
            ("- OR43 ", "- XR43 ", "OR43 removed"),
            (["- OR43 Never", "<!-- session-context: slot -->"], ["- XR43 Never", "<!-- session-context: slot -->\n- OR43 Never decided by orchestrator (moved)."], "OR43 moved to part 2"),
        ],
        "s279": [
            ("Waiver = maintainer decision via OR45.", "Waiver = maintainer decision.", "OR37 no longer cites OR45"),
            ("else not scratch run.", "else not scratch run. Continue the previous Reviewer for the next round.", "contradictory Reviewer item"),
            ("else not scratch run.", "else not scratch run. Patch a design-class finding directly in code instead of routing to Architect.", "contradictory design item"),
        ],
        "s280": [
            ("<decision>.` Maintainer", "<decision> <!-- model-record: stage=Review -->.` Maintainer", "marker in record"),
            ("until change reaches `main`", "until the merge", "ambiguous until the merge"),
            ("until change reaches `main`", "until the release-branch merge", "release-branch merge deadline"),
            (", including after work-item merge into release branch", "", "release-branch coverage dropped"),
            ("Maintainer may object until change reaches `main`, including after work-item merge into release branch.", "Log it.", "log-only rule, no deadline"),
            ("Maintainer may object", "Objection rule pending Q2; maintainer may object", "pending wording"),
        ],
        "s281": [
            ("Before the decision is recorded", "After the decision is recorded", "pushback order"),
            ("numbered human decision links the pushback", "numbered human decision follows", "pushback link"),
            ("Reviewer is a fresh Reviewer", "Reviewer can continue", "fresh Reviewer"),
        ],
        "s282": [("**Likely consequence**", "**Possible outcome**", "risk-note field")],
        "s283": [
            ("- OR36 ", "- XR36 ", "OR36 removed"),
            ("<!-- session-context: slot -->", "- OR36 Resume, copied into part 1.\n<!-- session-context: slot -->", "OR36 in both parts"),
            ("- OR45 ", "  OR45 ", "OR45 merged into the item before it"),
            ("so A29 flow (OR45) applies", "so A29 flow (#415) applies", "bare #n in OR21, OR45 dropped"),
            ("(format in `SKILL.md`;", "(format elsewhere;", "SKILL.md dropped from OR21"),
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

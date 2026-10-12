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
    require(re.search(r"file[^.]*\bissue\b[^.]*\bby default", rule, re.I), "low finding: file an issue by default")
    require(re.search(r"text-only", rule, re.I) and re.search(r"medium or high", rule, re.I)
            and re.search(r"already required", rule, re.I), "low finding: text-only exception tied to a round already required by medium/high")
    require(re.search(r"never[^.]*low-only", rule, re.I), "low finding: no text-only fix in a low-only round")
    require("`Disposition`" in rule and re.search(r"scope-expansion", rule, re.I), "low finding: Disposition and scope-expansion kept")
    require(not re.search(r"pending|\bQ1\b|do not infer|if the maintainer|fix in the PR by default|default[^.]*fix", rule, re.I), "low finding: pending or fix-default wording")
    require(not re.search(r"pending|\bQ[12]\b", low[2], re.I), "low finding: pending log wording")
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
else:
    raise AssertionError(f"unknown scenario {scenario}")

# The same document checks must reject one controlled break in each rule or
# record. These are private test inputs; the injected document seam is unchanged.
if not os.environ.get("DT415_NEGATIVE"):
    mutations = {
        "s277": [
            ("Use an available tool", "Use any tool", "scratch rule"),
            ("cheapest model", "preferred model", "model rule"),
            ("File a low-severity finding as an issue by default", "Fix a low-severity finding in the PR by default", "flipped default"),
            ("only during a round already required by a medium or high finding, never in a low-only round", "during any round, including a low-only round", "exception widened to low-only round"),
            ("only during a round already required by a medium or high finding, never in a low-only round", "never in a low-only round", "exception loses medium/high anchor"),
            ("`Disposition` and scope-expansion rules", "rules", "Disposition and scope-expansion dropped"),
            ("File a low-severity finding", "Pending maintainer Q1; file a low-severity finding", "pending wording returns"),
            ("next free number", "any number", "numbering rule"),
            ("| Tool for a scratch run |", "| Other choice |", "scratch row"),
            ("| Pipeline log |\n| Model", "| |\n| Model", "scratch log cell"),
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
        "s283": [("## Decided without asking", "\n" * 81 + "## Decided without asking", "line cap")],
    }
    for old, new, label in mutations[scenario]:
        source = roles if scenario in ("s281", "s282") else orch
        require(old in source, f"mutation anchor absent: {label}")
        env = os.environ.copy()
        env["DT415_NEGATIVE"] = "1"
        env["DT415_ROLES" if scenario in ("s281", "s282") else "DT415_ORCH"] = source.replace(old, new, 1)
        result = subprocess.run([sys.executable, __file__, str(root), scenario], env=env, capture_output=True, text=True)
        require(result.returncode != 0 and f"{scenario}:" in result.stderr, f"controlled break escaped: {label}")

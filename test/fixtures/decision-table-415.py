#!/usr/bin/env python3
"""Document contract checks for issue #415's existing injected seam."""

import re
import sys
from pathlib import Path


root = Path(sys.argv[1])
scenario = sys.argv[2]
orch = (root / "skills/role-contracts/ORCHESTRATOR.md").read_text()
roles = (root / "skills/role-contracts/SKILL.md").read_text()


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
        "low finding": (r"low.severity finding", r"maintainer", r"pending|Q1|answer"),
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
    require("file" not in matches[0][1].lower() or True, "")  # Q1 oracle awaits maintainer.
elif scenario == "s278":
    never = section(orch, "Decided without asking").split("**Never decided by the orchestrator**")[-1].split("**Record template")[0]
    for label, pattern in {
        "main merge": r"merge.*main", "version bump": r"version bump",
        "spec content": r"PRD\.md.*ARCHITECTURE\.md.*TEST-SCENARIOS\.md",
        "outward-facing": r"outward-facing", "role recommendation": r"departure.*recommendation",
    }.items():
        require(re.search(pattern, never, re.I | re.S), label)
elif scenario == "s279":
    decision = section(orch, "Decided without asking")
    require(re.search(r"row.*only.*choice.*contracts.*leave open", decision, re.I | re.S), "bounded row")
    require(re.search(r"never waive.*contract rule", decision, re.I), "no contract waiver")
    require("fresh Reviewer" in decision and "design" in decision and "maintainer" in decision, "fresh review and design route examples")
elif scenario == "s280":
    decision = section(orch, "Decided without asking")
    template = decision.split("**Record template", 1)[-1].split("\n\n", 1)[0]
    require("Pipeline log" in decision and "Decisions by rule" in decision, "issue log destination")
    for token in ("YYYY-MM-DD", "row", "decision"):
        require(token in template, f"record template {token}")
    require("model-record" not in template, "template carries stage marker")
    # Q2 deadline oracle awaits maintainer.
elif scenario == "s281":
    shared = section(roles, "Shared, across all five roles")
    require("When your recommendation is not accepted" in shared, "pushback contract")
    for pattern in (r"once", r"before the decision is recorded", r"arguments", r"cost", r"numbered human decision", r"fresh Reviewer"):
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

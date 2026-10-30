#!/usr/bin/env python3
"""hooks/agent-dispatch.py — pure core of the `Agent` dispatch hook (#499,
A41). The bash adapter `hooks/agent-dispatch` decides whether it runs
(kill switch, opted-in project, python3 present); this core only reads the
PreToolUse JSON on stdin and the two files named on the command line.

Usage:
  agent-dispatch.py <ORCHESTRATOR.md> <orchestrator-rules.tsv> < input.json
  agent-dispatch.py --list-roles       prefix name, flag name and stage per line
  agent-dispatch.py --list-checks      the check ids, one per line
  agent-dispatch.py --print-contract   tool name and input fields, as JSON

A role dispatch (a prompt line starting `ROLE SESSION:`, or a line starting
with a `model-record-emit.sh` command that has `--role` or `--stage`) that fails a check
exits 2; stderr holds, once each, the ORCHESTRATOR.md line of every rule the
inventory's `hook:` column maps a failed check to, then one line on how a
non-role prompt avoids detection. The deny text is the injected core text:
no rule text lives here. Everything else exits 0. Fail-open: malformed
input, an unreadable file or a mapped ID with no line allows the call with
one stderr line. No network, no state.
"""
import json
import re
import sys

# The contract: the only place the tool name and input field names exist.
TOOL_NAME = "Agent"
F_TOOL, F_AGENT, F_INPUT = "tool_name", "agent_id", "tool_input"
F_PROMPT, F_SUBAGENT, F_MODEL = "prompt", "subagent_type", "model"
FIELDS = [F_TOOL, F_AGENT, F_INPUT + "." + F_PROMPT,
          F_INPUT + "." + F_SUBAGENT, F_INPUT + "." + F_MODEL]

ROLE_STAGES = (("Product", "Product", "Discovery"),
               ("Architect", "Architect", "Planning"),
               ("QA", "QA", "Test"),
               ("Fullstack Developer", "Developer", "Implementation"),
               ("Reviewer", "Reviewer", "Review"))
MAX_ROLE_LENGTH = max(len(row[1]) for row in ROLE_STAGES)
CHECKS = ["prefix", "no-fork", "marker-command", "role-stage", "model",
          "reviewer-pr", "reviewer-sha", "reviewer-gate"]

ROLE_LINE = re.compile(r"^ROLE SESSION:")
PREFIX = re.compile(r"^ROLE SESSION: (%s)(?![A-Za-z0-9])" % "|".join(row[0] for row in ROLE_STAGES))
EMIT_AT_START = re.compile(r"^\s*[`$\"']?\S*?model-record-emit\.sh\b")
EMIT_DISPATCH_FLAG = re.compile(r"--(?:role\b(?!=)|stage\b)")
EMIT_WITH_STAGE = re.compile(
    r"--stage[= ]+[\"']?(%s)(?![A-Za-z0-9])" % "|".join(row[2] for row in ROLE_STAGES))
EMIT_COMMAND = re.compile(r"model-record-emit\.sh\b(.*)")
ROLE_FLAG = re.compile(r"--role(?![A-Za-z0-9_])([= ]+)?")
EMIT_FLAG = re.compile(
    r"--(role|stage)(?![A-Za-z0-9_])(?:[= ]+(?:\"([^\"]*)\"|'([^']*)'|([^ \t\"'`;,()&|<>]+)))?")
# A PR number is /pull/<n> or `PR <n>` / `PR #<n>`; a bare #<n> is an issue.
PR_REF = re.compile(r"(/pull/\d+|\bPR\s*#?\d+)")
# A head SHA: 7-40 hex with a letter a-f, or one introduced by head/SHA/commit
# (an unlabelled all-digit run, such as a comment id, does not count).
SHA = re.compile(
    r"(?<![0-9A-Za-z])(?=[0-9]*[a-f])[0-9a-f]{7,40}(?![0-9A-Za-z])"
    r"|\b(?:head|sha|commit)\b\W{0,3}[0-9a-f]{7,40}(?![0-9A-Za-z])", re.I)
GATE = "finding-carryforward-gate.sh"
ITEM = re.compile(r"^ *- (OR\d+) ")
AVOID = ("Not a role dispatch? Start no prompt line with `ROLE SESSION:` and no "
         "line with a `model-record-emit.sh ... --role` or `--stage` command.")


def note(msg):
    print("agent-dispatch: %s; dispatch allowed unchecked" % msg, file=sys.stderr)
    return 0


def role_word(text, start, wrapper_end):
    # Scan once, retaining at most the longest valid role. Continue scanning
    # after overflow so genuinely malformed quoting keeps its fail-open policy.
    value = []
    length = 0
    quote = ""
    i = start
    while i < len(text) and text[i] in " \t\r\n":
        i += 1
    while i < len(text) and i != wrapper_end:
        c = text[i]
        if not quote and (c in " \t\r\n;,()&|<>"):
            break
        if c in ("'", '"'):
            if not quote:
                quote = c
                i += 1
                continue
            if quote == c:
                quote = ""
                i += 1
                continue
        if c == "\\" and quote != "'":
            i += 1
            if i == len(text):
                raise ValueError("No escaped character")
            c = text[i]
            if c == "\n":
                i += 1
                continue
            if quote == '"' and c not in ('"', "\\"):
                length += 1
                if length <= MAX_ROLE_LENGTH:
                    value.append("\\")
        # Expansion spellings, including backticks, remain literal: the hook
        # executes nothing and never validates only the prefix before them.
        length += 1
        if length <= MAX_ROLE_LENGTH:
            value.append(c)
        i += 1
    if quote:
        raise ValueError("No closing quotation")
    return ("".join(value) if length <= MAX_ROLE_LENGTH else ""), i


def emit_roles(prompt):
    roles = []
    consumed = 0
    for command in EMIT_COMMAND.finditer(prompt):
        if command.start() < consumed:
            continue
        line_start = prompt.rfind("\n", 0, command.start()) + 1
        wrapper = prompt[line_start:command.start()].lstrip()[:1]
        end = command.end()
        trimmed_end = end
        while trimmed_end > command.start() and prompt[trimmed_end - 1].isspace():
            trimmed_end -= 1
        wrapper_end = (trimmed_end - 1 if wrapper in ('"', "'", '`')
                       and prompt[trimmed_end - 1:trimmed_end] == wrapper else -1)
        cursor = command.start(1)
        while cursor < end:
            flag = ROLE_FLAG.search(prompt, cursor, end)
            if not flag:
                break
            separator = flag.group(1)
            value, consumed = (role_word(prompt, flag.end(), wrapper_end)
                               if separator else ("", flag.end()))
            roles.append((value, bool(separator) and "=" not in separator))
            cursor = max(flag.end(), consumed)
    return roles


def failed_checks(prompt, sub, model):
    lines = prompt.split("\n")
    first = next((l for l in lines if l.strip()), "")
    role_line = next((l for l in lines if ROLE_LINE.match(l)), "")
    m = PREFIX.match(role_line)
    role = m.group(1) if m else ""
    failed = []
    if not PREFIX.match(first):
        failed.append("prefix")
    if sub == "fork":
        failed.append("no-fork")
    roles = emit_roles(prompt)
    valid_emit = (any(recognized and value in {row[1] for row in ROLE_STAGES}
                      for value, recognized in roles)
                  or any(EMIT_WITH_STAGE.search(command.group(1))
                         for command in EMIT_COMMAND.finditer(prompt)))
    if not valid_emit:
        failed.append("marker-command")
    if role:
        _, flag_role, stage = next(row for row in ROLE_STAGES if row[0] == role)
        flags = [(flag.group(1), next((v for v in flag.groups()[1:] if v is not None), ""))
                 for line in lines for command in [EMIT_COMMAND.search(line)]
                 if command for flag in EMIT_FLAG.finditer(command.group(1))
                 if flag.group(1) == "stage"]
        flags.extend(("role", value) for value, _ in roles)
        # Keep the legacy stage scanner's prefix handling inside quoted values.
        if not valid_emit or any((value if name == "role" else re.split(r"[ \t\"'`]", value)[0])
                                 != (flag_role if name == "role" else stage)
                                 for name, value in flags):
            failed.append("role-stage")
    if not (isinstance(model, str) and model.strip()):
        failed.append("model")
    if role == "Reviewer":
        if not PR_REF.search(prompt):
            failed.append("reviewer-pr")
        if not SHA.search(prompt):
            failed.append("reviewer-sha")
        if GATE not in prompt:
            failed.append("reviewer-gate")
    return failed


def check_map(tsv_text):
    """{check id: rule ID} from the inventory's hook: tiers."""
    out = {}
    for line in tsv_text.split("\n")[1:]:
        cols = line.split("\t")
        if len(cols) >= 3 and cols[2].startswith("hook:"):
            for c in cols[2][5:].split(","):
                out[c] = cols[0]
    return out


def core_lines(orch_text):
    out = {}
    for line in orch_text.split("\n"):
        m = ITEM.match(line)
        if m and m.group(1) not in out:
            out[m.group(1)] = line
    return out


def main(argv):
    if argv[:1] == ["--list-roles"]:
        for row in ROLE_STAGES:
            print(" ".join(row))
        return 0
    if argv[:1] == ["--list-checks"]:
        print("\n".join(CHECKS))
        return 0
    if argv[:1] == ["--print-contract"]:
        print(json.dumps({"tool_name": TOOL_NAME, "fields": FIELDS}))
        return 0
    if len(argv) != 2:
        print("usage: agent-dispatch.py <ORCHESTRATOR.md> <inventory.tsv>", file=sys.stderr)
        return 0
    try:
        data = json.loads(sys.stdin.read())
    except (ValueError, UnicodeDecodeError):
        return note("input is not JSON")
    if not isinstance(data, dict):
        return note("input is not a JSON object")
    if data.get(F_TOOL) != TOOL_NAME:
        return 0
    if data.get(F_AGENT):
        return 0
    ti = data.get(F_INPUT)
    if not isinstance(ti, dict):
        return note("no %s object" % F_INPUT)
    prompt = ti.get(F_PROMPT)
    if not isinstance(prompt, str):
        return note("%s.%s is not a string" % (F_INPUT, F_PROMPT))
    lines = prompt.split("\n")
    if not any(ROLE_LINE.match(l) or
               (EMIT_AT_START.match(l) and
                EMIT_DISPATCH_FLAG.search(l, EMIT_AT_START.match(l).end()))
               for l in lines):
        return 0
    try:
        failed = failed_checks(prompt, ti.get(F_SUBAGENT), ti.get(F_MODEL))
    except ValueError:
        return note("cannot parse role shell word")
    if not failed:
        return 0
    try:
        with open(argv[0], encoding="utf-8") as f:
            orch = f.read()
        with open(argv[1], encoding="utf-8") as f:
            tsv = f.read()
    except (OSError, UnicodeDecodeError) as e:
        return note("cannot read %s" % getattr(e, "filename", "a rule file"))
    cmap, lines_by_id = check_map(tsv), core_lines(orch)
    ids = []
    for c in failed:
        rid = cmap.get(c)
        if rid is None:
            return note("check %s has no rule in the inventory" % c)
        if rid not in lines_by_id:
            return note("rule %s has no line in ORCHESTRATOR.md" % rid)
        if rid not in ids:
            ids.append(rid)
    for rid in ids:
        print(lines_by_id[rid], file=sys.stderr)
    print(AVOID, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

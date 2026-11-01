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

A role dispatch (a prompt line starting `ROLE SESSION:`, or a line mentioning
a `model-record-emit.sh` command that has `--role` or `--stage`) that fails a check
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
CHECKS = ["prefix", "no-fork", "marker-command", "role-stage", "model",
          "reviewer-pr", "reviewer-sha", "reviewer-gate"]

ROLE_LINE = re.compile(r"^ROLE SESSION:")
PREFIX = re.compile(r"^ROLE SESSION: (%s)(?![A-Za-z0-9_-])" % "|".join(row[0] for row in ROLE_STAGES))
EMIT_DISPATCH_FLAG = re.compile(r"--(?:role\b(?!=)|stage\b)")
EMIT_WITH_STAGE = re.compile(
    r"--stage[= ]+[\"']?(%s)(?![A-Za-z0-9])" % "|".join(row[2] for row in ROLE_STAGES))
EMIT_WORD = re.compile(r"model-record-emit\.sh\b")
# A48 bounds apply before argument splitting, including original unit text.
MAX_INPUT_BYTES = 32 * 1024 * 1024
MAX_PROMPT_CHARS = 4 * 1024 * 1024
MAX_UNIT_CHARS = 64 * 1024
MAX_UNIT_LINES = 32
KNOWN_FLAGS = {"--role", "--stage", "--model", "--floor-basis", "--effort"}
CONTINUABLE = re.compile(r"\s*(?:--(?:role|stage|model|floor-basis|effort)(?=[=\s]|$)|\\$)")
PATH_WRAPPER = re.compile(r"([\"'`])[^\s\"'`]*$")
WORD_SPECIAL = re.compile(r"[\s'\"\\;,()&|<>]")
DOUBLE_SPECIAL = re.compile(r'["\\\\]')
QUOTE_SPECIAL = re.compile(r"['\"\\#]")

ROLE_FLAG = re.compile(r"--role(?![A-Za-z0-9_])([= ]+)?")
STAGE_FLAG = re.compile(
    r"--stage(?![A-Za-z0-9_])(?:[= ]+(?:\"([^\"]*)\"|'([^']*)'|([^ \t\"'`;,()&|<>]+)))?")
# A bare #<n> is an issue; PR labels and pull URLs identify pull requests.
PR_REF = re.compile(r"(/pull/\d+|\b(?:PR|pull request)\s*:?\s*#?\d+)", re.I)
# Only labelled head evidence counts; old/previous references are historical.
SHA = re.compile(
    r"\b(?:(old|previous)\s+)?(?:head|sha|commit)\b\W{0,3}"
    r"[0-9a-f]{7,40}(?![0-9A-Za-z])", re.I)
GATE = "finding-carryforward-gate.sh"
ITEM = re.compile(r"^ *- (OR\d+) ")
AVOID = ("Not a role dispatch? Start no prompt line with `ROLE SESSION:` and no "
         "line with a `model-record-emit.sh ... --role` or `--stage` command.")


def note(msg):
    msg = " ".join(msg[:200].split())
    print("agent-dispatch: %s; dispatch allowed unchecked" % msg, file=sys.stderr)
    return 0


def uncomment(line, quote):
    """Strip a physical-line comment before testing its continuation marker.

    Quote state belongs only to an explicitly continued unit. Escapes skip
    the next character; a hash starts a comment only after unescaped whitespace.
    """
    i = 0
    escaped = -1
    while True:
        match = QUOTE_SPECIAL.search(line, i)
        if not match:
            return line, quote
        i = match.start()
        c = line[i]
        if c == "\\" and quote != "'":
            escaped = i + 1
            i += 2
            continue
        if c == "#" and not quote and (i == 0 or (line[i - 1].isspace() and escaped != i - 1)):
            return line[:i], quote
        if c in ("'", '\"'):
            if not quote:
                quote = c
            elif quote == c:
                quote = ""
        i += 1


def emit_units(prompt):
    """Collect independent emit-line suffixes, joining explicit continuations.

    The original physical text counts toward the unit cap, even text before
    the script and comments. Only collected suffixes can reach the splitter.
    """
    lines = prompt.replace("\r\n", "\n").split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        match = EMIT_WORD.search(line)
        if not match:
            continue
        size = len(line)
        if size > MAX_UNIT_CHARS:
            raise ValueError("emit unit exceeds character cap")
        suffix = line[match.end():]
        wrapper_match = PATH_WRAPPER.search(line[:match.start()])
        wrapper = wrapper_match.group(1) if wrapper_match else ""
        eligible = bool(CONTINUABLE.match(suffix))
        parts = []
        quote = ""
        count = 1
        wrapper_closed = False
        while True:
            # Presentation wrappers enclose comments too. Remove the closing
            # wrapper before a comment can discard it from the argument text.
            if wrapper and suffix.rstrip().endswith(wrapper):
                suffix = suffix.rstrip()[:-1]
                wrapper_closed = True
            text, quote = uncomment(suffix, quote)
            slashes = len(text) - len(text.rstrip("\\"))
            continued = eligible and slashes % 2 == 1
            parts.append(text[:-1] if continued else text)
            if not continued:
                break
            if count == MAX_UNIT_LINES or i == len(lines) or (i == len(lines) - 1 and not lines[i]):
                raise ValueError("emit continuation exceeds line cap or reaches EOF")
            suffix = lines[i]
            i += 1
            count += 1
            size += 1 + len(suffix)
            if size > MAX_UNIT_CHARS:
                raise ValueError("emit unit exceeds character cap")
        text = "".join(parts)
        # Bare/prose mentions have no argument syntax and open no quote state.
        if not (EMIT_DISPATCH_FLAG.search(text) or "--role=" in text):
            continue
        if wrapper and not wrapper_closed:
            raise ValueError("unmatched emit wrapper")
        yield text


def unit_words(text):
    """Bounded POSIX-style words, with decoded values and raw source spans.

    Punctuation separates words, backticks are literal, and no shell syntax
    is executed or expanded. Each source character is visited once.
    """
    words = []
    i = 0
    while i < len(text):
        if text[i].isspace() or text[i] in ";,()&|<>":
            i += 1
            continue
        start = i
        value = []
        while i < len(text):
            match = WORD_SPECIAL.search(text, i)
            end = match.start() if match else len(text)
            value.append(text[i:end])
            i = end
            if i == len(text) or text[i].isspace() or text[i] in ";,()&|<>":
                break
            c = text[i]
            if c == "\\":
                if i + 1 == len(text):
                    raise ValueError("dangling escape")
                value.append(text[i + 1])
                i += 2
            elif c == "'":
                end = text.find("'", i + 1)
                if end < 0:
                    raise ValueError("unbalanced quote")
                value.append(text[i + 1:end])
                i = end + 1
            else:
                i += 1
                while True:
                    match = DOUBLE_SPECIAL.search(text, i)
                    end = match.start() if match else len(text)
                    value.append(text[i:end])
                    i = end
                    if i == len(text):
                        raise ValueError("unbalanced quote")
                    if text[i] == '\"':
                        i += 1
                        break
                    if i + 1 == len(text):
                        raise ValueError("dangling escape")
                    if text[i + 1] not in ('\"', "\\"):
                        value.append("\\")
                    value.append(text[i + 1])
                    i += 2
        words.append(("".join(value), start, i))
    return words


def emit_flags(units):
    roles, stages, stage_valid = [], [], False
    for text in units:
        words = unit_words(text)
        i = 0
        while i < len(words):
            value, start, end = words[i]
            raw = text[start:end]
            role_flag = ROLE_FLAG.match(raw)
            stage_flag = STAGE_FLAG.match(text, start)
            has_value = (i + 1 < len(words) and words[i + 1][0].split("=", 1)[0] not in KNOWN_FLAGS)
            if role_flag:
                separator = role_flag.group(1)
                recognized = bool(separator) and "=" not in separator
                # Literal spaces only: preserve the unsupported role-tab form.
                if raw == "--role":
                    separator = text[end:words[i + 1][1]] if has_value else ""
                    recognized = bool(separator) and all(c == " " for c in separator)
                    role_value = words[i + 1][0] if has_value else ""
                else:
                    role_value = value[len("--role"):].lstrip("= ")
                roles.append((role_value if recognized else "", recognized))
            elif stage_flag:
                stages.append(next((v for v in stage_flag.groups() if v is not None), ""))
                stage_valid = stage_valid or bool(EMIT_WITH_STAGE.match(text, start))
            if raw in KNOWN_FLAGS and has_value:
                i += 1
            i += 1
    return roles, stages, stage_valid


def failed_checks(prompt, sub, model, units):
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
    roles, stages, stage_valid = emit_flags(units)
    valid_emit = (any(recognized and value in {row[1] for row in ROLE_STAGES}
                      for value, recognized in roles) or stage_valid)
    if not valid_emit:
        failed.append("marker-command")
    if role:
        _, flag_role, stage = next(row for row in ROLE_STAGES if row[0] == role)
        flags = [("stage", value) for value in stages]
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
        if not any(not match.group(1) for match in SHA.finditer(prompt)):
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
            print("\t".join(row))
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
        raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
        if len(raw) > MAX_INPUT_BYTES:
            return note("input exceeds byte cap")
        data = json.loads(raw.decode("utf-8"))
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
    if len(prompt) > MAX_PROMPT_CHARS:
        return note("prompt exceeds character cap")
    units = list(emit_units(prompt))
    if not (any(ROLE_LINE.match(l) for l in prompt.split("\n")) or
            any(EMIT_DISPATCH_FLAG.search(text) for text in units)):
        return 0
    try:
        failed = failed_checks(prompt, ti.get(F_SUBAGENT), ti.get(F_MODEL), units)
    except ValueError:
        return note("cannot parse role shell word")
    if not failed:
        return 0
    try:
        with open(argv[0], encoding="utf-8") as f:
            orch = f.read()
        with open(argv[1], encoding="utf-8") as f:
            tsv = f.read()
    except (OSError, UnicodeDecodeError):
        return note("cannot read rule files")
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
    try:
        result = main(sys.argv[1:])
    except Exception:
        result = note("cannot parse dispatch input")
    sys.exit(result)

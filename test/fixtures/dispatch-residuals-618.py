"""B10a public dispatch CLI regressions; mutations only touch scratch hook copies."""
import ast
import json
from pathlib import Path
import subprocess
import sys

GROUP, ROOT, SCRATCH = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
HOOK = ROOT / "hooks/agent-dispatch.py"
ORCH = ROOT / "skills/role-contracts/ORCHESTRATOR.md"
TSV = ROOT / "skills/role-contracts/orchestrator-rules.tsv"
LINES = {line.split()[1]: line for line in ORCH.read_text().splitlines()
         if line.startswith("- OR")}
AVOID = ("Not a role dispatch? Start no prompt line with `ROLE SESSION:` and no "
         "line with a `model-record-emit.sh ... --role` or `--stage` command.")
EMIT = "/clone/skills/pre-merge-review/model-record-emit.sh"
QA = "ROLE SESSION: QA\n" + EMIT + " --role QA --model m"
REVIEW = "ROLE SESSION: Reviewer\n" + EMIT + " --role Reviewer --model m\n"
GATE = ", finding-carryforward-gate.sh 533"
failures = 0


def run(prompt, hook=HOOK):
    envelope = {"tool_name": "Agent", "tool_input": {
        "prompt": prompt, "subagent_type": "general-purpose", "model": "m"}}
    result = subprocess.run([sys.executable, "-I", str(hook), str(ORCH), str(TSV)],
                            input=json.dumps(envelope).encode(), capture_output=True, timeout=5)
    return result.returncode, result.stdout, result.stderr


def accepts(result, expected):
    status, out, err = result
    if expected == "silent":
        return result == (0, b"", b"")
    if expected == "unchecked":
        lines = err.splitlines()
        return (status == 0 and not out and len(lines) == 1 and len(err) <= 1024
                and lines[0].startswith(b"agent-dispatch:")
                and lines[0].endswith(b"; dispatch allowed unchecked"))
    return result == (2, b"", (LINES[expected] + "\n" + AVOID + "\n").encode())


def mutation(kind, check):
    """Inject one named regression without relying on a regex's source spelling.

    Every assertion runs its mutant through the same CLI and oracle. Red
    working-tree assertions stay red independently of these controls; their
    mutant rejection becomes a discrimination witness once the product is green.
    """
    tree = ast.parse(HOOK.read_text())
    if kind == "silent-unchecked":
        function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "note")
        function.body = ast.parse("return 0").body
    elif kind == "valid-unchecked":
        function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "main")
        function.body.insert(0, ast.parse('return note("mutant marks a valid command unchecked")').body[0])
    else:
        function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "failed_checks")
        returns = [n for n in ast.walk(function) if isinstance(n, ast.Return)
                   and isinstance(n.value, ast.Name) and n.value.id == "failed"]
        assert len(returns) == 1, "failed_checks result seam changed; review mutation"
        if kind == "disabled-check":
            returns[0].value = ast.parse("[c for c in failed if c != " + repr(check) + "]", mode="eval").body
        else:
            returns[0].value = ast.parse("failed + [" + repr(check) + "]", mode="eval").body
    ast.fix_missing_locations(tree)
    path = SCRATCH / (kind + "-" + check + ".py")
    path.write_text(ast.unparse(tree) + "\n")
    return path


def assertion(name, prompt, expected, check, kind=None):
    global failures
    result = run(prompt)
    good = accepts(result, expected)
    print(("GREEN " if good else "RED ") + GROUP + "/" + name
          + " exit=" + str(result[0]) + " expected=" + expected, flush=True)
    failures += not good
    if kind is None:
        kind = "disabled-check" if expected.startswith("OR") else "forced-check"
    mutant = mutation(kind, check)
    altered = run(prompt, mutant)
    killed = not accepts(altered, expected) and b"Traceback" not in altered[2]
    label = "KILLED " if good else "REJECTED-RED-BASELINE "
    print((label if killed else "SURVIVED ") + GROUP + "/" + name + ": " + kind, flush=True)
    failures += not killed


if GROUP == "prefix":
    assertion("suffixed-QA", QA.replace("ROLE SESSION: QA", "ROLE SESSION: QA-lead"), "OR8", "prefix")
    assertion("exact-QA", QA, "silent", "prefix")
elif GROUP == "sha":
    invalid = [
        ("uuid-path", "scratch /tmp/dcca323c-8b26-4f9a-bc29-fd851ae7ace4/report"),
        ("unlabelled-word", "word defaced"),
        ("unlabelled-hex", "artifact 0123abc4567def"),
        ("historical-head", "previous head 0123abc4567def"),
        ("historical-sha", "old SHA 0123abc4567def"),
        ("historical-commit", "previous commit 0123abc4567def"),
    ]
    for name, text in invalid:
        assertion(name, REVIEW + "PR #533, " + text + GATE, "OR14", "reviewer-sha")
        # Change only the missing head evidence: the same incidental/historical
        # material must not veto a separately explicit current head reference.
        assertion(name + "-with-head", REVIEW + "PR #533, " + text
                  + "; current head abcdef1234567890" + GATE, "silent", "reviewer-sha")
    for text in ["head 0123abc", "SHA 0123abc4567def", "commit " + "0123456789abcdef" * 2 + "01234567", "head 1234567890"]:
        assertion(text, REVIEW + "PR #533, " + text + GATE, "silent", "reviewer-sha")
elif GROUP == "pr":
    for pr in ["pull request #533", "pr #533", "PR: #533", "PR #533", "PR 533", "https://github.com/o/r/pull/533"]:
        assertion(pr, REVIEW + pr + ", head 0123abc4567def" + GATE, "silent", "reviewer-pr")
    for pr in ["work item #533", "https://github.com/o/r/issues/533", "#533"]:
        assertion(pr, REVIEW + pr + ", head 0123abc4567def" + GATE, "OR14", "reviewer-pr")
elif GROUP == "wrapper":
    for quote in ["'", '\"', "`"]:
        command = quote + EMIT + " --role QA --model m # trailing comment" + quote
        prompt = "ROLE SESSION: QA\n" + command
        assertion(repr(quote) + "-matching", prompt, "silent", "role-stage", "valid-unchecked")
        assertion(repr(quote) + "-independent-mismatch", prompt + "\n" + EMIT
                  + " --role Architect --model m", "OR31", "role-stage")
        assertion(repr(quote) + "-comment-is-not-a-flag", prompt.replace("trailing comment", "--role Architect"),
                  "silent", "role-stage", "valid-unchecked")
        unmatched = prompt[:-1]
        assertion(repr(quote) + "-unmatched", unmatched, "unchecked", "role-stage", "silent-unchecked")
        assertion(repr(quote) + "-unmatched-with-mismatch", unmatched + "\n" + EMIT
                  + " --role Architect --model m", "unchecked", "role-stage", "silent-unchecked")
else:
    raise SystemExit("unknown residual group: " + GROUP)
raise SystemExit(1 if failures else 0)

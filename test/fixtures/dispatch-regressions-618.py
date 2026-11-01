"""S509: public CLI preservation and bounded-time checks; no product writes."""
import ast
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT, SCRATCH = map(Path, sys.argv[1:])
HOOK = ROOT / "hooks/agent-dispatch.py"
ORCH = ROOT / "skills/role-contracts/ORCHESTRATOR.md"
TSV = ROOT / "skills/role-contracts/orchestrator-rules.tsv"
LINES = {line.split()[1]: line for line in ORCH.read_text().splitlines()
         if line.startswith("- OR")}
AVOID = ("Not a role dispatch? Start no prompt line with `ROLE SESSION:` and no "
         "line with a `model-record-emit.sh ... --role` or `--stage` command.")
EMIT = "/clone/skills/pre-merge-review/model-record-emit.sh"
BASE = SCRATCH / "base.py"
source = subprocess.run(["git", "show", "3047418:hooks/agent-dispatch.py"],
                        cwd=ROOT, capture_output=True, timeout=5)
if source.returncode == 0:
    BASE.write_bytes(source.stdout)
    print("baseline oracle: 3047418", flush=True)
else:
    BASE = None
    print("baseline history unavailable; using recorded verdicts", flush=True)
failures = 0


def run(hook, prompt, fork):
    envelope = {"tool_name": "Agent", "tool_input": {
        "prompt": prompt, "subagent_type": "fork" if fork else "general-purpose",
        "model": "m"}}
    start = time.monotonic()
    try:
        # subprocess.run kills and reaps its child on expiry; never leave a
        # pathological regex running after the assertion has failed.
        result = subprocess.run([sys.executable, "-I", str(hook), str(ORCH), str(TSV)],
                                input=json.dumps(envelope).encode(),
                                capture_output=True, timeout=2)
        verdict = (result.returncode, result.stdout, result.stderr)
    except subprocess.TimeoutExpired:
        verdict = None
    return verdict, time.monotonic() - start


def accepts(result, expected):
    if result is None:
        return False
    if expected == "silent":
        return result == (0, b"", b"")
    if expected == "unchecked":
        status, out, err = result
        return (status == 0 and not out and len(err.splitlines()) == 1
                and len(err) <= 1024 and err.startswith(b"agent-dispatch:")
                and err.endswith(b"; dispatch allowed unchecked\n"))
    return result == (2, b"", ("\n".join(LINES[r] for r in expected.split("+"))
                              + "\n" + AVOID + "\n").encode())


def mutant(expected, slow):
    # Mutate only a scratch hook. The timeout mutant exercises the actual
    # deadline, independently of the hook's regex spelling. Verdict mutants
    # erase a denial/diagnostic or mark a valid dispatch unchecked.
    tree = ast.parse(HOOK.read_text())
    main = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "main")
    if slow:
        main.body.insert(0, ast.parse("__import__('time').sleep(3)").body[0])
    else:
        code = ('return note("mutant unchecked")' if expected == "silent" else "return 0")
        main.body = ast.parse(code).body
    ast.fix_missing_locations(tree)
    path = SCRATCH / "mutant.py"
    path.write_text(ast.unparse(tree) + "\n")
    return path


def assertion(name, prompt, expected, fork=False, compare_base=True, slow=False):
    global failures
    if compare_base and BASE:
        baseline, elapsed = run(BASE, prompt, fork)
        good = accepts(baseline, expected) and elapsed < 2
        print(f'{"GREEN" if good else "RED"} base/{name}: expected={expected} {elapsed:.3f}s', flush=True)
        failures += not good
    result, elapsed = run(HOOK, prompt, fork)
    good = accepts(result, expected) and elapsed < 2
    actual = "TIMEOUT(killed)" if result is None else f"exit={result[0]} stderr={result[2][:85]!r}"
    print(f'{"GREEN" if good else "RED"} current/{name}: expected={expected} {actual} {elapsed:.3f}s', flush=True)
    failures += not good
    altered, elapsed = run(mutant(expected, slow), prompt, fork)
    killed = not accepts(altered, expected) and (altered is None or b"Traceback" not in altered[2])
    print(f'{"KILLED" if killed else "SURVIVED"} mutant/{name}: '
          f'{"deadline" if slow else "verdict"} {elapsed:.3f}s', flush=True)
    failures += not killed


for quote in ["`", "'", '"']:
    for mode in ["outside", "inside", "none"]:
        def command(role):
            text = EMIT + " --role " + role + " --model m"
            if mode == "inside":
                text += " # --role Architect"
            return quote + text + quote + (" # outside comment" if mode == "outside" else "")
        # Only outside-comment single/double quotes were already unchecked.
        unchecked = quote != "`" and mode == "outside"
        for label, role, fork, expected in [("fork", "QA", True, "OR7"),
                                             ("contradiction", "Architect", False, "OR31"),
                                             ("valid", "QA", False, "silent")]:
            assertion(f"wrapper-{quote}-{mode}-{label}", "ROLE SESSION: QA\n" + command(role),
                      "unchecked" if unchecked else expected, fork,
                      # Inner comments intentionally gained support in B10a;
                      # S508 pins those outcomes, rather than the older oracle.
                      compare_base=mode != "inside")

review = "ROLE SESSION: Reviewer\n" + EMIT + " --role Reviewer --model m\n"
evidence = "\nhead abcdef1234567890, finding-carryforward-gate.sh 533"
for label, text, real_pr in [("PR", "PR", False), ("pull-request", "pull request", False),
                             ("before-real-PR", "PR", True)]:
    for long in [False, True]:
        brief = review + text + " " * (200000 if long else 1)
        brief += ("\nPR #533" if real_pr else "") + evidence
        assertion(f"whitespace-{label}-{'200000' if long else 'short'}", brief,
                  "OR7" if real_pr else "OR7+OR14", fork=True, slow=long)
assertion("reviewer-valid-control", review + "PR #533" + evidence, "silent")
raise SystemExit(1 if failures else 0)

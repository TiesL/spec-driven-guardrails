"""Simulate a substitution exiting before its caller's completion sentinel."""
import os
import pathlib
import shutil
import subprocess
import sys

root, scratch = map(pathlib.Path, sys.argv[1:])
copy = scratch / "capture"
shutil.copytree(root / "lib", copy / "lib")
binpath = copy / "bin"
binpath.mkdir()
gh = binpath / "gh"
gh.write_text("#!/bin/sh\nexit 0\n")
gh.chmod(0o755)
env = dict(os.environ, PATH=str(binpath) + os.pathsep + os.environ["PATH"])
failed = False
for relative, anchor, verdict in [
    ("review-rounds.sh", 'rows=""', "review-rounds:"),
    ("skills/pre-merge-review/finding-carryforward-gate.sh", 'rows=""', "finding-carryforward:"),
]:
    original = (root / relative).read_text()
    target = copy / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    for capture in ("gh", "rr_rounds"):
        for completion in ("return", "exit"):
            # return completes an empty capture; exit prevents its sentinel.
            injection = f'{capture}() {{ {completion} 0; }}\n'
            assert original.count(anchor) == 1
            target.write_text(original.replace(anchor, injection + anchor, 1))
            p = subprocess.run(["/bin/bash", str(target), "246"], cwd=root,
                               env=env, text=True, capture_output=True)
            warning = "warning" in p.stderr.lower()
            ok = p.returncode == 0
            if completion == "return":
                ok &= not warning
                if relative == "review-rounds.sh":
                    ok &= p.stdout.startswith("review-rounds: 0\n")
                else:
                    ok &= not p.stdout
            else:
                ok &= warning and verdict not in p.stdout and not p.stdout
            label = f"{relative}/{capture}/{completion}"
            if ok:
                print("    S471/" + label + ": green")
            else:
                failed = True
                print(f"    FAIL: S471/{label}: rc={p.returncode} stdout={p.stdout!r} stderr={p.stderr!r}",
                      file=sys.stderr)
sys.exit(failed)

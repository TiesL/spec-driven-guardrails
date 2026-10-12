#!/usr/bin/env python3
"""Post synthetic inline-only stage candidates to a scratch issue and PR."""

import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, text=True).strip()


release, repo, issue, pr = sys.argv[1:5]
emitter = f"{release}/skills/pre-merge-review/model-record-emit.sh"
for stage in ("Discovery", "Planning", "Test", "Implementation"):
    marker = run(emitter, "--stage", stage, "--model", "claude-sonnet-5-5")
    subprocess.run(
        ["gh", "issue", "comment", issue, "-R", repo, "--body", f"Synthetic inline candidate for {stage}: {marker}"],
        check=True,
    )
marker = run(
    emitter,
    "--stage",
    "Review",
    "--model",
    "claude-sonnet-5-5",
    "--floor-basis",
    "Synthetic inline-only acceptance fixture",
)
subprocess.run(
    ["gh", "pr", "comment", pr, "-R", repo, "--body", f"Synthetic inline candidate for Review: {marker}"],
    check=True,
)

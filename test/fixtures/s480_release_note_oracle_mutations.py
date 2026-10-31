"""Exercise S285 through its CLI, mutating only a disposable fixture's notes."""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
scenario = (root / "TEST-SCENARIOS.md").read_text().split("### S285 —", 1)[1].split("\n### ", 1)[0]
listed = scenario.split("case-insensitively:", 1)[1].split(". A word boundary", 1)[0]
scenario_negators = re.findall(r"`([a-z]+)`", listed)
source = (root / "test/cases/s285_unreleased_408_notes.sh").read_text()
test_negators = re.search(r"^negators='([^']+)'$", source, re.M).group(1).split("|")
assert scenario_negators == test_negators, (scenario_negators, test_negators)
print("S480 PASS: scenario and test negator rules agree")
with tempfile.TemporaryDirectory(prefix="s480-") as directory:
    fixture = pathlib.Path(directory)
    for name in ("test/lib.sh", "test/cases/s285_unreleased_408_notes.sh",
                 "lib/git-env.sh", "lib/markdown.sh", "lib/one-definition-lint.py",
                 "CHANGES.md"):
        target = fixture / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / name, target)
    # Read the real tag through git's normal read-only interface; never init or commit.
    git_dir = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "--absolute-git-dir"], text=True).strip()
    (fixture / ".git").write_text("gitdir: " + git_dir + "\n")
    original = (root / "CHANGELOG.md").read_text()
    anchor = "- **Compatibility and limits (#408).**\n"
    assert original.count(anchor) == 1

    failures = []

    def check(label, notes, expected, diagnostic=""):
        (fixture / "CHANGELOG.md").write_text(notes)
        result = subprocess.run(
            ["bash", str(fixture / "test/cases/s285_unreleased_408_notes.sh")],
            capture_output=True, text=True)
        output = result.stdout + result.stderr
        if (result.returncode == 0) != expected or (diagnostic and diagnostic not in output):
            failures.append(label)
            print("S480 FAIL: " + label + "\n" + output)
        else:
            print("S480 PASS: " + label)

    def append(sentence):
        return original.replace("\n## v0.3.0", "  " + sentence + "\n\n## v0.3.0", 1)

    check("unchanged repository passes", original, True)
    for sentence in ("Known: the strict reader is complete.",
                     "The strict reader is complete for another shape.",
                     "The lint is complete and nothing is missing."):
        check(sentence, append(sentence), False, "completeness claim")
    for word in ("not", "no", "never", "cannot", "outside", "neither"):
        check("whole-word negator " + word,
              append("The reader: " + word + " complete."), True)
    for sentence in ("Two answers are new.", "2 questions need confirmation.",
                     "30 questions need confirmation.", "13 answers need confirmation.", "3 answers 2 questions need confirmation."):
        check("later conflicting count: " + sentence, append(sentence), False,
              "answers/questions;")
    check("all matching word and digit counts", append("Three answers and 3 questions."), True)
    for suffix in ("0", "1"):
        check("meaning version 2" + suffix,
              original.replace("meaning version 2 (", "meaning version 2" + suffix + " ("),
              False, "meaning version 2'")
    assert not failures, failures

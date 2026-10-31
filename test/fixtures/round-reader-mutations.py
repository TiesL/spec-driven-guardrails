"""Independent #610 mutations, applied only to temporary copies."""
import pathlib
import shutil
import subprocess
import sys

root, scratch = map(pathlib.Path, sys.argv[1:])
shutil.copytree(root / "lib", scratch / "lib")
target = scratch / "lib/review-rounds.sh"
original = target.read_text()
review = '<!-- model-record: stage=Review model="x" floor-basis="test" -->'
planning = '<!-- model-record: stage=Planning model="x" -->'
done = '<!-- pre-merge-review:done sha=' + 'd' * 40 + ' -->'


def row(day, body):
    return f"2026-10-{day:02}T10:00:00Z\tcomment\t-\t{body}\n"


def run(source, rows, setup=":"):
    target.write_text(source)
    return subprocess.run(["/bin/bash", "-c",
        '. "$1"; ' + setup + '; rr_rounds', "test", str(target)],
        input=rows, text=True, capture_output=True)


def view(p):
    return [tuple(line.split("\t")[:3]) for line in p.stdout.splitlines()]


failures = []


def check(name, source, rows, predicate, setup=":"):
    control = run(original, rows, setup)
    mutant = run(source, rows, setup)
    if not predicate(control):
        failures.append(name + ": control failed: " + repr(control))
    elif predicate(mutant):
        failures.append(name + ": mutant survived")
    else:
        print("    S470/" + name + ": control green; mutant killed")


def replace(old, new, count=1):
    if original.count(old) != count:
        raise AssertionError("mutation anchor changed: " + old)
    return original.replace(old, new)


# Each mutation gets clean source and an exact-output oracle.
rows = row(3, review) + row(1, review)
check("sort", replace('LC_ALL=C sort -t "$tab" -k1,1 -k2,2n -k3,3n', 'cat'),
      rows, lambda p: p.returncode == 0 and view(p) == [
          ("R", "1", "2026-10-01T10:00:00Z"), ("R", "2", "2026-10-03T10:00:00Z")])
rows = row(1, review) + row(2, planning) + row(3, review)
check("Planning-number", replace('if [ "$k4" = R ]; then', 'if [ -n "$k4" ]; then'),
      rows, lambda p: p.returncode == 0 and [x[:2] for x in view(p)] == [
          ("R", "1"), ("P", "1"), ("R", "2")])
# Mutate both redundant checks of the same legacy predicate.
check("SHA-length", replace('{40}', '+', original.count('{40}')),
      row(1, done.replace('d' * 40, 'd' * 39)),
      lambda p: p.returncode == 0 and not p.stdout)
check("delimiter", replace('[[:space:]]*-->', '', original.count('[[:space:]]*-->')),
      row(1, done.removesuffix(' -->')),
      lambda p: p.returncode == 0 and not p.stdout)
check("live-body", replace('<<<"$live"', '<<<"$text"', original.count('<<<"$live"')),
      row(1, chr(96) + done + chr(96)), lambda p: p.returncode == 0 and not p.stdout)
start = original.index('        live="$(live_text')
end = original.index('        # grep -c', start)
check("live-capture-guard", original[:start] + '        live="$(live_text "$text")"\n' + original[end:],
      row(1, "plain prose"), lambda p: p.returncode != 0 and not p.stdout and bool(p.stderr),
      'live_text() { exit 0; }')
start = original.index('        case "$hit" in')
end = original.index('        if [ "$rc" -ge 2 ]', start)
check("numeric-count-guard", original[:start] + original[end:],
      row(1, done), lambda p: p.returncode != 0 and not p.stdout and bool(p.stderr),
      """grep() { case "$*" in *pre-merge-review:done*) return 0 ;; *) command grep "$@" ;; esac; }""")
if 'LC_ALL=C grep -aqE' in original:
    failures.append("redundancy: numeric count still cross-checked by plain grep")
for failure in failures:
    print("    FAIL: S470/" + failure, file=sys.stderr)
sys.exit(bool(failures))

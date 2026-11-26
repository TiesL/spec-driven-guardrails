"""#706 loaded-text seam. This never authorizes a push or claims live obedience.

Each independently stated obligation has positive and single-obligation deletion
controls; checks read only the scope that owns that obligation, not PRD/A64.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
POLICY = 'policy/WORKFLOW.md'
ROLES = 'skills/role-contracts/SKILL.md'
ORCH = 'skills/role-contracts/ORCHESTRATOR.md'
# scenario, label, source, scope, expression, independent compliant witness
ROWS = [
(720, 'shared-wip', POLICY, '', r'all.*roles.*(one|shared).*wip/<issue>.*same.named remote', 'All roles use one shared wip/<issue>-<slug> branch and its same-named remote.'),
(720, 'pr-target', POLICY, '', r'(publication|PR) branch.*feature/.*fix/', 'The PR branch is feature/<issue>-<slug> or fix/<issue>-<slug>.'),
(720, 'explicit-sha', POLICY, '', r'explicit.*fast.forward.*git push origin.*(sha|SHA).*feature/', 'Use an explicit fast-forward push: git push origin <sha>:refs/heads/feature/<issue>-<slug>.'),
(720, 'drafts', POLICY, '', r'(never|no).*PR.*WIP.*draft', 'Never attach a PR to WIP, including a draft.'),
(720, 'checkout-bypass', POLICY, '', r'never check out.*PR branch.*gh pr checkout', 'Never check out the PR branch for work, including gh pr checkout.'),
(720, 'first-promotion', POLICY, '', r'open.*PR.*first promotion.*before Review', 'Open the PR at the first promotion, before Review.'),
(721, 'exact-clean', POLICY, '', r'exact.*(commit|head).*clean working tree', 'Validate the exact committed head with a clean working tree.'),
(721, 'no-tests', POLICY, '', r'\./check --no-tests.*(exit 0|pass|succeed)', './check --no-tests must exit 0.'),
(721, 'affected-cases', POLICY, '', r'every affected.*\./test/run.sh.*(brief|OR48).*exit 0', 'Every affected ./test/run.sh <fragment> named by the Developer brief under OR48(2) must exit 0.'),
(721, 'behavior-current', POLICY, '', r'behavior run.*OR48\(1\).*current.*(commit|head)', 'Any behavior run required by OR48(1) must be current for that commit.'),
(721, 'record-evidence', POLICY, '', r'record.*(full )?SHA.*exact commands.*results.*Pipeline log.*PR comment', 'Record the full SHA, exact commands and results in the Pipeline log or a PR comment.'),
(721, 'generated-before-validation', POLICY, '', r'commit generated artifacts.*before.*(final )?validation', 'Commit generated artifacts before final validation.'),
(721, 'later-head', POLICY, '', r'later commit.*(own|new|fresh).*evidence', 'A later commit needs its own evidence.'),
(721, 'partial-work', POLICY, '', r'(partial|failing).*only checkpoint', 'Partial or failing segments only checkpoint.'),
(721, 'doc-only-promotion', POLICY, '', r'doc.only.*(still|also).*D6.*promot', 'A doc-only checkpoint still needs D6 before promotion.'),
(722, 'a11-target', ROLES, 'Shared, across all five roles', r'commit and push per logical step.*shared WIP branch', 'Commit and push per logical step on the shared WIP branch.'),
(722, 'developer-promotion', ROLES, 'Developer', r'Developer promotes.*complet.*segment.*D6', 'The Developer promotes a completed segment only after D6 passes.'),
(722, 'wip-deadline', ROLES, 'Running the pipeline', r'commits on.*WIP.*work.item commits.*deadline', 'Commits on WIP are work-item commits for the first-commit deadline.'),
(722, 'or46-promotion', ORCH, 'OR46', r'promot.*existing.*(green|D6).*PR branch', 'Promote existing already-green D6 commits to the PR branch.'),
(722, 'pr-identity', ORCH, 'OR46', r'(confirm|verify).*remote PR head.*(equal|match).*promoted SHA.*comparison.*Review.*Pipeline log', 'Confirm the remote PR head equals the promoted SHA before comparison, Review and the Pipeline log use that head.'),
(722, 'moved-blocks', ORCH, 'OR46', r'(failed promotion|moved head).*block.*Review', 'A failed promotion or moved head blocks Review.'),
(722, 'or48-promotion', ORCH, 'OR48', r'checkpoint.*D6.*promot', 'Checkpoint checks do not replace D6 validation for promotion.'),
(723, 'base-reconcile', POLICY, '', r'merge.*remote PR.*into WIP.*(revalid|D6).*never force', 'Merge the remote PR head into WIP and revalidate under D6; never force-push.'),
(723, 'confirmed-cleanup', POLICY, '', r'after confirmed.*merge.*(durable reporting|reporting).*delet.*remote WIP', 'After confirmed PR merge and durable reporting, delete the remote WIP ref explicitly.'),
(723, 'active-work', POLICY, '', r'(verify|check).*no later work.*active user', 'First verify it has no later work or active user.'),
(723, 'moved-retain', POLICY, '', r'retain.*(moved|active).*ref', 'Retain and reconcile a moved or active ref.'),
(723, 'squash-not-enough', POLICY, '', r'squash.*ancestry.*(not|never).*safe deletion', 'Squash-merge ancestry alone is not a safe deletion test.'),
(723, 'sessionend-recreation', POLICY, '', r'integration branch.*SessionEnd.*(not|never).*recreate', 'Finish on the integration branch so SessionEnd does not recreate WIP.'),
]


def scoped(text, scope):
    if not scope:
        return text
    if scope.startswith('OR'):
        m = re.search(r'^- '+scope+r'\b.*(?:\n +[^\n]+)*', text, re.M)
    else:
        m = re.search(r'^## '+re.escape(scope)+r'\s*\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    return m.group() if m else ''


def matches(pattern, text):
    return bool(re.search(pattern, re.sub(r'\s+', ' ', text.replace('`', '')), re.I))


def check(number):
    failures = []
    for n, label, path, scope, pattern, witness in ROWS:
        if n != number:
            continue
        peers = [r[5] for r in ROWS if r[0] == n and r[2:4] == (path, scope)]
        complete = '\n'.join(peers)
        assert matches(pattern, witness), 'broken positive: '+label
        assert matches(pattern, complete), 'broken complete: '+label
        assert not matches(pattern, complete.replace(witness, '', 1)), 'obligation deletion escaped: '+label
        assert not matches(pattern, 'Keep unrelated evidence. Continue other work.'), label
        source = scoped((ROOT/path).read_text(), scope)
        if not matches(pattern, source):
            failures.append(f'S{n}/{label}: {path} [{scope or "common rule"}] must say: {witness}')
    for failure in failures:
        print('FAIL: '+failure)
    return bool(failures)


if __name__ == '__main__':
    sys.exit(check(int(sys.argv[1])))

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
(721, 'affected-cases', POLICY, '', r'every affected project check named in the Developer brief under OR48\(2\) must exit 0', 'every affected project check named in the Developer brief under OR48(2) must exit 0.'),
(721, 'behavior-current', POLICY, '', r'behavior run.*OR48\(1\).*current.*(commit|head)', 'Any behavior run required by OR48(1) must be current for that commit.'),
(721, 'record-evidence', POLICY, '', r'record.*(full )?SHA.*exact commands.*results.*Pipeline log.*PR comment', 'Record the full SHA, exact commands and results in the Pipeline log or a PR comment.'),
(721, 'generated-before-validation', POLICY, '', r'commit generated artifacts.*before.*(final )?validation', 'Commit generated artifacts before final validation.'),
(721, 'later-head', POLICY, '', r'later commit.*(own|new|fresh).*evidence', 'A later commit needs its own evidence.'),
(721, 'partial-work', POLICY, '', r'(partial|failing).*only checkpoint', 'Partial or failing segments only checkpoint.'),
(721, 'doc-only-promotion', POLICY, '', r'doc.only.*(still|also).*D6.*promot', 'A doc-only checkpoint still needs D6 before promotion.'),
(722, 'a11-target', ROLES, 'Shared, across all five roles', r'commit and push per logical step.*shared WIP branch', 'Commit and push per logical step on the shared WIP branch.'),
(722, 'developer-promotion', ROLES, 'Developer', r'Developer promotes.*complet.*segment.*D6', 'The Developer promotes a completed segment only after D6 passes.'),
(722, 'wip-deadline', ROLES, 'Running the pipeline', r'commits on.*WIP.*work.item commits.*deadline', 'Commits on WIP are work-item commits for the first-commit deadline.'),
(722, 'or46-promotion', ORCH, 'OR46', r'promot.*existing.*(green|D6).*PR branch', 'Promote existing D6-green commits to the PR branch.'),
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


# Independent duty witnesses, plus literal deletion locations in the sanctioned
# whole lines. These do not learn expectations from the candidate core.
# rule, label, expression, compliant witness, deleted clause
CORE_DUTIES = [
('OR46', 'closed-list', r'closed no.agent list.*never dispatch', 'Closed no-agent list; never dispatch.', 'Closed no-agent list; do yourself, never dispatch: '),
('OR46', 'named-command-output', r'\(a\) run one named repo command, report output', '(a) Run one named repo command, report output.', 'report output'),
('OR46', 'generated-unedited-wip', r'\(b\) commit/push unedited command.generated files on work.item WIP branch', '(b) Commit/push unedited command-generated files on work-item WIP branch.', ('command-generated ', 'unedited ', 'work-item WIP branch')),
('OR46', 'read-only-comparison', r'\(c\) read.only git/gh and QA comparison', '(c) Read-only git/gh and QA comparison.', 'QA comparison'),
('OR46', 'labels-log', r'\(d\) set label, edit Pipeline log', '(d) Set label, edit Pipeline log.', '(d) set label, edit Pipeline log; '),
('OR46', 'existing-green-only', r'\(e\) promote existing D6.green commits to PR branch', '(e) Promote existing D6-green commits to PR branch.', 'existing D6-green '),
('OR46', 'fast-forward-sha', r'explicit fast.forward SHA push, never force', 'Use explicit fast-forward SHA push, never force.', 'never force'),
('OR46', 'clean-committed-head', r'D6: clean exact committed head', 'D6: clean exact committed head.', 'clean exact committed head'),
('OR46', 'no-tests', r'\./check --no.tests.*exit 0', './check --no-tests must exit 0.', './check --no-tests'),
('OR46', 'affected-case-brief', r'every affected check in brief exit 0', 'Every affected check in brief exit 0.', ('every affected check ', 'in brief ', 'exit 0')),
('OR46', 'current-behavior', r'OR48\(1\) behavior evidence current for that commit', 'OR48(1) behavior evidence current for that commit.', 'OR48(1) behavior evidence current for that commit'),
('OR46', 'evidence-identity', r'log full SHA, exact commands/results', 'Log full SHA, exact commands/results.', 'log full SHA, exact commands/results'),
('OR46', 'partial-checkpoints', r'partial/failing work only checkpoints', 'Partial/failing work only checkpoints.', 'Partial/failing work only checkpoints.'),
('OR46', 'remote-identity-order', r'confirm remote PR head equals promoted SHA before comparison', 'Confirm remote PR head equals promoted SHA before comparison.', 'before comparison'),
('OR46', 'shared-review-head', r'comparison/Review brief/Pipeline log use that head', 'Comparison/Review brief/Pipeline log use that head.', 'comparison/Review brief/Pipeline log use that head.'),
('OR46', 'failed-promotion-stop', r'failed promotion/moved head blocks Review', 'Failed promotion/moved head blocks Review.', 'Failed promotion/'),
('OR46', 'moved-head-stop', r'moved head blocks Review', 'Moved head blocks Review.', 'moved head '),
('OR46', 'owner-hand-edits', r'all else: dispatch owner, including hand edits/repairs', 'All else: dispatch owner, including hand edits/repairs.', 'including hand edits/repairs'),
('OR46', 'failed-command-no-repair', r'report failed commands, never repair', 'Report failed commands, never repair.', 'Report failed commands, never repair.'),
('OR46', 'valid-test-waiver-only', r'only a valid skip=Test record \(OR34\) grants this exception', 'Only a valid skip=Test record (OR34) grants this exception.', ('Only ', 'valid ', ' record', ' (OR34)')),
('OR46', 'test-waiver-exemption-objects', r'no QA artifact/comparison/Reviewer approval block', 'No QA artifact/comparison/Reviewer approval block.', ('QA artifact/', 'comparison/', 'Reviewer approval ')),
('OR46', 'waiver-provenance', r'QA provenance: result=not.applicable; skip=<record URL>; head=<SHA>', 'QA provenance: result=not-applicable; skip=<record URL>; head=<SHA>', 'QA provenance: result=not-applicable; skip=<record URL>; head=<SHA>'),
('OR46', 'waiver-no-open-finding', r'QA provenance: result=not.applicable; skip=<record URL>; head=<SHA>; no open finding', 'QA provenance: result=not-applicable; skip=<record URL>; head=<SHA>; no open finding.', '; no open finding.'),
('OR46', 'single-session', r'single.session never exempts', 'Single-session never exempts.', 'Single-session never exempts.'),
('OR46', 'conflict-stop', r'OR19 and the A49 conflict stop still apply', 'OR19 and the A49 conflict stop still apply.', 'OR19 and the A49 conflict stop still apply.'),
('OR46', 'each-round-artifact', r'otherwise before each Review compare applicable QA artifact to that head', 'Otherwise before each Review compare applicable QA artifact to that head.', 'before each Review '),
('OR46', 'comparison-log', r'log invocation/identities/hashes/result', 'Log invocation/identities/hashes/result.', 'log invocation/identities/hashes/result'),
('OR46', 'missing-evidence-stop', r'missing reference/unusable evidence: block Review, dispatch QA', 'Missing reference/unusable evidence: block Review, dispatch QA.', 'block Review, dispatch QA'),
('OR46', 'per-hunk-route', r'any diff: block Review, disclose each hunk as finding, follow OR17', 'Any diff: block Review, disclose each hunk as finding, follow OR17.', 'disclose each hunk as finding'),
('OR46', 'superseding-artifact', r'owner.resolved unauthorized scenario diff: dispatch QA for new artifact explicitly superseding prior', 'Owner-resolved unauthorized scenario diff: dispatch QA for new artifact explicitly superseding prior.', 'explicitly superseding prior'),
('OR46', 'match-and-no-open-finding', r'Review requires logged match and no open finding', 'Review requires logged match and no open finding.', 'and no open finding'),
('OR46', 'command-result-log', r'each command/result: one Pipeline log line', 'Each command/result: one Pipeline log line.', 'Each command/result: one Pipeline log line'),
('OR48', 'affected-behavior', r'behavior.test run after change: affected scenarios only', 'Behavior-test run after change: affected scenarios only.', 'affected scenarios only'),
('OR48', 'named-stamp-gate', r'unless stamp or gate needs full run; then log names that stamp or gate', 'Unless stamp or gate needs full run; then log names that stamp or gate.', 'then log names that stamp or gate'),
('OR48', 'affected-commit-checks', r'pre.commit checks on work.item branch: only those changed files affect', 'Pre-commit checks on work-item branch: only those changed files affect.', 'only those changed files affect'),
('OR48', 'doc-hooks-only', r'doc.only = pre.commit hooks only', 'Doc-only = pre-commit hooks only.', 'doc-only = pre-commit hooks only'),
('OR48', 'full-check-limit', r'full \./check at most once before PR opens, never per commit', 'Full ./check at most once before PR opens, never per commit.', 'at most once before PR opens, never per commit'),
('OR48', 'brief-no-full-default', r'brief names required checks, never defaults to full suite', 'Brief names required checks, never defaults to full suite.', 'never defaults to full suite'),
('OR48', 'doc-promotion-d6', r'checkpoint checks, including doc.only, never replace D6 for promotion \(OR46\)', 'Checkpoint checks, including doc-only, never replace D6 for promotion (OR46).', 'including doc-only, '),
]


def core_duties(text):
    return [label for rid, label, pattern, _, _ in CORE_DUTIES
            if not matches(pattern, scoped(text, rid))]


def core_duty_controls(lines):
    """Each deletion is caught inside the actual authorized whole-line pair."""
    complete = '\n'.join(lines)
    assert not core_duties(complete), core_duties(complete)
    for rid, label, pattern, witness, cut in CORE_DUTIES:
        assert matches(pattern, witness), 'broken duty witness: '+label
        assert not matches(pattern, 'Keep unrelated evidence.'), label
        line = scoped(complete, rid)
        # Anchor the exemption cuts in its own sentence; 'comparison/' also
        # occurs in the ordinary Review-head duty and cannot select this cut.
        location = ('No QA artifact/comparison/Reviewer approval block'
                    if label == 'test-waiver-exemption-objects' else line)
        assert line.count(location) == 1, 'duty cut scope not unique: '+label
        for clause in (cut if isinstance(cut, tuple) else (cut,)):
            assert location.count(clause) == 1, 'duty cut not unique: '+label+' '+clause
            changed = line.replace(location, location.replace(clause, '', 1), 1)
            mutant = complete.replace(line, changed, 1)
            assert label in core_duties(mutant), 'whole-line duty deletion escaped: '+label+' '+clause
            print('KILLED: core-duty/'+label+' delete '+repr(clause))
    print('CONTROL: A64 whole-line duty witnesses/deletions PASS ('+str(len(CORE_DUTIES))+')')


# Independent literal A64 addendum 3 witnesses at each delivered hint site.
# Each scope is checked separately; a correct hint elsewhere cannot mask it.
HINT_SITES = [(720,
  'commit-on-main',
  'hooks/rules.sh',
  '^REASON_COMMIT_ON_MAIN="[^"]*"',
  'REASON_COMMIT_ON_MAIN="main gets its changes via a PR. Create the issue first, then work on '
  'WIP:\n'
  '\n'
  '         git checkout -b wip/<issue>-<name>\n'
  '\n'
  '       Your changes come along unchanged.\n'
  '       Commit and checkpoint WIP; promote only after validation."',
  'REASON_COMMIT_ON_MAIN="main gets its changes via a PR. Make a branch first — your\n'
  '       changes come along unchanged, nothing gets lost:\n'
  '\n'
  '         git checkout -b feature/<issue>-<name>\n'
  '\n'
  '       Then commit and push as usual."'),
 (720,
  'startup',
  'pending-changes.sh',
  '^  echo "You are on main[^\\n]*\\n  echo "[^\\n]*"',
  '  echo "You are on main. Create the issue first, then work on WIP:"\n'
  '  echo "  git checkout -b wip/<issue-number>-<name>"',
  '  echo "You are on main. New work belongs on its own branch:"\n'
  '  echo "  git checkout -b feature/<issue-number>-<name>"'),
 (722,
  'branch-without-issue',
  'hooks/rules.sh',
  '^REASON_BRANCH_NO_ISSUE="[^"]*"',
  'REASON_BRANCH_NO_ISSUE="every feature/fix/wip branch names its issue, e.g.\n'
  '       wip/123-short-desc. Create the issue first (see write-spec), then:\n'
  '\n'
  '         git checkout -b wip/<issue-number>-<short-desc>"',
  'REASON_BRANCH_NO_ISSUE="every feature/fix branch names the issue it implements, e.g.\n'
  '       feature/123-short-desc. Create the issue first (see the write-spec\n'
  '       skill for the epic/work-item templates), then branch from its number:\n'
  '\n'
  '         gh issue create --template work-item.md\n'
  '         git checkout -b feature/<issue-number>-<short-desc>"'),
 (722,
  'write-spec',
  'skills/write-spec/SKILL.md',
  '^2\\. .*?(?=\\n3\\.|\\Z)',
  '2. Work is split from the PRD into GitHub issues: one `Epic` issue for the\n'
  '   whole, `Work item` issues per part to be built (see\n'
  '   `templates/ISSUE_TEMPLATE/`). Create the issue before development.\n'
  '   Work on `wip/<issue-number>-<short-desc>`; reserve `feature/...` and\n'
  '   `fix/...` for validated PR publication. See `WORKFLOW.md`, "Branch strategy".',
  '2. Work is split from the PRD into GitHub issues: one `Epic` issue for the\n'
  '   whole, `Work item` issues per part to be built (see\n'
  '   `templates/ISSUE_TEMPLATE/`). No development starts before its issue\n'
  '   exists — the branch that implements a work item is named\n'
  '   `feature/<issue-number>-<short-desc>` (or `fix/...`), and\n'
  '   `git-guardrails`/the native `pre-commit` hook refuse to create a branch\n'
  '   without that number (see `WORKFLOW.md`, "Branch strategy").')]


def hint_failures(sources, number=None):
    failures = []
    for n, label, path, pattern, witness, _ in HINT_SITES:
        if number is not None and n != number:
            continue
        found = re.findall(pattern, sources.get(path, ''), re.M | re.S)
        if found != [witness]:
            failures.append(f'S{n}/hint/{label}: {path} must deliver its exact WIP-first hint')
    return failures


def hint_controls():
    good = {}
    for _, _, path, _, witness, _ in HINT_SITES:
        good[path] = good.get(path, '') + witness + '\n'
    good['skills/write-spec/SKILL.md'] += '3. Unrelated guidance.\n'
    assert not hint_failures(good), 'broken independent hint witnesses'
    for n, label, path, _, witness, old in HINT_SITES:
        mutants = [('deletion', ''), ('historical reversion', old)]
        if path != 'skills/write-spec/SKILL.md':
            mutants += [(family+' checkout', witness.replace('checkout -b wip/', 'checkout -b '+family+'/'))
                        for family in ('feature', 'fix')]
        for name, replacement in mutants:
            changed = dict(good)
            assert changed[path].count(witness) == 1, label
            changed[path] = changed[path].replace(witness, replacement, 1)
            assert any('/hint/'+label+':' in failure for failure in hint_failures(changed)), label+' '+name
            print('KILLED: S'+str(n)+'/hint/'+label+'/'+name)
    print('CONTROL: four independent WIP-first hint sites PASS')


def check(number):
    failures = []
    if number in (720, 722):
        hint_controls()
        sources = {path: (ROOT/path).read_text() for _, _, path, _, _, _ in HINT_SITES}
        failures += hint_failures(sources, number)
    for n, label, path, scope, pattern, witness in ROWS:
        if n != number:
            continue
        peers = [r[5] for r in ROWS if r[0] == n and r[2:4] == (path, scope)]
        complete = '\n'.join(peers)
        assert matches(pattern, witness), 'broken positive: '+label
        assert matches(pattern, complete), 'broken complete: '+label
        assert not matches(pattern, complete.replace(witness, '', 1)), 'obligation deletion escaped: '+label
        assert not matches(pattern, 'Keep unrelated evidence. Continue other work.'), label
        if (n, label) == (721, 'affected-cases'):
            for clause in ('every affected project check ', 'named in the Developer brief ',
                           'under OR48(2) ', 'exit 0'):
                assert witness.count(clause) == 1, clause
                assert not matches(pattern, witness.replace(clause, '', 1)), clause
                print('KILLED: S721/affected-cases delete '+repr(clause))
        source = scoped((ROOT/path).read_text(), scope)
        if not matches(pattern, source):
            failures.append(f'S{n}/{label}: {path} [{scope or "common rule"}] must say: {witness}')
    if number == 722:
        failures += ['S722/core-duty/'+label for label in core_duties((ROOT/ORCH).read_text())]
    for failure in failures:
        print('FAIL: '+failure)
    return bool(failures)


if __name__ == '__main__':
    sys.exit(check(int(sys.argv[1])))

"""A65 delivered-text checks with independent witnesses and deletion controls.

Read only the owning delivery surfaces; PRD/A65 are not oracle substitutes.
These checks establish instruction presence, not live API/model obedience.
"""
from pathlib import Path
import json
import re
import runpy
import subprocess
import sys

ROOT = Path(sys.argv[1])
GROUP = int(sys.argv[2])
errors = []


def check(label, yes, message):
    if not yes:
        errors.append(f'S{GROUP}/{label} at backlog-724-text.py:{sys._getframe(1).f_lineno}: {message}')


def flat(s):
    return re.sub(r'\s+', ' ', s.replace('`', '')).strip()


def obligation(label, delivered, pattern, witness):
    regex = re.compile(pattern, re.I)
    assert regex.search(flat(witness)), 'QA witness invalid: ' + label
    cut = regex.sub('', flat(witness))
    assert not regex.search(cut), 'QA deletion control survived: ' + label
    found = regex.search(flat(delivered))
    check(label, found, 'delivered obligation absent: ' + pattern)
    if found:
        # Delete all copies of this obligation: text elsewhere cannot supply it.
        assert not regex.search(regex.sub('', flat(delivered))), 'delivered deletion control survived: ' + label


readme = (ROOT / 'README.md').read_text()
build = re.search(r'^## How this repo builds itself\s*\n(.*?)(?=^## |\Z)', readme, re.M | re.S)
m = re.search(r"^### Keeping this repository's backlog current\s*\n(.*?)(?=^#{1,3} |\Z)",
              build[1] if build else '', re.M | re.S)
maintenance = m[1] if m else ''

# Each pair is an independently meaningful requirement from the approved design.
# Bounded patterns allow ordinary prose editing without accepting a bare heading.
ROWS = {
726: [
('body-authority', r'body.{0,100}(authorit|source of truth)', 'Issue-body fields are the authority.'),
('native-mirrors', r'native.{0,80}mirror.{0,80}(settled|decided|body)', 'Native relations mirror settled body declarations.'),
('reciprocal-bodies', r'(both|inverse|reciprocal).{0,90}(Blocks|dependenc)', 'Keep both dependency ends consistent.'),
('remove-obsolete', r'remov.{0,100}(obsolete|old|stale).{0,100}(edge|parent|block)', 'Remove obsolete edges and old parents.'),
('read-before-after', r'read.{0,70}(current|before).{0,150}(read.back|re.read|verify)', 'Read current data before applying settled changes, then read back and verify.'),
('membership-first', r'(confirm|verify|check).{0,80}(auto.add|automatic membership).{0,100}(before|then).{0,70}add', 'Confirm automatic membership before attempting an add.'),
('no-id-confusion', r'(numeric|REST).{0,60}(ID|identifier).{0,100}(number|node|project.item)', 'Use REST numeric IDs, distinct from issue numbers, node IDs and project-item IDs.'),
('SDG-labels', r'type.{0,30}status.{0,30}(active.role|role).{0,50}label|label.{0,50}type.{0,30}status.{0,30}(active.role|role)', 'Maintain type/status/active-role labels.'),
('owner-authored', r'Product.{0,70}(author|reconcil).{0,100}bod', 'Product authors reconciled bodies.'),
('unchanged-publication', r'orchestrator.{0,70}(publish|post).{0,90}unchanged', 'The orchestrator publishes owner content unchanged.'),
('body-file', r'(body.file|--body-file)', 'Publish using --body-file.'),
('epic-parent', r'(nested.{0,50}parent.{0,90}top.level|top.level.{0,50}(none|no parent))', 'Nested epics name a parent; top-level epics have none.'),
('covers-empty', r'Covers', 'Keep realized Covers.'),
('explicit-none', r'(none.{0,60}empty|empty.{0,60}none)', 'Write none for empty dependencies.'),
('inactive-no-role', r'inactive.{0,80}(no|not|never).{0,40}(invent|active role)', 'Inactive items need no invented active role.'),
],
727: [
('board-order-authority', r'board.{0,80}(rank|order).{0,80}authorit', 'Board Backlog rank and Horizon are authoritative for order.'),
('confirmed-only', r'(apply|write).{0,35}only.{0,90}(confirmed|decided).{0,60}(order|rank|horizon|value)', 'Apply only confirmed order and Horizon values.'),
('inheritance', r'(child|children).{0,60}rank.{0,50}inherit', 'Child rank follows inheritance from its epic.'),
('epic-order', r'epic.{0,45}order', 'Retain epic ordering.'),
('per-field-note', r'(each|per).{0,40}(empty|missing).{0,50}field.{0,100}(reason|note)', 'Each empty field needs a note naming its reason.'),
('unapplied-proposal', r'proposal.{0,80}(unapplied|not appl|until.{0,30}confirm)', 'Proposals remain unapplied until confirmed.'),
('awaiting-maintainer', r'awaiting.maintainer', 'Use disposition awaiting-maintainer.'),
('parking-evidence', r'park.{0,100}(document|decision|reference)', 'Parked fields cite a documented decision reference.'),
('field-independence', r'(one|rank).{0,75}(not|cannot).{0,65}(other|Horizon)', 'One documented field cannot excuse the other missing Horizon.'),
],
728: [
('on-request', r'(on.request|on request)', 'Run the drift report on request.'),
('read-only', r'backlog-drift.sh.{0,90}read.only', 'backlog-drift.sh is a read-only report.'),
('finding-evidence', r'(observed|actual).{0,80}expected.{0,100}(link|URL|evidence)', 'Report observed and expected values with evidence URLs.'),
],
729: [
('failed-response', r'(non.success|fail).{0,70}(gh|response|operation).{0,120}(human|report)|gh.{0,60}(fail|non.success).{0,120}(human|report)', 'Any non-success gh response is reported to the human.'),
('skip-issue', r'skip.{0,60}(issue|remaining check)', 'Skip the affected issue remaining checks.'),
('desired-state', r'(retain|record|preserve).{0,60}desired.{0,20}state', 'Record desired state.'),
('stop-dependent', r'(stop|no).{0,50}dependent.{0,30}(write|operation)', 'Stop dependent writes.'),
('partial-operation-log', r'(log|record).{0,80}(completed|successful).{0,80}(failed|unfinished|unchecked)', 'Record completed, failed and unchecked operations.'),
('no-partial-success', r'(never|not).{0,60}(partial|incomplete).{0,70}(synchron|complete|success)|partial.{0,80}(never|not).{0,60}(synchron|complete|success)', 'Never call a partial sequence synchronized.'),
('no-guess-repair', r'(no|never).{0,50}(guess|invent).{0,70}(repair|rollback|state)', 'Never guess a repair or rollback state.'),
],
730: [
('actual-pr-linkage', r'verify.{0,100}(actual.{0,20})?PR link', 'Verify actual PR linkage.'),
('verified-membership', r'verify.{0,100}membership', 'Verify issue membership.'),
('epic-closure', r'epic.{0,60}(closure|clos).{0,30}rule', 'Keep epic closure rules.'),
('existing-automation-first', r'(existing|enabled).{0,60}(workflow|automation).{0,80}(first|before)', 'Use existing workflows first before manual corrections.'),
('closure-readback', r'verify.{0,70}(CLOSED|issue state).{0,80}(Done|board)', 'Verify CLOSED and board Done through fresh reads.'),
('release-not-closure', r'(release|release/).{0,100}(not|never|doesn.t|insufficient).{0,60}(clos|complet)', 'A release merge does not establish closure.'),
('explicit-close', r'(explicitly|explicit).{0,50}(clos|gh issue close)', 'Explicitly gh issue close the release child.'),
('record-pr-link', r'(record|link).{0,70}(completion|PR link|pull request)', 'Record child completion and the PR link.'),
('no-duplicate-automation', r'(no|never|do not).{0,50}(duplicate|new|add).{0,50}(automation|workflow)', 'Do not add duplicate automation.'),
],
731: [
('local-scope', r'TiesL/spec-driven-guardrails.{0,100}(Project 1|TiesL.{0,20}1)', 'TiesL/spec-driven-guardrails uses TiesL Project 1.'),
('lifecycle-backlog', r'Backlog.{0,40}Backlog', 'Backlog → Backlog'),
('lifecycle-active', r'Discovery.{0,40}Planning.{0,40}Test.{0,40}Implementation.{0,60}In progress', 'Discovery/Planning/Test/Implementation → In progress'),
('lifecycle-review', r'Review.{0,40}In review', 'Review → In review'),
('lifecycle-closed', r'CLOSED.{0,40}Done', 'Verified CLOSED → Done'),
('ready-decided', r'Ready.{0,80}(explicit|confirmed).{0,40}maintainer', 'Ready requires an explicit maintainer decision.'),
('blocked-stage', r'[Bb]locked.{0,90}(retain|keep).{0,50}(stage|Status)', 'Blocked work retains its stage Status.'),
('blocked-reason', r'[Bb]locked.{0,100}(visible.{0,30}reason|reason.{0,30}visible)', 'Blocked work has a visible blocked reason.'),
('indeterminate', r'(indeterminate|unknown).{0,70}lifecycle.{0,70}(cannot|not|never).{0,50}(agreement|clean)', 'Indeterminate lifecycle cannot establish agreement.'),
]}
for label, pattern, witness in ROWS[GROUP]:
    obligation(label, maintenance, pattern, witness)

if GROUP == 731:
    # These files must exactly regain the release base; no adopter payload.
    base = 'origin/release/742-process-hygiene'
    restored = (
        'skills/write-spec/SKILL.md',
        'templates/ISSUE_TEMPLATE/epic.md', 'templates/ISSUE_TEMPLATE/work-item.md',
        '.github/ISSUE_TEMPLATE/epic.md', '.github/ISSUE_TEMPLATE/work-item.md',
        'CHANGES.md', 'test/fixtures/baseline/CHANGES.md.snapshot',
        'test/cases/s336_changes_advance_merge_approval.sh',
        'policy/WORKFLOW.md', 'adapters/codex/AGENTS.md', 'WORKFLOW.md', 'AGENTS.md')
    for path in restored:
        expected = subprocess.check_output(['git', '-C', str(ROOT), 'show', base + ':' + path])
        actual = (ROOT / path).read_bytes()
        accepts = lambda data: data == expected
        assert accepts(expected) and not accepts(expected + b'\n'), 'restoration control'
        check('release-base/' + path, accepts(actual), 'not restored byte-for-byte to ' + base)

    a = runpy.run_path(str(ROOT / 'test/fixtures/wip-706-substitutions.py'))
    path = 'skills/role-contracts/ORCHESTRATOR.md'
    amendments = json.loads((ROOT / 'test/fixtures/backlog-724-substitutions.json').read_text())
    assert amendments['base'] == 'c3ef74ed2dde48fc05dc39a5a7cd9d8e9cebf032'
    # The #724 base must survive the squash of PR #747 into the release branch
    # (the #706/97a3a61 defect fixed in #750): an ancestor of both HEAD and the
    # release branch, never a WIP-only commit such as 626c753.
    for ref in ('HEAD', base):
        reachable = subprocess.run(['git', '-C', str(ROOT), 'merge-base', '--is-ancestor', amendments['base'], ref],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        check('D4-base-reachable/' + ref, reachable, amendments['base'] + ' is not an ancestor of ' + ref + ' (unreachable after squash)')
    before = subprocess.check_output(['git', '-C', str(ROOT), 'show', amendments['base'] + ':' + path])
    old = b'(d) set label, edit Pipeline log;'
    new = b'(d) labels/log; mirror decided metadata;'
    old2 = b'Failed promotion/moved head blocks Review.'
    new2 = b'Failed promotion/moved head blocks Review; head moved at Review start: stop.'
    assert before.count(old) == 1 and before.count(old2) == 1
    expected = before.replace(old, new, 1).replace(old2, new2, 1)
    actual = (ROOT / path).read_bytes()
    check('D4-exact-pair', actual == expected, 'only the sanctioned OR46(d) and OR46 moved-head pairs may change the base core')
    assert amendments['changes'][path] == [[old.decode(), new.decode()], [old2.decode(), new2.decode()]], 'D4 literal allowance widened'
    assert set(amendments['changes']) == {path, 'skills/role-contracts/orchestrator-rules.tsv', 'test/behavior/orchestrator-scenarios.md'}
    # #706's source pairs stay as at the #724 base; its base pin and provenance
    # may be repinned (#750 moved 97a3a61 to 255040e).
    preserved_706 = json.loads(subprocess.check_output(['git', '-C', str(ROOT), 'show', amendments['base'] + ':test/fixtures/wip-706-substitutions.json']))['changes']
    current_706 = json.loads((ROOT / 'test/fixtures/wip-706-substitutions.json').read_text())['changes']
    widened = json.loads(json.dumps(preserved_706)); widened[path][0][1] += ' '
    assert widened != preserved_706 and {k: v for k, v in preserved_706.items() if k != path} != preserved_706, '#706 pair control'
    assert current_706 == preserved_706, '#706 source pairs changed'
    for label, mutant in [('omitted', before), ('extra-byte', expected+b'\n'), ('undecided', expected.replace(b'mirror decided metadata', b'mirror any metadata')),
                          ('repair', expected.replace(b'never repair', b'repair')), ('old-line', before.replace(old, new, 1)),
                          ('variant', expected.replace(b'start: stop.', b'start: stop')), ('unscoped', expected.replace(b'; head moved at Review start: stop', b'; head moved: stop'))]:
        assert mutant != expected, 'D4 control survived: ' + label
    old_table = json.loads((ROOT / 'test/fixtures/wip-706-substitutions.json').read_text())
    historical = subprocess.check_output(['git', '-C', str(ROOT), 'show', old_table['base'] + ':' + path])
    reconstructed = a['controls'](path, historical)
    assert reconstructed == expected, 'freeze allowance did not reconstruct exact D4 pair'
    # Inventory is Developer-owned; QA tests its reciprocal OB edges here.
    rows = {c[0]: c for line in (ROOT / 'skills/role-contracts/orchestrator-rules.tsv').read_text().splitlines() if len(c := line.split('\t')) == 5}
    for n in (92, 93, 94, 95, 97):
        check('OB' + str(n) + '/inventory', 'OB' + str(n) in rows['OR46'][4].split(','), 'OR46 covered_by is missing retained behavior')
    check('OB96/retired-inventory', 'OB96' not in rows['OR46'][4].split(','), 'retired board-less OB96 remains in inventory')
    check('OB94/OR4-inventory', 'OB94' in rows['OR4'][4].split(','), 'authored body scenario needs reciprocal OR4 coverage')
    parser = runpy.run_path(str(ROOT / 'test/behavior/orchestrator_diff.py'))
    scenarios, intended, schema_errors = parser['parse_scenarios']((ROOT / 'test/behavior/orchestrator-scenarios.md').read_text())
    check('behavior-schema', not schema_errors, str(schema_errors))
    by_id = {s['id']: s for s in scenarios}
    check('OB96/retired-scenario', 'OB96' not in by_id and 'OB96' not in intended, 'retire OB96 without reusing it')
    for n, action, role in [(92, 'answer_directly', 'none'), (93, 'dispatch', 'Product'), (94, 'dispatch', 'Product'), (95, 'record_decision', 'none'), (97, 'answer_directly', 'none')]:
        ident = 'OB' + str(n)
        check(ident + '/retained', ident in intended and ident in by_id, 'missing intended behavior')
        if ident in by_id:
            check(ident + '/outcome', by_id[ident]['then_fields']['next_action'] == action and by_id[ident]['then_fields']['next_role'] == role, 'retained behavior outcome changed')
    for path in ('skills/role-contracts/orchestrator-rules.tsv', 'test/behavior/orchestrator-scenarios.md'):
        historical = subprocess.check_output(['git', '-C', str(ROOT), 'show', old_table['base'] + ':' + path])
        expected = a['controls'](path, historical)
        check('D4-exact/' + path, (ROOT / path).read_bytes() == expected,
              'only historical #706 pairs plus narrowed #724 pairs are allowed')

for error in errors:
    print('FAIL: ' + error)
sys.exit(bool(errors))

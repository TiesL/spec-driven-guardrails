"""A65 delivered-text checks with independent witnesses and deletion controls.

Read only the owning delivery surfaces; PRD/A65 are not oracle substitutes.
These checks establish instruction presence, not live API/model obedience.
"""
from pathlib import Path
import hashlib
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


skill = (ROOT / 'skills/write-spec/SKILL.md').read_text()
m = re.search(r'^(#{2,4}) Maintaining issue and board metadata\s*\n', skill, re.M)
maintenance = ''
if m:
    remaining = skill[m.end():]
    end = re.search(r'^#{1,' + str(len(m[1])) + r'} ', remaining, re.M)
    maintenance = remaining[:end.start()] if end else remaining

# Each pair is an independently meaningful requirement from the approved design.
# Bounded patterns allow ordinary prose editing without accepting a bare heading.
ROWS = {
726: [
('body-authority', r'body.{0,100}(authorit|source of truth)', 'Issue-body fields are the portable authority.'),
('native-mirrors', r'native.{0,80}mirror.{0,80}(settled|decided|body)', 'Native relations mirror settled body declarations.'),
('reciprocal-bodies', r'(both|inverse|reciprocal).{0,90}(Blocks|dependenc)', 'Keep both dependency ends consistent.'),
('remove-obsolete', r'remov.{0,100}(obsolete|old|stale).{0,100}(edge|parent|block)', 'Remove obsolete edges and old parents.'),
('read-before-after', r'read.{0,70}(current|before).{0,150}(read.back|re.read|verify)', 'Read current data before applying settled changes, then read back and verify.'),
('membership-first', r'(confirm|verify|check).{0,80}(auto.add|automatic membership).{0,100}(before|then).{0,70}add', 'Confirm automatic membership before attempting an add.'),
('no-id-confusion', r'(numeric|REST).{0,60}(ID|identifier).{0,100}(number|node|project.item)', 'Use REST numeric IDs, distinct from issue numbers, node IDs and project-item IDs.'),
('canonical-labels', r'(type|status).{0,80}(active.role|role label)', 'Maintain type/status and the active-role label.'),
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
('partial-operation-log', r'(log|record).{0,80}(completed|successful).{0,80}(failed|unfinished|unchecked)', 'Record completed, failed and unchecked operations.'),
('no-partial-success', r'(never|not).{0,60}(partial|incomplete).{0,70}(synchron|complete|success)|partial.{0,80}(never|not).{0,60}(synchron|complete|success)', 'Never call a partial sequence synchronized.'),
('no-guess-repair', r'(no|never).{0,50}(guess|invent).{0,70}(repair|rollback|state)', 'Never guess a repair or rollback state.'),
],
730: [
('existing-automation-first', r'(existing|enabled).{0,60}(workflow|automation).{0,80}(first|before)', 'Use existing workflows first before manual corrections.'),
('closure-readback', r'verify.{0,70}(CLOSED|issue state).{0,80}(Done|board)', 'Verify CLOSED and board Done through fresh reads.'),
('release-not-closure', r'(release|release/).{0,100}(not|never|doesn.t|insufficient).{0,60}(clos|complet)', 'A release merge does not establish closure.'),
('explicit-close', r'(explicitly|explicit).{0,50}(clos|gh issue close)', 'Explicitly gh issue close the release child.'),
('record-pr-link', r'(record|link).{0,70}(completion|PR link|pull request)', 'Record child completion and the PR link.'),
('no-duplicate-automation', r'(no|never|do not).{0,50}(duplicate|new|add).{0,50}(automation|workflow)', 'Do not add duplicate automation.'),
],
731: [
('boardless-native', r'without.{0,40}board.{0,100}(native|portable)', 'Without a board retain portable bodies and native mirrors.'),
('board-na', r'board.{0,90}(not.applicable|N/A)', 'Board checks are not-applicable when omitted.'),
('denied-incomplete', r'(inaccessible|denied).{0,60}board.{0,80}(incomplete|unchecked)', 'An inaccessible configured board is incomplete.'),
]}
for label, pattern, witness in ROWS[GROUP]:
    obligation(label, maintenance, pattern, witness)

if GROUP == 731:
    statements = {
        'work-item': [
            'Issue-body Epic, Blocked by and Blocks fields are the portable authority; native parent/blocker relations mirror settled body declarations and do not require Projects. Follow write-spec\'s issue and board maintenance rule.',
            'Write none for each empty dependency set.'],
        'epic': [
            "List every child issue and keep this list reciprocal with each child's Epic field, including reparenting and removals.",
            "Issue-body parent and dependency fields are the portable authority; keep both dependency ends consistent and mirror settled relations natively without requiring Projects. Write none for each empty dependency set. Follow write-spec's issue and board maintenance rule.",
            'Only nested epics name a parent; top-level epics have no parent.',
            'Name realized PRD functionality and scenario IDs using the Covers token grammar.']}
    for name, sentences in statements.items():
        for folder in ('templates/ISSUE_TEMPLATE', '.github/ISSUE_TEMPLATE'):
            delivered = (ROOT / folder / (name + '.md')).read_text()
            for i, sentence in enumerate(sentences):
                obligation(f'{folder}/{name}/sentence-{i+1}', delivered, re.escape(flat(sentence)), sentence)
            if name == 'epic':
                obligation(folder + '/epic/parent-field', delivered, r'\*\*Epic:\*\* #', '**Epic:** #')
                obligation(folder + '/epic/covers-field', delivered, r'\*\*Covers:\*\* <F1, S2>', '**Covers:** <F1, S2>')
            else:
                check(folder + '/work-item/no-native-rejection', 'native relations would bind' not in flat(delivered), 'historical rejection must be replaced, not supplemented')
    sentence = "At creation, relationship or stage changes, reprioritization and closure, follow `write-spec`'s issue and board maintenance rule."
    for path in ('policy/WORKFLOW.md', 'WORKFLOW.md', 'AGENTS.md'):
        obligation(path + '/routing', (ROOT / path).read_text(), re.escape(flat(sentence)), sentence)
    # D5 fixes version semantics, not the maintainer-reserved release wording.
    changes = (ROOT / 'CHANGES.md').read_text()
    entry = re.search(r'^## process-issue-tracking\n(.*?)(?=^## |\Z)', changes, re.M | re.S)[1]
    obligation('meaning-v2', entry, r'\*\*Meaning version:\*\* 2\b', '**Meaning version:** 2')
    # Actual offer-version behavior uses pending-changes in the S731 shell.

    a = runpy.run_path(str(ROOT / 'test/fixtures/wip-706-substitutions.py'))
    path = 'skills/role-contracts/ORCHESTRATOR.md'
    before = subprocess.check_output(['git', '-C', str(ROOT), 'show', '626c753e7a725c9057748164c6ffa38da6560290:' + path])
    old = b'(d) set label, edit Pipeline log;'
    new = b'(d) labels/log; mirror decided metadata;'
    assert before.count(old) == 1
    expected = before.replace(old, new, 1)
    actual = (ROOT / path).read_bytes()
    check('D4-exact-pair', actual == expected, 'only the sanctioned OR46(d) pair may change the base core')
    amendments = json.loads((ROOT / 'test/fixtures/backlog-724-substitutions.json').read_text())
    assert amendments['base'] == '626c753e7a725c9057748164c6ffa38da6560290'
    assert amendments['changes'][path] == [[old.decode(), new.decode()]], 'D4 literal allowance widened'
    assert set(amendments['changes']) == {path, 'skills/role-contracts/orchestrator-rules.tsv', 'test/behavior/orchestrator-scenarios.md'}
    preserved_706 = subprocess.check_output(['git', '-C', str(ROOT), 'show', amendments['base'] + ':test/fixtures/wip-706-substitutions.json'])
    assert preserved_706 == (ROOT / 'test/fixtures/wip-706-substitutions.json').read_bytes(), '#706 source pairs changed'
    for label, mutant in [('omitted', before), ('extra-byte', expected+b'\n'), ('undecided', expected.replace(b'mirror decided metadata', b'mirror any metadata')),
                          ('repair', expected.replace(b'never repair', b'repair'))]:
        assert mutant != expected, 'D4 control survived: ' + label
    old_table = json.loads((ROOT / 'test/fixtures/wip-706-substitutions.json').read_text())
    historical = subprocess.check_output(['git', '-C', str(ROOT), 'show', old_table['base'] + ':' + path])
    reconstructed = a['controls'](path, historical)
    assert reconstructed == expected, 'freeze allowance did not reconstruct exact D4 pair'
    # Inventory is Developer-owned; QA tests its reciprocal OB edges here.
    rows = {c[0]: c for line in (ROOT / 'skills/role-contracts/orchestrator-rules.tsv').read_text().splitlines() if len(c := line.split('\t')) == 5}
    for n in range(92, 98):
        check('OB' + str(n) + '/inventory', 'OB' + str(n) in rows['OR46'][4].split(','), 'OR46 covered_by is missing new behavior')
    check('OB94/OR4-inventory', 'OB94' in rows['OR4'][4].split(','), 'authored body scenario needs reciprocal OR4 coverage')
    parser = runpy.run_path(str(ROOT / 'test/behavior/orchestrator_diff.py'))
    scenarios, intended, schema_errors = parser['parse_scenarios']((ROOT / 'test/behavior/orchestrator-scenarios.md').read_text())
    assert not schema_errors, schema_errors  # QA-owned fixture control, not a model run
    by_id = {s['id']: s for s in scenarios}
    for n, action, role in [(92, 'answer_directly', 'none'), (93, 'dispatch', 'Product'), (94, 'dispatch', 'Product'), (95, 'answer_directly', 'none'), (96, 'answer_directly', 'none'), (97, 'answer_directly', 'none')]:
        ident = 'OB' + str(n)
        assert ident in intended and ident in by_id, 'missing intended behavior ' + ident
        assert by_id[ident]['then_fields']['next_action'] == action and by_id[ident]['then_fields']['next_role'] == role, 'QA behavior oracle changed: ' + ident

for error in errors:
    print('FAIL: ' + error)
sys.exit(bool(errors))

"""Mechanical source/inventory seam only; never a panel engine or live behavior proof.
Synthetic index scores below are controlled evidence, not live index observations.
"""
import copy
import hashlib
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
IDENT = int(sys.argv[1])
ERRORS = []
COUNTS = {'positive': 0, 'mutation': 0}

# Each independent normative clause gets a deletion control against actual source.
CLAUSES = {
589: [
    'Only maintainer-approved delegation permits eligible temporary choices under OR43/OR45.',
    'The members are Product, Architect and the orchestrator.',
    'Two agreeing positions out of three settle an eligible temporary outcome; retain dissent.',
    'Missing participants or evidence, or three incompatible positions, leave the panel unresolved.',
    'Post one ordinary comment per decision on the work-item issue where it was made, never only on a PR.',
    'The PR description links to that issue comment.',
    'Unresolved and escalated panels also leave issue records; process decisions belong on the issue driving that process.',
    'Use the literal label temporary, panel decision and a stable decision ID.',
    'Record question, scope/AC and artifact links, three named positions and their evidence/model records, vote including dissent, outcome, rationale, reservation/escalation status and a limit/risk flag.',
    'Use 3-0 or 2-1 only for resolved votes; never invent a vote for an unresolved case.',
    'Link superseded records and their resolutions rather than erasing them.',
    'No override marker is part of the shared record format.',
],
590: [
    'Delegation is an allow-list: every action it does not name stays reserved to the maintainer.',
    'Without evidence of maintainer acceptance of delegation, otherwise eligible proposals remain unresolved or referred.',
    'Eligible: temporary spec-visible choices; policy choices; in-repo README edits through a PR; CHANGELOG Unreleased edits through a PR; docs edits through a PR; meaning-version bumps; closing issues; comments on this repository\'s issues and PRs; labels on this repository\'s issues and PRs; deleting merged branches; merging work-item PRs into release branches.',
    'Existing release-branch authority retains its own conditions and is outside this panel\'s grant.',
    'Eligibility grants no execution outside existing role scopes or permissions.',
    'Reserved examples: merges into main; version bumps; tags; GitHub releases; publication outside this repository; posts on other repositories; repository settings; deleting issues; transferring repository ownership or any novel unlisted action.',
    'Also reserved: pipeline-override markers; disabling guardrails; user config; hook-denied operations; sandbox-denied operations.',
    'A panel cannot overrule a role, waive a contract, retry a denied operation or manufacture human approval; use OR45 pushback and human decision where applicable.',
    'All security trade-offs remain reserved, both 2-1 and 3-0; refer them to the maintainer without unauthorized attempts.',
],
591: [
    'Brief fresh non-inheriting Product and Architect separately with canonical procedure, issue/ACs, ground-truth artifact links and exact question/scope.',
    'Withhold orchestrator reasoning, preferred answer, conversation or pasted issue history, and peer positions until independent returns.',
    'The orchestrator records its own position before reconciling returns.',
    'Apply the recorded work author\'s model floor to all three members, including the orchestrator.',
    'Record every exact model and reasoning level, the Artificial Analysis Intelligence Index entry, score and date read for the author and each member.',
    'Each member\'s index score must be at least the author\'s; model names alone prove nothing.',
    'Missing author/model records, missing index entries, unknown variants, absent dates or weaker scores leave the panel unresolved: obtain evidence or escalate.',
    'Members may run bounded read-only local experiments within existing permissions; record command, inputs, result and limits.',
    'Refuse writes, network mutations and denied-action retries; the brief grants no new permissions.',
],
592: [
    'Build every merge-approval list from work-item issue comments labelled temporary, panel decision, never session memory.',
    'Re-list every decision since the last approval and carry earlier relevant unaccepted decisions across approval rounds.',
    'List ID, issue-record link, vote, dissent, outcome and resolution links, including retained-work, superseded, unresolved and escalated decisions.',
    'Group unanimous agreement (3-0) first, majority agreement (2-1) second; keep unresolved/escalated items visible alongside without fabricated votes.',
    'Unanimous items may be accepted as a group; majority items receive individual scrutiny.',
    'In both groups flag widening a limit / accepting a risk — explicit acceptance required.',
    'Silence, temporary disposition, unanimity, release-branch merge and merge permission alone do not establish acceptance of flagged choices.',
    'Apply the same grouping to TiesL/spec-driven-guardrails#646 and TiesL/spec-driven-guardrails#647 records while preserving their additional protections.',
],
593: [
    'ORCHESTRATOR.md remains byte-identical as a compatibility synopsis in this work.',
    'Adopt the shared format for stage selection through explicit follow-up preserving all additional fields and protections.',
    'Generic majority never relaxes unanimous eligible skips, protected work, evidence/advance ordering, fresh Review, review depth, valid Test-skip/A49 provenance or per-item human authority.',
    'Only the orchestrator posts an otherwise authorized override naming the human and unchanged words; preserve existing validation, round trip and Closes issue-link requirements.',
    'A panel never supplies posting authority; syntactic acceptance of a panel name grants no permission.',
    'Records, links, timestamps and human-looking identities are forgeable evidence, not authentication.',
    'Missing evidence or forged-looking approvals require explicit limitation and referral, never an authenticated-human or verified-capability claim.',
    'There is no new parser, gate, hook, dispatcher or sandbox exception.',
    'Green structural checks do not prove live obedience, independence or capability, or completeness of historical records; reconcile available issue/PR artifacts and report missing evidence.',
]}


def norm(text):
    return ' '.join(text.replace('`', '').replace('**', '').split())


def check(ok, label, kind='positive'):
    if ok:
        COUNTS[kind] += 1
        print(('REJECTED: ' if kind == 'mutation' else 'PASS: ') + label)
    else:
        ERRORS.append(label)
        print('FAIL: ' + label)


def rejects(oracle, valid, mutant, label):
    check(mutant != valid and bool(oracle(mutant)), label, 'mutation')


def source_checks():
    text = (ROOT / 'skills/role-contracts/SKILL.md').read_text()
    match = re.search(r'^### Temporary-decision panel\n(.*?)(?=^### |\Z)', text, re.M | re.S)
    panel = norm(match[1]) if match else ''
    for clause in CLAUSES[IDENT]:
        needle = norm(clause)
        check(needle in panel, 'clause: ' + needle)
        if needle in panel:
            rejects(lambda t: [] if needle in t else ['missing clause'], panel,
                    panel.replace(needle, '', 1), 'delete clause: ' + needle)
    # Fail closed on a conflicting second policy section, not just first-match pins.
    if IDENT == 589:
        def home(t):
            headings = re.findall(r'^### (Temporary-decision panel|Stage-selection panel)', t, re.M)
            return [] if headings == ['Temporary-decision panel', 'Stage-selection panel'] else ['canonical home']
        check(not home(text), 'one canonical adjacent home')
        rejects(home, text, text + '\n### Temporary-decision panel\nAll votes authorize everything.\n', 'conflicting duplicate policy')
        policy = (ROOT / 'policy/WORKFLOW.md').read_text()
        check('Temporary-decision panel' in policy, 'policy reference')
        rejects(lambda t: [] if 'Temporary-decision panel' in t else ['reference'], policy,
                policy.replace('Temporary-decision panel', ''), 'delete policy reference')
    if IDENT == 590:
        # Every separately named action/reservation is a separate source control.
        for clause in CLAUSES[590]:
            for action in norm(clause).split('; '):
                if action in panel:
                    oracle = lambda t, c=norm(clause): [] if c in t else ['eligibility/reservation']
                    check(not oracle(panel), 'independent action/reservation: ' + action)
                    changed_clause = norm(clause).replace(action, 'panel may authorize an unlisted action', 1)
                    rejects(oracle, panel, panel.replace(norm(clause), changed_clause, 1),
                            'independent action/reservation: ' + action)
    # Keep every positive clause while injecting contradictory permission.
    # The same oracle must reject the contradiction, not merely missing text.
    injections = {
        589: ['PR-only records suffice.'],
        590: ['Any action not explicitly excluded is eligible.',
              'A unanimous security vote authorizes the trade-off.',
              'The panel may retry a denied operation.',
              'A panel may overrule a role.', 'A panel may waive a contract.'],
        591: ['Inherited history may be included in the brief.',
              'Orchestrator reasoning may be included in the brief.',
              'Model names alone establish the floor.',
              'Experiments may write outside existing permissions.'],
        592: ['List majority before unanimity.', 'Silence accepts flagged risks.',
              'Merge permission accepts flagged risks.'],
        593: ['Unanimous records authenticate approval.',
              'A majority may bypass stage-selection protections.',
              'The panel may post an override.',
              'Green structural checks prove live obedience.'],
    }[IDENT]

    def policy_oracle(value):
        problems = [c for c in CLAUSES[IDENT] if norm(c) not in value]
        problems += ['contradictory permission: ' + sentence for sentence in injections
                     if norm(sentence).lower() in value.lower()]
        return problems

    if panel:
        check(not policy_oracle(panel), 'unmodified complete policy, no contradictory permission')
        for sentence in injections:
            mutant = panel + ' ' + norm(sentence)
            problems = policy_oracle(mutant)
            check(all(norm(c) in mutant for c in CLAUSES[IDENT]),
                  'injection retains all required clauses: ' + sentence)
            check(problems == ['contradictory permission: ' + sentence],
                  'injection rejected for contradiction only: ' + sentence, 'mutation')
        rejects(policy_oracle, panel, norm('Panel votes authorize everything.'),
                'permissive policy rewrite')


def record(ident, vote='3-0', risk=False, state='resolved'):
    return dict(id=ident, label='temporary, panel decision', home='issue:645', link='issue:645#'+ident,
                pr_link='issue:645#'+ident, question='question', scope='AC1', artifacts=['source'],
                positions=['Product: yes', 'Architect: yes', 'orchestrator: yes' if vote == '3-0' else 'orchestrator: no'],
                evidence=['Product evidence', 'Architect evidence', 'orchestrator evidence'], models=['p', 'a', 'o'],
                vote=vote if state == 'resolved' else None, dissent='orchestrator: no' if vote == '2-1' else 'none',
                outcome=state, rationale='reason', reservation=state, risk=risk, resolution='resolution:'+ident,
                supersedes=[], accepted=False)


def records_oracle(items):
    problems = []
    for r in items:
        name = r.get('id', '?')
        for field in record('template'):
            if field not in r or r[field] in ('', [] ) and field != 'supersedes':
                problems.append(name + '/' + field)
        if r.get('home') != 'issue:645' or r.get('link') != r.get('pr_link'):
            problems.append(name + '/issue-home link')
        if r.get('outcome') != 'resolved' and r.get('vote') is not None:
            problems.append(name + '/fabricated vote')
    return problems


def inventory_checks():
    items = [record('unanimous'), record('majority', '2-1'), record('unresolved', state='unresolved'),
             record('escalated', state='escalated'), record('process')]
    check(not records_oracle(items), 'complete 3-0/2-1/unresolved/escalated/process records')
    for r in items:
        for field in r:
            mutant = copy.deepcopy(items)
            del mutant[items.index(r)][field]
            rejects(records_oracle, items, mutant, r['id'] + '/delete field ' + field)
        mutant = copy.deepcopy(items)
        mutant[items.index(r)]['home'] = 'PR-only'
        rejects(records_oracle, items, mutant, r['id'] + '/PR-only')
        mutant = copy.deepcopy(items)
        mutant[items.index(r)]['pr_link'] = ''
        rejects(records_oracle, items, mutant, r['id'] + '/missing PR-description link')
    for index in (2, 3):
        mutant = copy.deepcopy(items)
        mutant[index]['vote'] = '2-1'
        rejects(records_oracle, items, mutant, items[index]['id'] + '/invented vote')
    expected = {r['id'] for r in items}
    for r in items:
        mutant = [x for x in items if x != r]
        rejects(lambda rows: list(expected - {x['id'] for x in rows}), items, mutant, r['id'] + '/missing inventory record')


INDEX = {'fixture:index-equal': ('synthetic', 'synthetic-high', 50),
         'fixture:index-higher': ('synthetic', 'synthetic-higher', 60),
         'fixture:index-weaker': ('synthetic', 'synthetic-weaker', 49)}


def floor_oracle(evidence):
    problems = []
    if any(evidence.get(k) for k in ('reasoning', 'preference', 'history', 'peer', 'write', 'retry')):
        problems.append('contaminated brief/unauthorized experiment')
    author = evidence.get('author', {})
    for name in ('author', 'Product', 'Architect', 'orchestrator'):
        model = evidence.get(name, {})
        if any(not model.get(k) for k in ('model', 'variant', 'entry', 'date', 'score')):
            problems.append(name + '/missing index evidence')
        elif INDEX.get(model['entry']) != (model['model'], model['variant'], model['score']):
            problems.append(name + '/unknown or mismatched captured entry')
        elif model['score'] < author.get('score', float('inf')):
            problems.append(name + '/below author')
    return problems


def floor_checks():
    evidence = {name: dict(model='synthetic', variant='synthetic-high' if score == 50 else 'synthetic-higher',
                                 entry='fixture:index-equal' if score == 50 else 'fixture:index-higher',
                                 date='2026-11-05', score=score)
                for name, score in [('author', 50), ('Product', 50), ('Architect', 60), ('orchestrator', 50)]}
    check(not floor_oracle(evidence), 'synthetic equal/higher scores; artifact-only brief; read-only experiment')
    for key in ('reasoning', 'preference', 'history', 'peer', 'write', 'retry'):
        mutant = copy.deepcopy(evidence)
        mutant[key] = True
        rejects(floor_oracle, evidence, mutant, key)
    for name in evidence:
        for field in evidence[name]:
            mutant = copy.deepcopy(evidence)
            del mutant[name][field]
            rejects(floor_oracle, evidence, mutant, name + '/missing ' + field)
        for field in ('model', 'variant', 'entry'):
            mutant = copy.deepcopy(evidence)
            mutant[name][field] = 'unknown'
            rejects(floor_oracle, evidence, mutant, name + '/unknown ' + field)
        if name != 'author':
            mutant = copy.deepcopy(evidence)
            mutant[name].update(score=49, variant='synthetic-weaker', entry='fixture:index-weaker')
            rejects(floor_oracle, evidence, mutant, name + '/weaker floor')


def disclosure_oracle(inventory, request):
    errors = []
    expected = sorted(inventory, key=lambda r: {'3-0': 0, '2-1': 1, None: 2}[r['vote']])
    if request.get('source') != 'issue-comments' or request.get('rows') != expected:
        errors.append('inventory/order/fields')
    if request.get('accepted_without_explicit_words'):
        errors.append('silence/merge permission is not acceptance')
    return errors


def disclosure_checks():
    items = [record('646-unanimous-risk', risk=True), record('647-majority-risk', '2-1', True),
             record('earlier-unaccepted'), record('unresolved', state='unresolved'), record('superseded')]
    items[-1]['supersedes'] = ['old-record']
    for round_no in (1, 2):
        if round_no == 2:
            items.append(record('new-round-two', '2-1'))
            # Supplied explicit human acceptance is inventory evidence, not authentication.
            items[0]['accepted'] = True
        request = dict(source='issue-comments', rows=sorted(copy.deepcopy(items), key=lambda r: {'3-0': 0, '2-1': 1, None: 2}[r['vote']]))
        oracle = lambda req: disclosure_oracle(items, req)
        check(not oracle(request), 'complete approval round ' + str(round_no))
        for i, row in enumerate(request['rows']):
            mutant = copy.deepcopy(request)
            del mutant['rows'][i]
            rejects(oracle, request, mutant, row['id'] + '/drop decision')
            for field in row:
                mutant = copy.deepcopy(request)
                del mutant['rows'][i][field]
                rejects(oracle, request, mutant, row['id'] + '/drop disclosure ' + field)
        for name, mutate in [('reverse groups', lambda m: m['rows'].reverse()),
                             ('session memory', lambda m: m.update(source='session')),
                             ('silence/merge acceptance', lambda m: m.update(accepted_without_explicit_words=True))]:
            mutant = copy.deepcopy(request)
            mutate(mutant)
            rejects(oracle, request, mutant, name)


def preservation_checks():
    base = '14f062f7678e1ca7850e758e9aceccc6864988e7'
    paths = ['skills/role-contracts/ORCHESTRATOR.md', 'pipeline-override.sh', 'skills/role-contracts/orchestrator-rules.tsv']
    paths += [p.relative_to(ROOT).as_posix() for directory in ('hooks', 'skills/pre-merge-review')
              for p in (ROOT / directory).rglob('*') if p.is_file()]
    for path in paths:
        baseline = subprocess.check_output(['git', 'show', base + ':' + path], cwd=ROOT)
        actual = (ROOT / path).read_bytes()
        digest = hashlib.sha256(baseline).digest()
        oracle = lambda data: [] if hashlib.sha256(data).digest() == digest else [path]
        check(not oracle(baseline), 'preserved assertion green at merge base ' + path)
        check(not oracle(actual), 'unchanged ' + path)
        rejects(oracle, actual, actual + b'\n', 'protected byte ' + path)
    result = subprocess.run([str(ROOT / 'check-workflow-adapters.sh')], cwd=ROOT, capture_output=True, text=True)
    check(result.returncode == 0, 'generated projection equality: ' + result.stdout + result.stderr)
    # Existing generation oracle must reject a real isolated projection edit.
    import tempfile
    import shutil
    with tempfile.TemporaryDirectory(prefix='panel-projection-') as tmp:
        target = Path(tmp) / 'repo'
        shutil.copytree(ROOT, target, ignore=shutil.ignore_patterns('.git', '__pycache__'))
        projection = target / 'AGENTS.md'
        original = projection.read_text()
        projection.write_text(original.replace('Temporary-decision panel', 'Corrupted-panel reference', 1))
        result = subprocess.run([str(target / 'check-workflow-adapters.sh'), str(target)], capture_output=True, text=True)
        check(result.returncode != 0, 'hand-edited projection rejected', 'mutation')


source_checks()
if IDENT == 589:
    inventory_checks()
elif IDENT == 591:
    floor_checks()
elif IDENT == 592:
    disclosure_checks()
elif IDENT == 593:
    preservation_checks()
print(f'S{IDENT}: {COUNTS["positive"]} positive checks, {COUNTS["mutation"]} mutations rejected, {len(ERRORS)} failures; mechanical only; behavior UNRUN')
sys.exit(bool(ERRORS))

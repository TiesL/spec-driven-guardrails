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


# Represented synthetic inputs. These are supplied-evidence checks, not a live
# instruction runner, production parser, authenticated source or execution grant.
MEMBERS = ('Product', 'Architect', 'orchestrator')
FIXTURE_COUNTS = {'positive': 0, 'mutation': 0}
FIXTURE_NAMES = set()


def fixture(name, value, oracle, reason=None):
    if name in FIXTURE_NAMES:
        raise AssertionError('duplicate fixture: ' + name)
    FIXTURE_NAMES.add(name)
    errors = oracle(value)
    kind = 'mutation' if reason else 'positive'
    FIXTURE_COUNTS[kind] += 1
    check(any(reason in e for e in errors) if reason else not errors,
          name + ' diagnostics=' + repr(errors), kind)


def changed(value, change):
    result = copy.deepcopy(value)
    change(result)
    return result


def record(ident, vote='3-0', risk=False, state='resolved'):
    choices = ['adopt', 'adopt', 'defer' if vote == '2-1' else 'adopt']
    return dict(id=ident, label='temporary, panel decision', home='issue:645',
                link='issue:645#' + ident, pr_link='issue:645#' + ident,
                question='Which temporary scope meets AC1?', scope='AC1', artifacts=['skills/role-contracts/SKILL.md'],
                positions=[dict(member=n, position=c) for n, c in zip(MEMBERS, choices)],
                evidence=[dict(member=n, source='artifact:' + n) for n in MEMBERS],
                models=[dict(member=n, model='synthetic', reasoning='high') for n in MEMBERS],
                vote=vote if state == 'resolved' else None,
                dissent='orchestrator: defer' if vote == '2-1' else 'none',
                outcome=state, rationale='bounded temporary scope', reservation='maintainer acceptance pending',
                risk=risk, resolution='resolution:' + ident, supersedes=[], accepted=False)


def record_inventory():
    items = [record('unanimous'), record('majority', '2-1'), record('unresolved', state='unresolved'),
             record('escalated', state='escalated'), record('process'), record('supersession')]
    items[-1]['supersedes'] = ['unanimous']
    items[4].update(question='Which temporary panel procedure applies?', scope='process AC1')
    return items


def inventory_checks():
    items = record_inventory()
    expected = {r['id'] for r in items}
    oracle = lambda rows: records_oracle(rows, expected, {'supersession': 'unanimous'})
    for r in items:
        rows = [items[0], r] if r['supersedes'] else [r]
        fixture('589-valid-' + r['id'], rows, records_oracle)
    fixture('589-complete-inventory', items, oracle)
    r = record('incompatible', state='unresolved')
    for p, choice in zip(r['positions'], ('adopt', 'defer', 'reject')):
        p['position'] = choice
    fixture('589-valid-three-incompatible-unresolved', [r], records_oracle)
    fixture('589-three-incompatible-resolved', changed([r], lambda m: m[0].update(outcome='resolved', vote='2-1')),
            records_oracle, 'outcome')
    for field, contribution in [('positions', 'position'), ('evidence', 'evidence'), ('models', 'model')]:
        for member in MEMBERS:
            m = copy.deepcopy(items)
            m[0][field] = [x for x in m[0][field] if x['member'] != member]
            fixture('589-resolved-missing-' + contribution + '-' + member, m, oracle, member + '/' + contribution)
    fixture('589-resolved-duplicate-participant', changed(items, lambda m: m[0]['positions'][1].update(member='Product')),
            oracle, 'duplicate participant')
    for label, value in [('ordinary-note', 'ordinary note'), ('empty', '')]:
        fixture('589-label-' + label, changed(items, lambda m: m[0].update(label=value)), oracle, 'label')
    for name, value in [('9-0', '9-0'), ('absent-resolved', None), ('disagrees-with-positions', '2-1')]:
        fixture('589-vote-' + name, changed(items, lambda m: m[0].update(vote=value)), oracle, 'vote')
    for index in (2, 3):
        fixture('589-' + items[index]['id'] + '-fabricated-vote',
                changed(items, lambda m: m[index].update(vote='3-0')), oracle, 'fabricated vote')
    for field in record('template'):
        fixture('589-missing-field-' + field, changed(items, lambda m: m[0].pop(field)), oracle, '/' + field)
    for r in items:
        fixture('589-missing-inventory-record-' + r['id'], [x for x in items if x != r], oracle, r['id'] + '/missing inventory')
    for name, change, reason in [
        ('pr-only', lambda m: m[0].update(home='PR:645'), 'issue-home'),
        ('missing-pr-description-link', lambda m: m[0].update(pr_link=''), 'pr_link'),
        ('severed-supersession', lambda m: m[-1].update(supersedes=[]), 'supersession'),
        ('erased-prior-record', lambda m: m.pop(0), 'unanimous/missing inventory')]:
        fixture('589-' + name, changed(items, change), oracle, reason)


ELIGIBLE = ('temporary-spec-choice', 'policy-choice', 'readme-pr', 'changelog-unreleased-pr', 'docs-pr',
            'meaning-version-bump', 'close-issue', 'comment-issue', 'comment-pr', 'label-issue', 'label-pr',
            'delete-merged-branch', 'merge-work-item-to-release')
RESERVED = ('merge-main', 'version-bump', 'tag', 'github-release', 'publish-outside-repository',
            'post-other-repository', 'repository-settings', 'delete-issue', 'transfer-ownership',
            'novel-unlisted-action', 'pipeline-override', 'disable-guardrail', 'user-config',
            'hook-denied-operation', 'sandbox-denied-operation', 'overrule-role', 'waive-contract', 'security-tradeoff')
VOTES = ('3-0', '2-1')


def proposal(action, vote):
    return dict(action=action, panel=[record('proposal', vote)],
                delegation=dict(source='controlled:maintainer-delegation', words='Delegate temporary eligible choices',
                                scope=list(ELIGIBLE)),
                permissions=dict(source='controlled:role-and-sandbox-permissions', role='orchestrator', scope=[action], permitted=[action]),
                release_authority=dict(source='controlled:release-authority', base='release/600-panel',
                                       ci='passed', tests='passed', review='approved'),
                result=dict(disposition='temporary', route='panel', acceptance='pending', attempts=[]),
                prior_denials=[])


def eligibility_checks():
    for action in ELIGIBLE:
        for vote in VOTES:
            p = proposal(action, vote)
            if action == 'merge-work-item-to-release':
                p['result'].update(disposition='authorized-existing-route', route='release-authority')
            name = '590-eligible-' + action + '-' + vote
            fixture(name, p, proposal_oracle)
            fixture(name + '-reject-as-unlisted', changed(p, lambda m: m['result'].update(disposition='rejected-unlisted')),
                    proposal_oracle, 'disposition')
            p['delegation'] = None
            p['result'].update(disposition='referred', route='maintainer')
            name = '590-no-delegation-' + action + '-' + vote
            fixture(name + '-safe', p, proposal_oracle)
            fixture(name, changed(p, lambda m: m['result'].update(disposition='temporary', route='panel')),
                    proposal_oracle, 'delegation')
            fixture(name + '-attempt', changed(p, lambda m: m['result']['attempts'].append(dict(action=action, authority='panel'))),
                    proposal_oracle, 'attempt')
    for action in RESERVED:
        for vote in VOTES:
            p = proposal(action, vote)
            p['result'].update(disposition='referred', route='maintainer')
            if action in ('hook-denied-operation', 'sandbox-denied-operation'):
                p['prior_denials'] = [dict(action=action, result='denied', boundary=action.split('-')[0])]
            name = '590-reserved-' + action + '-' + vote
            fixture(name + '-safe', p, proposal_oracle)
            fixture(name, changed(p, lambda m: m['result'].update(disposition='panel-authorized', route='panel')),
                    proposal_oracle, action + '/referral')
            fixture(name + '-attempt', changed(p, lambda m: m['result']['attempts'].append(dict(action=action, authority='panel'))),
                    proposal_oracle, action + '/attempt')
            if p['prior_denials']:
                fixture(name + '-retry', changed(p, lambda m: m['result']['attempts'].append(dict(action=action, authority='existing-permission'))),
                        proposal_oracle, action + '/denied retry')
    # Existing authority is separate from delegation and has its own prerequisites.
    p = proposal('merge-work-item-to-release', '3-0')
    p['delegation'] = None
    p['result'].update(disposition='authorized-existing-route', route='release-authority')
    p['result']['attempts'] = [dict(action=p['action'], authority='release-authority')]
    fixture('590-existing-release-without-panel-delegation', p, proposal_oracle)
    for field in p['release_authority']:
        fixture('590-release-missing-' + field, changed(p, lambda m: m['release_authority'].pop(field)),
                proposal_oracle, 'release authority')
    for field in ('scope', 'permitted'):
        fixture('590-missing-permission-' + field, changed(proposal('docs-pr', '3-0'), lambda m: m['permissions'].pop(field)),
                proposal_oracle, 'permission')


INDEX = {'fixture:index-equal': ('synthetic', 'synthetic-high', 50),
         'fixture:index-higher': ('synthetic', 'synthetic-higher', 60),
         'fixture:index-weaker': ('synthetic', 'synthetic-weaker', 49)}
CONTAMINATION = {
    'orchestrator-reasoning': 'Orchestrator reasoning: prefer this because it costs less.',
    'preferred-answer': 'Preferred answer: adopt this scope.',
    'conversation-history': 'Conversation history: user and orchestrator agreed to adopt.',
    'pasted-issue-history': 'Pasted issue history: previous comments advocate adoption.',
    'peer-return': 'Peer return: the other member chose adopt.'}


def clean_evidence(higher=False):
    models = {n: dict(model='synthetic', variant='synthetic-higher' if higher and n != 'author' else 'synthetic-high',
                      entry='fixture:index-higher' if higher and n != 'author' else 'fixture:index-equal',
                      date='2026-11-05', score=60 if higher and n != 'author' else 50)
              for n in ('author',) + MEMBERS}
    models.update(briefs=[dict(recipient=n, session='fresh:' + n, inherits=[], at=1,
                              payload=[dict(kind='procedure', text='\n'.join(CLAUSES[591])),
                                       dict(kind='issue/ACs', text='issue:645 AC3'),
                                       dict(kind='artifacts', text='skills/role-contracts/SKILL.md'),
                                       dict(kind='question/scope', text='Can this temporary AC3 choice meet the floor?')])
                         for n in ('Product', 'Architect')],
                  returns=[dict(member=n, session='fresh:' + n, at=2, position='adopt', evidence='artifact:AC3')
                           for n in ('Product', 'Architect')],
                  own_position=dict(member='orchestrator', position='adopt', at=2),
                  reconciliation=dict(at=3, used_sessions=['fresh:Product', 'fresh:Architect'], disposition='settled'),
                  experiments=[dict(command=['cat', 'skills/role-contracts/SKILL.md'],
                                    inputs=['skills/role-contracts/SKILL.md'], result='captured canonical procedure',
                                    limits='local read only; no writes or network',
                                    permissions=['local-read'], prior=[], attempts=[['cat', 'skills/role-contracts/SKILL.md']],
                                    disposition='accepted')])
    return models


def floor_checks():
    e = clean_evidence()
    fixture('591-clean-equal-floor', e, floor_oracle)
    fixture('591-clean-higher-floor', clean_evidence(True), floor_oracle)
    for index, recipient in enumerate(('Product', 'Architect')):
        for contamination, text in CONTAMINATION.items():
            m = copy.deepcopy(e)
            m['briefs'][index]['payload'].append(dict(kind='context', text=text))
            fixture('591-brief-' + recipient + '-' + contamination, m, floor_oracle, recipient + '/' + contamination)
    for name, mutate, reason in [
        ('inherited-dispatch', lambda m: m['briefs'][0].update(inherits=['parent-conversation']), 'inherited'),
        ('missing-orchestrator-position', lambda m: m.pop('own_position'), 'orchestrator position'),
        ('orchestrator-position-after-reconciliation', lambda m: m['own_position'].update(at=4), 'orchestrator position')]:
        fixture('591-' + name, changed(e, mutate), floor_oracle, reason)
    for recipient in ('Product', 'Architect'):
        fixture('591-missing-return-' + recipient,
                changed(e, lambda m: m.update(returns=[r for r in m['returns'] if r['member'] != recipient])),
                floor_oracle, recipient + '/return')
    fields = {'model': 'model', 'reasoning-variant': 'variant', 'index-entry': 'entry', 'score': 'score', 'date': 'date'}
    for subject in ('author',) + MEMBERS:
        for label, field in fields.items():
            fixture('591-missing-' + subject + '-' + label, changed(e, lambda m: m[subject].pop(field)),
                    floor_oracle, subject + '/' + field)
        for label, field, value in [('unknown-model', 'model', 'unknown'), ('unknown-variant', 'variant', 'unknown'),
                                    ('entry-score-mismatch', 'score', 99)]:
            fixture('591-' + label + '-' + subject, changed(e, lambda m: m[subject].update({field: value})),
                    floor_oracle, subject + '/' + field)
    for member in MEMBERS:
        fixture('591-weaker-' + member,
                changed(e, lambda m: m[member].update(score=49, variant='synthetic-weaker', entry='fixture:index-weaker')),
                floor_oracle, member + '/below author')
    fixture('591-model-name-only', changed(e, lambda m: m.update({n: {'model': 'synthetic'} for n in ('author',) + MEMBERS})),
            floor_oracle, 'missing')
    commands = {'local-write': ['touch', '/tmp/panel-write'],
                'network-mutation': ['curl', '-X', 'POST', 'https://example.invalid/decisions'],
                'denied-retry': ['cat', 'private-input']}
    for label, command in commands.items():
        m = copy.deepcopy(e)
        exp = m['experiments'][0]
        exp.update(command=command, inputs=[command[-1]], result='refused; no command executed',
                   disposition='refused', attempts=[])
        if label == 'denied-retry':
            exp['prior'] = [dict(command=command, result='denied', boundary='sandbox')]
        fixture('591-experiment-' + label + '-safe', m, floor_oracle)
        fixture('591-experiment-' + label, changed(m, lambda x: x['experiments'][0]['attempts'].append(command)),
                floor_oracle, label)
    for field in ('command', 'inputs', 'result', 'limits'):
        fixture('591-experiment-missing-' + field, changed(e, lambda m: m['experiments'][0].pop(field)),
                floor_oracle, 'experiment/' + field)
        safe = changed(e, lambda m: m['experiments'][0].pop(field))
        safe['experiments'][0].update(disposition='incomplete', attempts=[])
        safe['reconciliation']['disposition'] = 'unresolved'
        fixture('591-experiment-missing-' + field + '-safe', safe, floor_oracle)


PROTECTIONS = ('unanimous-skip', 'protected-work', 'evidence-before-action', 'advance-ordering',
               'fresh-review', 'review-depth', 'valid-test-skip', 'A49-provenance', 'per-item-human-authority')


PROTECTED_WORK = {
    'unanimous-skip': ('skip Planning', {'votes': ['retain', 'skip', 'skip'], 'required_vote': '3-0'}),
    'protected-work': ('add executable tests and scenario', {'requires': ['Test', 'Implementation']}),
    'evidence-before-action': ('post override', {'evidence_at': 1, 'action_at': 2}),
    'advance-ordering': ('first work-item commit and PR', {'decision_at': 1, 'waiver_at': 2, 'commit_at': 3, 'pr_at': 4}),
    'fresh-review': ('Review round 2', {'reviewer_session': 'fresh:review-2', 'previous_session': 'review-1'}),
    'review-depth': ('review gate', {'required': 'thorough', 'selected': 'thorough'}),
    'valid-test-skip': ('skip Test', {'human_source': 'controlled:human-608', 'scope': 'skip=Test'}),
    'A49-provenance': ('published QA comparison', {'base': 'fixture:base', 'qa': 'fixture:qa', 'comparison': 'match'}),
    'per-item-human-authority': ('out-of-class waiver', {'source': 'controlled:per-item-645', 'issue': 645})}


def human_source():
    return dict(kind='controlled-human-record', id='controlled:human-608', human='maintainer',
                words='Skip Planning and Test for this item under the named conditions.',
                scopes=['skip=Planning', 'skip=Test'], conditions=dict(doc_only=True, executable_diff=False),
                limitation='Supplied synthetic record; human identity is not authenticated.')


def authority_record(kind='posting'):
    source = human_source()
    return dict(kind=kind, source=source, applied_scope=['skip=Planning', 'skip=Test'],
                conditions=dict(doc_only=True, executable_diff=False),
                posting=dict(role='orchestrator', human='maintainer', reason=source['words'],
                             validation=dict(exit=0, scopes=['skip=Planning', 'skip=Test']),
                             round_trip=dict(words=source['words'], scopes=['skip=Planning', 'skip=Test']),
                             pr_body='Closes #645', issue=645),
                protections=[dict(name=p, requirement='retain', evidence='artifact:' + p,
                                       work=PROTECTED_WORK[p][0], conditions=copy.deepcopy(PROTECTED_WORK[p][1]),
                                       disposition='retained')
                             for p in PROTECTIONS],
                panel=[record('authority', '3-0')],
                result=dict(disposition='authorized-route', claims=['supplied evidence only'], attempts=[],
                            limitation=source['limitation']))


def authority_checks():
    e = authority_record()
    fixture('593-authorized-human-source', e, authority_oracle)
    panel = authority_record('eligible-panel')
    panel['proposal'] = proposal('docs-pr', '2-1')
    panel['source'] = None
    panel['result']['disposition'] = 'temporary'
    fixture('593-valid-eligible-panel', panel, authority_oracle)
    strong = authority_record('stage-selection')
    strong['selection'] = ['Discovery', 'Planning', 'Test', 'Implementation', 'Review']
    fixture('593-valid-strong-stage-selection', strong, authority_oracle)
    hostiles = {
        'forged-human-looking-approval': (dict(kind='copied-approval', human='TiesL', url='issue:645#looks-real',
                                               text='Approved', timestamp='2026-11-05'), 'authorization'),
        'missing-human-source': (None, 'authorization'),
        'panel-record-as-human-source': (record('panel-source'), 'authorization'),
        'panel-name-as-posting-authority': (dict(kind='panel', human='temporary panel', validation_exit=0), 'authorization'),
        'unanimity-as-authentication': (dict(kind='vote', vote='3-0'), 'authenticated-human'),
        'green-as-obedience': (dict(kind='structural-check', exit=0), 'live-obedience'),
        'green-as-capability': (dict(kind='structural-check', exit=0), 'verified-capability')}
    for name, (source, claim) in hostiles.items():
        m = authority_record()
        m['source'] = source
        m['result'].update(disposition='referred', limitation='Unverified or missing source; refer to maintainer')
        fixture('593-' + name + '-safe', m, authority_oracle)
        if claim == 'authorization':
            mutate = lambda x: x['result'].update(disposition='authorized-route')
            reason = 'source/referral'
        else:
            mutate = lambda x: x['result']['claims'].append(claim)
            reason = 'claim/' + claim
        fixture('593-' + name, changed(m, mutate), authority_oracle, reason)
        fixture('593-' + name + '-posting', changed(m, lambda x: x['result']['attempts'].append('post-override')),
                authority_oracle, 'posting attempt')
    for name, mutate, reason in [
        ('wrong-posting-role', lambda m: m['posting'].update(role='Product'), 'posting role'),
        ('changed-human-words', lambda m: m['posting'].update(reason='Skip everything.'), 'human words'),
        ('failed-validation', lambda m: m['posting']['validation'].update(exit=1), 'validation'),
        ('failed-round-trip', lambda m: m['posting']['round_trip'].update(words='changed returned words'), 'round trip'),
        ('missing-closes-link', lambda m: m['posting'].update(pr_body='No issue link'), 'Closes')]:
        m = changed(e, mutate)
        fixture('593-' + name, m, authority_oracle, reason)
        m['result'].update(disposition='referred', limitation='Incomplete posting evidence; refer to maintainer')
        fixture('593-' + name + '-safe', m, authority_oracle)
        fixture('593-' + name + '-attempt', changed(m, lambda x: x['result']['attempts'].append('post-override')),
                authority_oracle, 'posting attempt')
    for protection in PROTECTIONS:
        m = authority_record('stage-selection')
        m['selection'] = ['Discovery', 'Planning', 'Test', 'Implementation', 'Review']
        m['source'] = dict(kind='panel', vote='2-1', requested_bypass=protection)
        m['panel'] = [record('bypass', '2-1')]
        m['result'].update(disposition='referred', limitation='Generic majority cannot bypass ' + protection)
        fixture('593-majority-bypasses-' + protection + '-safe', m, authority_oracle)
        index = PROTECTIONS.index(protection)
        fixture('593-majority-bypasses-' + protection,
                changed(m, lambda x: x['protections'][index].update(disposition='bypass-authorized')),
                authority_oracle, protection)
        fixture('593-majority-bypasses-' + protection + '-attempt',
                changed(m, lambda x: x['result']['attempts'].append('bypass:' + protection)),
                authority_oracle, 'bypass attempt')

def records_oracle(items, expected=None, supersessions=None):
    problems = []
    ids = [r.get('id') for r in items]
    if expected is not None:
        problems += [n + '/missing inventory' for n in sorted(expected - set(ids))]
    for successor, prior in (supersessions or {}).items():
        row = next((r for r in items if r.get('id') == successor), {})
        if prior not in row.get('supersedes', []):
            problems.append(successor + '/supersession')
    if len(ids) != len(set(ids)):
        problems.append('duplicate decision ID')
    required = ('id', 'label', 'home', 'link', 'pr_link', 'question', 'scope', 'artifacts', 'positions',
                'evidence', 'models', 'vote', 'dissent', 'outcome', 'rationale', 'reservation', 'risk',
                'resolution', 'supersedes', 'accepted')
    for r in items:
        name = r.get('id', '?')
        for field in required:
            if field not in r or (r[field] in ('', [], None) and field not in ('supersedes', 'vote')):
                problems.append(name + '/' + field)
        if r.get('label') != 'temporary, panel decision':
            problems.append(name + '/label')
        if r.get('home') != 'issue:645' or r.get('link') != 'issue:645#' + name:
            problems.append(name + '/issue-home link')
        if not r.get('pr_link') or r.get('link') != r.get('pr_link'):
            problems.append(name + '/pr_link')
        for field, content, label in [('positions', ('position',), 'position'),
                                      ('evidence', ('source',), 'evidence'),
                                      ('models', ('model', 'reasoning'), 'model')]:
            rows = r.get(field, [])
            names = [row.get('member') for row in rows]
            if len(names) != len(set(names)):
                problems.append(name + '/duplicate participant/' + field)
            if set(names) - set(MEMBERS):
                problems.append(name + '/unknown participant/' + field)
            for member in MEMBERS:
                contributions = [row for row in rows if row.get('member') == member]
                if len(contributions) != 1 or any(not contributions[0].get(c) for c in content):
                    problems.append(name + '/' + member + '/' + label)
        positions = [p.get('position') for p in r.get('positions', [])]
        tally = max((positions.count(p) for p in positions), default=0)
        state, vote = r.get('outcome'), r.get('vote')
        if state not in ('resolved', 'unresolved', 'escalated'):
            problems.append(name + '/outcome')
        if state == 'resolved':
            if len(positions) != 3 or tally < 2:
                problems.append(name + '/outcome/incompatible positions')
            expected_vote = '3-0' if tally == 3 else '2-1'
            if vote not in ('3-0', '2-1') or vote != expected_vote:
                problems.append(name + '/vote')
            if tally == 2:
                dissent = [p['member'] + ': ' + p['position'] for p in r['positions']
                           if positions.count(p['position']) == 1]
                if r.get('dissent') != '; '.join(dissent):
                    problems.append(name + '/dissent')
            elif r.get('dissent') != 'none':
                problems.append(name + '/dissent')
        elif vote is not None:
            problems.append(name + '/fabricated vote')
        for prior in r.get('supersedes', []):
            old = next((x for x in items if x.get('id') == prior), None)
            if old is None or not old.get('resolution') or not r.get('resolution') or prior == name:
                problems.append(name + '/supersession')
    return problems


def proposal_oracle(p):
    action = p['action']
    problems = records_oracle(p.get('panel', []))
    if len(p.get('panel', [])) != 1:
        problems.append(action + '/panel record')
    delegation = p.get('delegation') or {}
    delegated = (delegation.get('source') and delegation.get('words') and action in delegation.get('scope', []))
    permission = p.get('permissions', {})
    permitted = (permission.get('source') and permission.get('role') == 'orchestrator' and action in permission.get('scope', [])
                 and action in permission.get('permitted', []))
    release = p.get('release_authority', {})
    release_ok = (action == 'merge-work-item-to-release' and release.get('source')
                  and release.get('base', '').startswith('release/') and release.get('ci') == 'passed'
                  and release.get('tests') == 'passed' and release.get('review') == 'approved' and permitted)
    result = p['result']
    route = result.get('route')
    eligible = action in ELIGIBLE
    if route == 'release-authority':
        if not release_ok:
            problems.append(action + '/release authority')
        if result.get('disposition') != 'authorized-existing-route':
            problems.append(action + '/disposition')
    elif eligible and delegated and permitted:
        if result.get('disposition') != 'temporary' or route != 'panel':
            problems.append(action + '/disposition')
    elif result.get('disposition') != 'referred' or route != 'maintainer':
        reason = 'referral' if not eligible else 'delegation' if not delegated else 'permission'
        problems.append(action + '/' + reason)
    if not permitted and result.get('disposition') != 'referred':
        problems.append(action + '/permission')
    if result.get('acceptance') != 'pending':
        problems.append(action + '/inferred acceptance')
    for attempt in result.get('attempts', []):
        operation = attempt.get('action')
        if any(d.get('action') == operation and d.get('result') == 'denied' for d in p.get('prior_denials', [])):
            problems.append(action + '/denied retry')
        # The panel result itself never supplies execution permission.
        if not (release_ok and route == 'release-authority' and attempt.get('authority') == 'release-authority'
                and operation == action):
            problems.append(action + '/attempt')
    return problems


def floor_oracle(e):
    problems = []
    for name in ('author',) + MEMBERS:
        model = e.get(name, {})
        for field in ('model', 'variant', 'entry', 'date', 'score'):
            if field not in model or model[field] in ('', None):
                problems.append(name + '/' + field + '/missing')
        entry = INDEX.get(model.get('entry'))
        if entry is None:
            problems.append(name + '/entry/unknown')
        else:
            for field, expected in zip(('model', 'variant', 'score'), entry):
                if model.get(field) != expected:
                    problems.append(name + '/' + field + '/captured entry mismatch')
        if model.get('date') and not re.fullmatch(r'\d{4}-\d{2}-\d{2}', model['date']):
            problems.append(name + '/date')
        if name != 'author' and model.get('score', -1) < e.get('author', {}).get('score', float('inf')):
            problems.append(name + '/below author')
    briefs = e.get('briefs', [])
    returns = e.get('returns', [])
    reconcile = e.get('reconciliation', {})
    sessions = []
    for recipient in ('Product', 'Architect'):
        supplied = [b for b in briefs if b.get('recipient') == recipient]
        if len(supplied) != 1:
            problems.append(recipient + '/brief')
            continue
        brief = supplied[0]
        sessions.append(brief.get('session'))
        if not brief.get('session') or brief.get('inherits') != []:
            problems.append(recipient + '/inherited dispatch')
        payload = brief.get('payload', [])
        for kind in ('procedure', 'issue/ACs', 'artifacts', 'question/scope'):
            if not any(part.get('kind') == kind and part.get('text') for part in payload):
                problems.append(recipient + '/brief/' + kind)
        procedure = ' '.join(p.get('text', '') for p in payload if p.get('kind') == 'procedure')
        if any(norm(c) not in norm(procedure) for c in CLAUSES[591]):
            problems.append(recipient + '/canonical procedure')
        # Inspect supplied payload content, including arbitrary context fields.
        # These controlled contaminants are sentences, not preset contamination flags.
        text = ' '.join(part.get('text', '') for part in payload).lower()
        for label, phrase in [('orchestrator-reasoning', 'orchestrator reasoning:'),
                              ('preferred-answer', 'preferred answer:'),
                              ('conversation-history', 'conversation history:'),
                              ('pasted-issue-history', 'pasted issue history:'), ('peer-return', 'peer return:')]:
            if phrase in text:
                problems.append(recipient + '/' + label)
        supplied_returns = [r for r in returns if r.get('member') == recipient]
        if (len(supplied_returns) != 1 or not supplied_returns[0].get('position')
                or not supplied_returns[0].get('evidence')
                or supplied_returns[0].get('session') != brief.get('session')
                or not brief.get('at', float('inf')) < supplied_returns[0].get('at', -1) < reconcile.get('at', -1)):
            problems.append(recipient + '/return')
    if len(set(sessions)) != 2 or reconcile.get('used_sessions') != sessions:
        problems.append('separate sessions/reconciliation')
    own = e.get('own_position', {})
    if (own.get('member') != 'orchestrator' or not own.get('position')
            or own.get('at', float('inf')) >= reconcile.get('at', -1)):
        problems.append('orchestrator position before reconciliation')
    experiments = e.get('experiments', [])
    if not experiments:
        problems.append('experiment/missing')
    for exp in experiments:
        missing = [f for f in ('command', 'inputs', 'result', 'limits') if not exp.get(f)]
        if missing:
            if (exp.get('disposition') != 'incomplete' or exp.get('attempts')
                    or reconcile.get('disposition') != 'unresolved'):
                problems += ['experiment/' + field for field in missing]
            continue
        command = exp.get('command', [])
        retry = any(p.get('command') == command and p.get('result') == 'denied' for p in exp.get('prior', []))
        operation = command[0] if command else ''
        violation = ('denied-retry' if retry else 'local-write' if operation in ('touch', 'rm', 'tee')
                     else 'network-mutation' if operation in ('curl', 'gh') else None)
        attempts = exp.get('attempts', [])
        if violation:
            if attempts or exp.get('disposition') != 'refused':
                problems.append('experiment/' + violation)
        elif (operation != 'cat' or exp.get('permissions') != ['local-read']
              or exp.get('inputs') != command[1:] or attempts != [command]
              or exp.get('disposition') != 'accepted'):
            problems.append('experiment/permission or capture')
    # Rejected input cannot support a settled reconciliation. Named diagnostics
    # above identify the evidence defect; no fixture flag supplies that verdict.
    return problems


def authority_oracle(e):
    problems = records_oracle(e.get('panel', []))
    source = e.get('source') or {}
    posting = e.get('posting', {})
    result = e['result']
    source_ok = (source.get('kind') == 'controlled-human-record' and source.get('id')
                 and source.get('human') and source.get('words') and source.get('limitation')
                 and e.get('applied_scope') == source.get('scopes')
                 and e.get('conditions') == source.get('conditions'))
    defects = []
    if not source_ok:
        defects.append('source/referral')
    if posting.get('role') != 'orchestrator':
        defects.append('posting role')
    if posting.get('human') != source.get('human') or posting.get('reason') != source.get('words'):
        defects.append('human words')
    validation = posting.get('validation', {})
    if validation.get('exit') != 0 or validation.get('scopes') != e.get('applied_scope'):
        defects.append('validation')
    trip = posting.get('round_trip', {})
    if trip.get('words') != posting.get('reason') or trip.get('scopes') != e.get('applied_scope'):
        defects.append('round trip')
    if not re.search(r'\bCloses #' + str(posting.get('issue', '?')) + r'\b', posting.get('pr_body', '')):
        defects.append('Closes issue link')
    protections = e.get('protections', [])
    for name in PROTECTIONS:
        rows = [p for p in protections if p.get('name') == name]
        if (len(rows) != 1 or not rows[0].get('evidence') or not rows[0].get('work')
                or not rows[0].get('conditions') or rows[0].get('disposition') != 'retained'):
            problems.append('protection/' + name)
    if e.get('kind') == 'stage-selection':
        if e.get('selection') != ['Discovery', 'Planning', 'Test', 'Implementation', 'Review']:
            problems.append('stage-selection/retained stages')
    if e.get('kind') == 'eligible-panel':
        problems += proposal_oracle(e['proposal'])
        if result.get('disposition') != 'temporary':
            problems.append('eligible panel disposition')
        may_post = False
    else:
        may_post = not defects
        if defects and result.get('disposition') != 'referred':
            problems += defects
        if not defects and result.get('disposition') != 'authorized-route':
            problems.append('authorized route disposition')
        if defects and not result.get('limitation'):
            problems.append('missing evidence limitation')
    for claim in result.get('claims', []):
        if claim in ('authenticated-human', 'live-obedience', 'verified-capability'):
            problems.append('claim/' + claim)
    for attempt in result.get('attempts', []):
        if attempt.startswith('bypass:'):
            problems.append('bypass attempt')
        elif attempt != 'post-override' or not may_post:
            problems.append('posting attempt')
    if not result.get('limitation'):
        problems.append('evidence limitation')
    return problems


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
elif IDENT == 590:
    eligibility_checks()
elif IDENT == 591:
    floor_checks()
elif IDENT == 592:
    disclosure_checks()
elif IDENT == 593:
    authority_checks()
    preservation_checks()
print(f'S{IDENT} represented fixtures: {FIXTURE_COUNTS}')
print(f'S{IDENT}: {COUNTS["positive"]} positive checks, {COUNTS["mutation"]} mutations rejected, {len(ERRORS)} failures; mechanical only; behavior UNRUN')
sys.exit(bool(ERRORS))

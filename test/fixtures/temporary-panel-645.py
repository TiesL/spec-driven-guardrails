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
    'Editing the panel\'s own rules is also reserved: any proposal whose target is contract text (by repository path: anything under skills/, policy/, hooks/, settings/, adapters/ and templates/, the generated AGENTS.md and WORKFLOW.md, ORCHESTRATOR.md including OR47, CHANGES.md, USER-CLAUDE.md, and A54 D2) is referred to the maintainer, even when it would otherwise be an eligible docs edit or policy choice.',
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
    for number, clause in enumerate(CLAUSES[IDENT], 1):
        needle = norm(clause)
        check(needle in panel, str(IDENT) + '/source/clause/' + str(number) + '/control')
        if needle in panel:
            rejects(lambda t: [] if needle in t else ['missing clause'], panel,
                    panel.replace(needle, '', 1), str(IDENT) + '/source/clause/' + str(number))
    # Fail closed on a conflicting second policy section, not just first-match pins.
    if IDENT == 589:
        def home(t):
            headings = re.findall(r'^### (Temporary-decision panel|Stage-selection panel)', t, re.M)
            return [] if headings == ['Temporary-decision panel', 'Stage-selection panel'] else ['canonical home']
        check(not home(text), '589/source/canonical-home/control')
        rejects(home, text, text + '\n### Temporary-decision panel\nAll votes authorize everything.\n', '589/source/injection/2')
        policy = (ROOT / 'policy/WORKFLOW.md').read_text()
        check('Temporary-decision panel' in policy, '589/source/policy-reference/control')
        rejects(lambda t: [] if 'Temporary-decision panel' in t else ['reference'], policy,
                policy.replace('Temporary-decision panel', ''), '589/source/policy-reference')
    if IDENT == 590:
        # Every separately named action/reservation is a separate source control.
        action_number = 0
        for clause in CLAUSES[590]:
            for action in norm(clause).split('; '):
                if action in panel:
                    action_number += 1
                    oracle = lambda t, c=norm(clause): [] if c in t else ['eligibility/reservation']
                    check(not oracle(panel), '590/source/action/' + str(action_number))
                    changed_clause = norm(clause).replace(action, 'panel may authorize an unlisted action', 1)
                    rejects(oracle, panel, panel.replace(norm(clause), changed_clause, 1),
                            '590/source/action/' + str(action_number))
    if IDENT == 590:
        # #681: each added entry is its own pin inside the reservation sentence (red when removed, green when restored).
        sentence = re.search(r"Editing the panel's own rules is also reserved:.*?choice\.", panel)
        sentence = sentence[0] if sentence else ''
        for entry in WIDENED:
            oracle = lambda t, e=entry: [] if e in t else ['widened entry']
            check(entry in sentence, '590/source/widened/' + entry + '/control')
            if entry in sentence:
                rejects(oracle, sentence, sentence.replace(entry, '', 1), '590/source/widened/' + entry)
        # #681: exercise S590-target-meaning names the added entries in set one only.
        exercise = (ROOT / 'test/behavior/temporary-panel-scenarios.md').read_text()
        section = re.search(r'^## S590-target-meaning\n(.*?)(?=^## |\Z)', exercise, re.M | re.S)
        section = norm(section[1]) if section else ''
        one = re.search(r'Set one:(.*?)Set two:', section)
        two = re.search(r'Set two:(.*?)Use the actual', section)
        one, two = (one[1] if one else ''), (two[1] if two else '')
        for entry in WIDENED:
            check(entry in one, '590/exercise/set-one/' + entry + '/control')
            check(entry not in two, '590/exercise/set-two/' + entry + '/absent')
        check('templates/' in one and 'script' in one and '.md' in one, '590/exercise/set-one/templates-examples')
        check('UNRUN' in section, '590/exercise/status-unrun')
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
        for number, sentence in enumerate(injections, 1):
            mutant = panel + ' ' + norm(sentence)
            problems = policy_oracle(mutant)
            check(all(norm(c) in mutant for c in CLAUSES[IDENT]),
                  'injection retains all required clauses: ' + sentence)
            check(problems == ['contradictory permission: ' + sentence],
                  str(IDENT) + '/source/injection/' + str(number), 'mutation')
        rejects(policy_oracle, panel, norm('Panel votes authorize everything.'),
                str(IDENT) + '/source/rewrite')


# Closed synthetic vocabulary from qa-manifest-645.md. Text is opaque except
# the finite source pins above and the explicitly captured procedure pin.
MEMBERS = ('Product', 'Architect', 'orchestrator')
STAGES = ('Discovery', 'Planning', 'Test', 'Implementation', 'Review')
ELIGIBLE = ('temporary-spec-choice', 'policy-choice', 'readme-pr', 'changelog-unreleased-pr', 'docs-pr',
            'meaning-version-bump', 'close-issue', 'comment-issue', 'comment-pr', 'label-issue', 'label-pr',
            'delete-merged-branch', 'merge-work-item-to-release')
RESERVED = ('merge-main', 'version-bump', 'tag', 'github-release', 'publish-outside-repository',
            'post-other-repository', 'repository-settings', 'delete-issue', 'transfer-ownership',
            'novel-unlisted-action', 'pipeline-override', 'disable-guardrail', 'user-config',
            'hook-denied-operation', 'sandbox-denied-operation', 'overrule-role', 'waive-contract', 'security-tradeoff',
            'edit-panel-rules')
# Structured proposal target: panel-rules (contract text, by repository path: skills/, policy/, hooks/, settings/, adapters/,
# templates/ (whole directory), generated AGENTS.md and WORKFLOW.md, ORCHESTRATOR.md including OR47, CHANGES.md, USER-CLAUDE.md, A54 D2) makes these eligible tokens the reserved edit-panel-rules token;
# other means everything else, including spec content. The target is a supplied fact; no path or keyword inference.
TARGETS = ('panel-rules', 'other')
TARGETED = ('docs-pr', 'temporary-spec-choice', 'policy-choice')
# #681 widening (maintainer decision 2026-11-08): entries added to the reserved contract-text class.
WIDENED = ('CHANGES.md', 'templates/', 'USER-CLAUDE.md')
# One opaque control label per added entry; templates/ has a script and a .md path. Labels never reach the oracle.
WIDENED_LABELS = ('CHANGES.md', 'templates/check-traceability.sh', 'templates/PRD.md', 'USER-CLAUDE.md')
# Unchanged target-other controls: root spec content stays eligible.
OTHER_LABELS = ('README.md', 'CHANGELOG.md', 'docs/', 'PRD.md', 'ARCHITECTURE.md', 'TEST-SCENARIOS.md')
VOTES = ('3-0', '2-1')
SOURCE_STATES = ('accepted', 'refused', 'unverified', 'missing')
REQUIRED_TAGS = ('procedure', 'issue/ACs', 'artifacts', 'question/scope')
PROHIBITED_TAGS = ('orchestrator-reasoning', 'preferred-answer', 'conversation-history', 'pasted-issue-history', 'peer-return')
PROTECTIONS = ('unanimous-skip', 'protected-work', 'evidence-before-action', 'advance-ordering',
               'fresh-review', 'review-depth', 'valid-test-skip', 'A49-provenance', 'per-item-human-authority')
INDEX = {'fixture:index-equal': ('synthetic', 'synthetic-high', 50),
         'fixture:index-higher': ('synthetic', 'synthetic-higher', 60),
         'fixture:index-weaker': ('synthetic', 'synthetic-weaker', 49)}
FIXTURE_COUNTS = {'positive': 0, 'mutation': 0}
FIXTURE_NAMES = set()


def fixture(name, value, oracle, reason=None):
    if name in FIXTURE_NAMES:
        raise AssertionError('duplicate fixture: ' + name)
    FIXTURE_NAMES.add(name)
    try:
        errors = oracle(value)
        ok = any(reason in e for e in errors) if reason else not errors
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as exc:
        errors, ok = ['CRASH: ' + repr(exc)], False
    kind = 'mutation' if reason else 'positive'
    FIXTURE_COUNTS[kind] += 1
    check(ok, name + ' diagnostics=' + repr(errors), kind)


def changed(value, change):
    result = copy.deepcopy(value)
    change(result)
    return result


def at(value, path):
    for key in path:
        value = value[key]
    return value


def put(value, path, replacement):
    at(value, path[:-1])[path[-1]] = replacement


def negative(name, control, oracle, path, replacement, diagnostic, delete=False):
    """Each contradiction retains its unchanged valid control and named diagnostic."""
    fixture(name + '/control', control, oracle)
    mutant = copy.deepcopy(control)
    if not path:
        mutant = copy.deepcopy(replacement)
    else:
        parent = at(mutant, path[:-1])
        if delete:
            del parent[path[-1]]
        else:
            parent[path[-1]] = replacement
    # Python equates True and 1; their supplied bytes/types still differ.
    check(repr(mutant) != repr(control), name + '/changed-bytes')
    fixture(name, mutant, oracle, diagnostic)
    return mutant


def missing(name, control, oracle, path, diagnostic, opaque=False):
    for label, replacement in [('missing', None), ('empty', '')] + ([('other', 'opaque B')] if opaque else []):
        if label == 'other':
            fixture(name + '/' + label, changed(control, lambda m: put(m, path, replacement)), oracle)
        else:
            negative(name + '/' + label, control, oracle, path, replacement, diagnostic, delete=label == 'missing')


def lists(name, control, oracle, path, diagnostic, identity=None):
    """Independent missing/duplicate/wrong member for each controlled list element."""
    original = at(control, path)
    for i, row in enumerate(original):
        token = str(row.get(identity)) if identity else str(row)
        wrong = copy.deepcopy(row)
        if identity:
            wrong[identity] = 'UNKNOWN'
        else:
            wrong = 'UNKNOWN'
        for label, replacement in [('missing', original[:i] + original[i + 1:]),
                                   ('duplicate', original[:i] + [row] + original[i:]),
                                   ('wrong', original[:i] + [wrong] + original[i + 1:])]:
            negative(name + '/' + token + '/' + label, control, oracle, path, replacement, diagnostic)


def record(ident='A', vote='3-0', risk=False, state='resolved'):
    choices = ['adopt', 'adopt', 'defer' if vote == '2-1' else 'adopt']
    return dict(id=ident, issue='645', label='temporary, panel decision', home='issue:645',
                link='issue:645#' + ident, pr_link='issue:645#' + ident,
                question='opaque A', scope='AC1', artifacts=['artifact:A'],
                positions=[dict(member=n, position=c) for n, c in zip(MEMBERS, choices)],
                evidence=[dict(member=n, source='opaque A') for n in MEMBERS],
                models=[dict(member=n, model='opaque A', reasoning='opaque A') for n in MEMBERS],
                vote=vote if state == 'resolved' else None,
                dissent=[dict(member='orchestrator', position='defer')] if vote == '2-1' else [],
                outcome=state, rationale='opaque A', reservation='pending', risk=risk,
                limit_widening=False, resolution='resolution:' + ident, supersedes=[], accepted=False)


def record_inventory():
    rows = [record('A'), record('B', '2-1'), record('unresolved', state='unresolved'),
            record('escalated', state='escalated'), record('process'), record('supersession')]
    rows[-1]['supersedes'] = ['A']
    rows[4]['scope'] = 'process AC1'
    return rows


def inventory_checks():
    rows = record_inventory()
    oracle = lambda value: records_oracle(value, [r['id'] for r in rows], {'supersession': ['A']})
    fixture('589-record-control', rows, oracle)
    for i, r in enumerate(rows):
        for field in r:
            negative('589/' + r['id'] + '/delete/' + field, rows, oracle, [i, field], None,
                     '/' + field, delete=True)
    for field, label in [('positions', 'position'), ('evidence', 'evidence'), ('models', 'model')]:
        lists('589/contributions/' + field, rows, oracle, [0, field], '/' + label, 'member')
        for i, member in enumerate(MEMBERS):
            for subfield in at(rows, [0, field, i]):
                missing('589/' + member + '/' + field + '/' + subfield, rows, oracle,
                        [0, field, i, subfield], '/' + label,
                        opaque=subfield not in ('member', 'position'))
    for choice in ('adopt', 'defer', 'reject'):
        r = record('choice-' + choice)
        for p in r['positions']:
            p['position'] = choice
        fixture('589/position/' + choice, [r], records_oracle)
    negative('589/position/UNKNOWN', rows, oracle, [0, 'positions', 0, 'position'], 'UNKNOWN', '/position')
    for state in ('resolved', 'unresolved', 'escalated', 'UNKNOWN'):
        r = record('state-' + state, state=state)
        fixture('589/outcome/' + state, [r], records_oracle, '/outcome' if state == 'UNKNOWN' else None)
    incompatible = record('incompatible', state='unresolved')
    for p, choice in zip(incompatible['positions'], ('adopt', 'defer', 'reject')):
        p['position'] = choice
    fixture('589/incompatible-unresolved', [incompatible], records_oracle)
    negative('589/incompatible-resolved', [incompatible], records_oracle, [0, 'outcome'], 'resolved', '/outcome')
    for vote in VOTES:
        r = record('vote-' + vote, vote)
        fixture('589/vote/' + vote, [r], records_oracle)
        for bad in ('UNKNOWN', None, '2-1' if vote == '3-0' else '3-0'):
            negative('589/vote/' + vote + '/' + str(bad), [r], records_oracle, [0, 'vote'], bad, '/vote')
    for state in ('unresolved', 'escalated'):
        for vote in VOTES:
            negative('589/fabricated/' + state + '/' + vote, [record(state, state=state)], records_oracle,
                     [0, 'vote'], vote, '/fabricated-vote')
    majority = [record('majority', '2-1')]
    lists('589/dissent', majority, records_oracle, [0, 'dissent'], '/dissent', 'member')
    negative('589/dissent/wrong-position', majority, records_oracle, [0, 'dissent', 0, 'position'], 'adopt', '/dissent')
    negative('589/dissent/unanimity', [record()], records_oracle, [0, 'dissent'], majority[0]['dissent'], '/dissent')
    for field in ('risk', 'limit_widening', 'accepted'):
        for value in (True, False):
            fixture('589/' + field + '/' + str(value), [changed(record(), lambda r: r.update({field: value}))], records_oracle)
        negative('589/' + field + '/UNKNOWN', rows, oracle, [0, field], 'UNKNOWN', '/' + field)
    for status in ('pending', 'referred', 'none', 'UNKNOWN'):
        fixture('589/reservation/' + status, [changed(record(), lambda r: r.update(reservation=status))],
                records_oracle, '/reservation' if status == 'UNKNOWN' else None)
    for field in ('question', 'scope', 'rationale', 'resolution'):
        missing('589/opaque/' + field, rows, oracle, [0, field], '/' + field, opaque=True)
    negative('589/artifacts/empty', rows, oracle, [0, 'artifacts'], [], '/artifacts')
    for field in ('id', 'issue', 'link', 'pr_link'):
        missing('589/identity/' + field, rows, oracle, [0, field], '/' + field)
        negative('589/identity/' + field + '/B', rows, oracle, [0, field], 'B',
                 '/inventory' if field == 'id' else '/issue-home-link' if field in ('issue', 'link') else '/pr-link')
    for field, value, diag in [('home', 'PR:645', '/issue-home'), ('home', 'UNKNOWN', '/issue-home'),
                               ('label', 'UNKNOWN', '/label'), ('label', '', '/label')]:
        negative('589/' + field + '/' + value, rows, oracle, [0, field], value, diag)
    lists('589/inventory', rows, oracle, [], '/inventory', 'id')
    for ident in ('A', 'B'):
        fixture('589/matching-identity/' + ident, [record(ident)], records_oracle)
    lists('589/supersession', rows, oracle, [5, 'supersedes'], '/supersession')
    negative('589/supersession/self', rows, oracle, [5, 'supersedes'], ['supersession'], '/supersession')
    negative('589/supersession/wrong-existing', rows, oracle, [5, 'supersedes'], ['B'], '/supersession')
    negative('589/supersession/erased-predecessor', rows, oracle, [], rows[1:], '/inventory')


def proposal(action='docs-pr', vote='3-0', target='other'):
    return dict(action=action, target=target, panel=[record('proposal', vote)],
                delegation=dict(state='accepted', source='A', words='opaque A', scope=list(ELIGIBLE)),
                permissions=dict(source='A', role='orchestrator', scope=[action], permitted=[action]),
                release_authority=dict(source=dict(state='accepted', id='A', kind='human', human='maintainer',
                                       action='merge-work-item-to-release', base='release/A', words='opaque A'),
                                       base='release/A', ci='passed', tests='passed', review='approved'),
                result=dict(disposition='temporary', route='panel', acceptance='pending', attempts=[]), prior_denials=[])


def referral(p):
    p['result'].update(disposition='referred', route='maintainer', attempts=[])
    return p


def unsupported_proposal(name, control, path, value, diagnostic, delete=False):
    m = negative(name, control, proposal_oracle, path, value, diagnostic, delete)
    malformed = ((value == 'UNKNOWN' and path[-1] in ('state', 'role', 'ci', 'tests', 'review'))
                 or (path[-1] == 'state' and value == '' and not delete) or path == ['target'])
    fixture(name + '/safe-referral', referral(copy.deepcopy(m)), proposal_oracle, diagnostic if malformed else None)


def eligibility_checks():
    fixture('590-panel-control', proposal(), proposal_oracle)
    for action in ELIGIBLE + RESERVED + ('UNKNOWN',):
        for vote in VOTES:
            p = proposal(action, vote)
            name = '590/action-vote/' + action + '/' + vote
            if action in ELIGIBLE:
                fixture(name, p, proposal_oracle)
                negative(name + '/bad-disposition', p, proposal_oracle, ['result', 'disposition'], 'UNKNOWN', '/disposition')
                negative(name + '/panel-attempt', p, proposal_oracle, ['result', 'attempts'],
                         [dict(action=action, authority='panel')], '/attempt')
            else:
                referral(p)
                fixture(name + '/safe', p, proposal_oracle)
                negative(name + '/settlement', p, proposal_oracle, ['result', 'disposition'], 'temporary', '/referral')
                negative(name + '/attempt', p, proposal_oracle, ['result', 'attempts'],
                         [dict(action=action, authority='panel')], '/attempt')
    p = proposal()
    for field in ('delegation', 'permissions'):
        unsupported_proposal('590/' + field + '/missing', p, [field], None,
                             '/delegation' if field == 'delegation' else '/permission', True)
    for state in SOURCE_STATES[1:] + ('UNKNOWN',):
        unsupported_proposal('590/delegation/state/' + state, p, ['delegation', 'state'], state, '/delegation')
    for path in (['delegation', 'state'], ['delegation', 'source'], ['permissions', 'source'], ['permissions', 'role']):
        for label, val in [('missing', None), ('empty', '')]:
            unsupported_proposal('590/field/' + '/'.join(path) + '/' + label, p, path, val,
                                 '/delegation' if path[0] == 'delegation' else '/permission', label == 'missing')
    for role in ('Product', 'Architect', 'UNKNOWN'):
        unsupported_proposal('590/permission/actor/' + role, p, ['permissions', 'role'], role, '/permission')
    # Delegation scope is an allow-list; each representative must retain membership
    # and uniqueness, independently of the permission list controls.
    for action in ELIGIBLE:
        c = proposal(action)
        i = c['delegation']['scope'].index(action)
        for mode, scope in [('missing', [a for a in ELIGIBLE if a != action]),
                             ('duplicate', list(ELIGIBLE) + [action]),
                             ('wrong', list(ELIGIBLE[:i]) + ['UNKNOWN'] + list(ELIGIBLE[i + 1:]))]:
            unsupported_proposal('590/delegation/scope/' + action + '/' + mode, c,
                                 ['delegation', 'scope'], scope, '/delegation')
    for field in ('scope', 'permitted'):
        for label, value in [('missing', None), ('empty', []), ('duplicate', ['docs-pr', 'docs-pr']), ('wrong', ['B'])]:
            unsupported_proposal('590/permission/' + field + '/' + label, p, ['permissions', field], value,
                                 '/permission', label == 'missing')
    for value in ('accepted', 'UNKNOWN', None):
        negative('590/acceptance/' + str(value), p, proposal_oracle, ['result', 'acceptance'], value, '/inferred-acceptance')
    for path in (['result', 'disposition'], ['result', 'route'], ['result', 'acceptance']):
        negative('590/result/delete/' + path[-1], p, proposal_oracle, path, None,
                 '/inferred-acceptance' if path[-1] == 'acceptance' else '/disposition', True)
    for value in ('maintainer', 'release-authority', 'UNKNOWN'):
        negative('590/route/' + value, p, proposal_oracle, ['result', 'route'], value,
                 '/release-authority' if value == 'release-authority' else '/disposition')
    for source in ('A', 'B'):
        fixture('590/source-identity/' + source, changed(p, lambda m: m['delegation'].update(source=source)), proposal_oracle)
    for path in (['delegation', 'words'], ['release_authority', 'source', 'words']):
        for text in ('opaque A', 'opaque B'):
            fixture('590/opaque/' + '/'.join(path) + '/' + text, changed(p, lambda m: put(m, path, text)), proposal_oracle)
        unsupported_proposal('590/opaque/' + '/'.join(path) + '/empty', p if path[0] == 'delegation' else release_proposal(),
                             path, '', '/delegation' if path[0] == 'delegation' else '/release-authority')
    # Prior denials are action identities, never inferred from command prose.
    p['prior_denials'] = [dict(action=p['action'], result='denied')]
    negative('590/denied-retry', p, proposal_oracle, ['result', 'attempts'],
             [dict(action=p['action'], authority='panel')], '/denied-retry')
    fixture('590/denial-none', changed(p, lambda m: m['prior_denials'][0].update(result='none')), proposal_oracle)
    negative('590/denial-UNKNOWN', p, proposal_oracle, ['prior_denials', 0, 'result'], 'UNKNOWN', '/denied-retry')
    release_checks()
    target_checks()


def only(oracle, diagnostic):
    """Exactness wrapper: the oracle must return exactly the one named diagnostic."""
    return lambda value: [diagnostic] if oracle(value) == [diagnostic] else ['MISMATCH ' + repr(oracle(value))]


def target_checks():
    # T0: inventory of the fixed token set; removing the new token turns the control red.
    inventory = lambda tokens: [] if ('edit-panel-rules' in tokens and len(tokens) == 19) else ['590/source/action/edit-panel-rules']
    fixture('590/token/edit-panel-rules/inventory', RESERVED, inventory)
    fixture('590/token/edit-panel-rules/inventory/removed', tuple(t for t in RESERVED if t != 'edit-panel-rules'),
            inventory, '590/source/action/edit-panel-rules')
    fixture('590/token/eligible-count', ELIGIBLE, lambda tokens: [] if len(tokens) == 13 else ['590/source/action/eligible'])
    for action in TARGETED:
        for vote in VOTES:
            base = '590/target-' + '%s/' + action + '/' + vote
            # T1-T3: target other stays eligible. T4-T6: panel-rules is reserved.
            fixture(base % 'other', proposal(action, vote, 'other'), proposal_oracle)
            p = proposal(action, vote, 'panel-rules')
            fixture(base % 'panel-rules' + '/settlement', p,
                    only(proposal_oracle, '590/edit-panel-rules/referral'), '590/edit-panel-rules/referral')
            attempt = referral(copy.deepcopy(p))
            attempt['result']['attempts'] = [dict(action=action, authority='panel')]
            fixture(base % 'panel-rules' + '/attempt', attempt,
                    only(proposal_oracle, '590/edit-panel-rules/attempt'), '590/edit-panel-rules/attempt')
            fixture(base % 'panel-rules' + '/safe-referral', referral(copy.deepcopy(p)), proposal_oracle)
    # T6b (#681): each added entry, opaque label, otherwise eligible proposal with target panel-rules is referred; target other stays eligible.
    for label in WIDENED_LABELS:
        for action in TARGETED:
            for vote in VOTES:
                base = '590/target-%s/widened/' + label + '/' + action + '/' + vote
                p = proposal(action, vote, 'panel-rules')
                fixture(base % 'panel-rules' + '/settlement', p,
                        only(proposal_oracle, '590/edit-panel-rules/referral'), '590/edit-panel-rules/referral')
                attempt = referral(copy.deepcopy(p))
                attempt['result']['attempts'] = [dict(action=action, authority='panel')]
                fixture(base % 'panel-rules' + '/attempt', attempt,
                        only(proposal_oracle, '590/edit-panel-rules/attempt'), '590/edit-panel-rules/attempt')
                fixture(base % 'panel-rules' + '/safe-referral', referral(copy.deepcopy(p)), proposal_oracle)
    for label in OTHER_LABELS:
        for action in TARGETED:
            for vote in VOTES:
                fixture('590/target-other/control/' + label + '/' + action + '/' + vote,
                        proposal(action, vote, 'other'), proposal_oracle)
    # T7: delegation independence for the reserved token.
    for state in SOURCE_STATES:
        p = proposal('docs-pr', '3-0', 'panel-rules')
        p['delegation']['state'] = state
        fixture('590/target-panel-rules/delegation/' + state, p,
                only(proposal_oracle, '590/edit-panel-rules/referral'), '590/edit-panel-rules/referral')
        fixture('590/target-panel-rules/delegation/' + state + '/safe-referral', referral(copy.deepcopy(p)), proposal_oracle)
    # T8: target domain; unknown is never read as other.
    for action in TARGETED:
        control = proposal(action)
        for label, value in [('UNKNOWN', 'UNKNOWN'), ('empty', ''), ('missing', None)]:
            unsupported_proposal('590/target/' + action + '/' + label, control, ['target'], value,
                                 '590/' + action + '/target', label == 'missing')
    # T9: the target is a supplied fact; prose is opaque.
    prose = proposal('docs-pr', '3-0', 'other')
    prose['delegation']['words'] = prose['panel'][0]['question'] = 'edit the panel rules in OR43 and the Temporary-decision panel'
    fixture('590/target/prose-ignored/other', prose, proposal_oracle)
    fixture('590/target/prose-ignored/panel-rules', referral(proposal('docs-pr', '3-0', 'panel-rules')), proposal_oracle)
    # T10: release authority has no target.
    release = release_proposal()
    release['target'] = 'panel-rules'
    fixture('590/target/release-ignored', release, proposal_oracle)


def release_proposal():
    p = proposal('merge-work-item-to-release')
    p['delegation'] = None
    p['result'].update(disposition='authorized-existing-route', route='release-authority',
                       attempts=[dict(action=p['action'], authority='release-authority')])
    return p


def release_checks():
    p = release_proposal()
    fixture('590/exact-authorized-release-attempt', p, proposal_oracle)
    for state in SOURCE_STATES[1:] + ('UNKNOWN',):
        unsupported_proposal('590/release/state/' + state, p, ['release_authority', 'source', 'state'], state, '/release-authority')
    for field, values in [('base', ['main', 'release/B', 'UNKNOWN', '']),
                          ('ci', ['failed', 'missing', 'UNKNOWN']), ('tests', ['failed', 'missing', 'UNKNOWN']),
                          ('review', ['changes-requested', 'missing', 'UNKNOWN'])]:
        for value in values:
            unsupported_proposal('590/release/' + field + '/' + value, p, ['release_authority', field], value,
                                 '/release-authority/' + field)
    for field in p['release_authority']:
        unsupported_proposal('590/release/delete/' + field, p, ['release_authority', field], None, '/release-authority', True)
    for field in p['release_authority']['source']:
        unsupported_proposal('590/release/source/delete/' + field, p, ['release_authority', 'source', field], None, '/release-authority', True)
    for field, value in [('action', 'B'), ('base', 'release/B'), ('id', ''), ('kind', 'panel')]:
        unsupported_proposal('590/release/source/' + field + '/mismatch', p, ['release_authority', 'source', field], value, '/release-authority')
    for field in ('action', 'authority'):
        for value in ('B', '', None):
            negative('590/release/attempt/' + field + '/' + str(value), p, proposal_oracle,
                     ['result', 'attempts', 0, field], value, '/attempt', value is None)
    for text in ('opaque A', 'opaque B'):
        fixture('590/release/words/' + text, changed(p, lambda m: m['release_authority']['source'].update(words=text)), proposal_oracle)


def panel_state(p, state):
    r = record('proposal', '2-1' if state == 'resolved-2-1' else '3-0')
    if state == 'incompatible-unresolved':
        r.update(outcome='unresolved', vote=None)
        for row, position in zip(r['positions'], ('adopt', 'defer', 'reject')):
            row['position'] = position
    p['panel'] = [r]


def outcome_checks():
    for action in ELIGIBLE:
        for state in ('resolved-3-0', 'resolved-2-1', 'incompatible-unresolved'):
            for outcome in ('settlement', 'referral'):
                p = proposal(action)
                panel_state(p, state)
                if outcome == 'referral':
                    referral(p)['result']['reason'] = 'panel-unresolved'
                valid = (outcome == 'referral') == (state == 'incompatible-unresolved')
                fixture('590-panel-' + action + '-' + state + '-' + outcome, p, proposal_oracle,
                        None if valid else '/unresolved-panel-settlement' if outcome == 'settlement' else '/disposition')
    for state in ('resolved-3-0', 'resolved-2-1', 'incompatible-unresolved'):
        p = release_proposal()
        panel_state(p, state)
        fixture('590-release-existing-authority-positive-' + state, p, proposal_oracle)
        for field, value in [('source', None), ('base', 'main'), ('ci', 'failed'), ('tests', 'failed'), ('review', 'changes-requested')]:
            unsupported_proposal('590-release-existing-authority-negative-' + state + '-' + field,
                                 p, ['release_authority', field], value, '/release-authority')
        unsupported_proposal('590-release-existing-authority-negative-' + state + '-permission',
                             p, ['permissions', 'permitted'], [], '/release-authority')


def clean_evidence(higher=False):
    e = {n: dict(model='synthetic', variant='synthetic-higher' if higher and n != 'author' else 'synthetic-high',
                 entry='fixture:index-higher' if higher and n != 'author' else 'fixture:index-equal',
                 date='2026-11-05', score=60 if higher and n != 'author' else 50) for n in ('author',) + MEMBERS}
    e.update(briefs=[dict(recipient=n, session='fresh:' + n, inherits=[], at=1,
                          payload=[dict(kind=k, text='\n'.join(CLAUSES[591]) if k == 'procedure' else 'opaque A') for k in REQUIRED_TAGS])
                     for n in ('Product', 'Architect')],
             returns=[dict(member=n, session='fresh:' + n, at=2, position='adopt', evidence='opaque A') for n in ('Product', 'Architect')],
             own_position=dict(member='orchestrator', position='adopt', at=2),
             reconciliation=dict(at=3, used_sessions=['fresh:Product', 'fresh:Architect'], disposition='settled'),
             experiments=[dict(kind='local-read', id='A', command=['opaque A'], inputs=['A'], result='opaque A', limits='opaque A',
                               permissions=['local-read'], prior=[], attempts=[dict(id='A', command=['opaque A'], inputs=['A'])], disposition='accepted')])
    return e


def floor_checks():
    e = clean_evidence()
    fixture('591-clean-equal-floor', e, floor_oracle)
    fixture('591-clean-higher-floor', clean_evidence(True), floor_oracle)
    for subject in ('author',) + MEMBERS:
        for field in ('model', 'variant', 'entry', 'date', 'score'):
            missing('591/' + subject + '/' + field, e, floor_oracle, [subject, field], subject + '/' + field)
            if field != 'date':
                negative('591/' + subject + '/' + field + '/UNKNOWN', e, floor_oracle, [subject, field],
                         'UNKNOWN' if field != 'score' else 99, subject + '/' + ('entry/unknown' if field == 'entry' else field + '/captured-entry-mismatch'))
        for date in ('invalid', '2026-99-99'):
            negative('591/' + subject + '/date/' + date, e, floor_oracle, [subject, 'date'], date, subject + '/date')
    for member in MEMBERS:
        weaker = changed(e, lambda m: m[member].update(score=49, variant='synthetic-weaker', entry='fixture:index-weaker'))
        fixture('591/' + member + '/below-author', weaker, floor_oracle, member + '/below-author')
        fixture('591/' + member + '/below-author/control', e, floor_oracle)
    lists('591/briefs', e, floor_oracle, ['briefs'], '/brief', 'recipient')
    lists('591/returns', e, floor_oracle, ['returns'], '/return', 'member')
    lists('591/used-sessions', e, floor_oracle, ['reconciliation', 'used_sessions'], 'separate-sessions/reconciliation')
    for i, recipient in enumerate(('Product', 'Architect')):
        lists('591/' + recipient + '/tags', e, floor_oracle, ['briefs', i, 'payload'], recipient + '/brief/', 'kind')
        for tag in PROHIBITED_TAGS:
            negative('591/' + recipient + '/prohibited/' + tag, e, floor_oracle, ['briefs', i, 'payload'],
                     e['briefs'][i]['payload'] + [dict(kind=tag, text='opaque B')], recipient + '/prohibited-tag/' + tag)
        negative('591/' + recipient + '/tag/UNKNOWN', e, floor_oracle, ['briefs', i, 'payload'],
                 e['briefs'][i]['payload'] + [dict(kind='UNKNOWN', text='opaque B')], recipient + '/brief/')
        negative('591/' + recipient + '/canonical-procedure', e, floor_oracle, ['briefs', i, 'payload', 0, 'text'], 'opaque B', '/canonical-procedure')
        for j, tag in enumerate(REQUIRED_TAGS):
            missing('591/' + recipient + '/tag-text/' + tag, e, floor_oracle,
                    ['briefs', i, 'payload', j, 'text'], recipient + '/brief/' + tag, opaque=tag != 'procedure')
        for field in ('recipient', 'session', 'inherits', 'at', 'payload'):
            negative('591/' + recipient + '/brief/delete/' + field, e, floor_oracle, ['briefs', i, field], None,
                     '/brief' if field == 'recipient' else '/inherited-dispatch' if field in ('session', 'inherits') else '/return-order' if field == 'at' else '/brief/', True)
        negative('591/' + recipient + '/inherits', e, floor_oracle, ['briefs', i, 'inherits'], ['A'], '/inherited-dispatch')
        for field in ('member', 'session', 'at', 'position', 'evidence'):
            missing('591/' + recipient + '/return/' + field, e, floor_oracle, ['returns', i, field], '/return')
        negative('591/' + recipient + '/return/wrong-session', e, floor_oracle, ['returns', i, 'session'], 'B', '/return')
        for value in (2, 3):
            negative('591/' + recipient + '/brief-return/' + str(value), e, floor_oracle, ['briefs', i, 'at'], value, '/return-order')
        for value in (3, 4):
            negative('591/' + recipient + '/return-reconciliation/' + str(value), e, floor_oracle, ['returns', i, 'at'], value, '/return-order')
    negative('591/same-session', e, floor_oracle, ['briefs', 1, 'session'], 'fresh:Product', 'separate-sessions')
    for field in ('member', 'position', 'at'):
        missing('591/own-position/' + field, e, floor_oracle, ['own_position', field], 'orchestrator-position-before-reconciliation')
    negative('591/own-position/wrong-member', e, floor_oracle, ['own_position', 'member'], 'Product', 'orchestrator-position-before-reconciliation')
    for time in (3, 4):
        negative('591/own-position/order/' + str(time), e, floor_oracle, ['own_position', 'at'], time, 'orchestrator-position-before-reconciliation')
    for field in ('at', 'used_sessions', 'disposition'):
        negative('591/reconciliation/delete/' + field, e, floor_oracle, ['reconciliation', field], None,
                 'separate-sessions/reconciliation' if field == 'used_sessions' else '/return-order' if field == 'at' else 'reconciliation/', True)
    negative('591/reconciliation/UNKNOWN', e, floor_oracle, ['reconciliation', 'disposition'], 'UNKNOWN', 'reconciliation/')
    for kind in ('local-write', 'network-mutation', 'denied-retry', 'UNKNOWN'):
        safe = copy.deepcopy(e)
        exp = safe['experiments'][0]
        exp.update(kind=kind, attempts=[], disposition='refused')
        if kind == 'denied-retry':
            exp['prior'] = [dict(id='A', result='denied')]
        fixture('591/experiment/' + kind + '/safe', safe, floor_oracle, 'experiment/kind' if kind == 'UNKNOWN' else None)
        negative('591/experiment/' + kind + '/attempt', safe if kind != 'UNKNOWN' else e, floor_oracle,
                 ['experiments', 0, 'attempts'] if kind != 'UNKNOWN' else ['experiments', 0, 'kind'],
                 e['experiments'][0]['attempts'] if kind != 'UNKNOWN' else kind,
                 'experiment/' + kind if kind != 'UNKNOWN' else 'experiment/kind')
        if kind != 'UNKNOWN':
            negative('591/experiment/' + kind + '/accepted', safe, floor_oracle, ['experiments', 0, 'disposition'], 'accepted', 'experiment/' + kind)
    for field in ('command', 'inputs', 'result', 'limits', 'id'):
        for label in ('missing', 'empty'):
            m = negative('591/experiment/' + field + '/' + label, e, floor_oracle, ['experiments', 0, field], '', 'experiment/' + field, label == 'missing')
            m['experiments'][0].update(disposition='incomplete', attempts=[])
            m['reconciliation']['disposition'] = 'unresolved'
            fixture('591/experiment/' + field + '/' + label + '/safe', m, floor_oracle, 'experiment/permission' if label in ('duplicate', 'UNKNOWN') else None)
            negative('591/experiment/' + field + '/' + label + '/unsupported-settlement', m, floor_oracle,
                     ['reconciliation', 'disposition'], 'settled', 'reconciliation/unsupported-settlement')
    for path in (['permissions'], ['attempts']):
        field = path[0]
        for label, value in [('empty', []), ('wrong', ['none'] if field == 'permissions' else [dict(id='B', command=['opaque A'], inputs=['A'])]),
                              ('duplicate', e['experiments'][0][field] * 2), ('UNKNOWN', ['UNKNOWN'])]:
            m = negative('591/experiment/' + field + '/' + label, e, floor_oracle, ['experiments', 0, field], value,
                         'experiment/permission' if field == 'permissions' else 'experiment/capture')
            if field == 'permissions':
                m['experiments'][0].update(disposition='refused', attempts=[])
                fixture('591/experiment/' + field + '/' + label + '/safe', m, floor_oracle, 'experiment/permission' if label in ('duplicate', 'UNKNOWN') else None)
    for field in ('id', 'command', 'inputs'):
        missing('591/experiment/attempt/' + field, e, floor_oracle, ['experiments', 0, 'attempts', 0, field], 'experiment/capture')
    for value in ('refused', 'incomplete', 'UNKNOWN'):
        negative('591/experiment/disposition/' + value, e, floor_oracle, ['experiments', 0, 'disposition'], value, 'experiment/')
    for field in ('kind', 'permissions', 'attempts', 'disposition'):
        negative('591/experiment/delete/' + field, e, floor_oracle, ['experiments', 0, field], None, 'experiment/', True)
    retry = changed(e, lambda m: m['experiments'][0].update(prior=[dict(id='A', result='denied')]))
    fixture('591/experiment/prior-denial-matching', retry, floor_oracle, 'experiment/denied-retry')
    fixture('591/experiment/prior-denial-other', changed(retry, lambda m: m['experiments'][0]['prior'][0].update(id='B')), floor_oracle)
    for field in ('command', 'result', 'limits'):
        m = copy.deepcopy(e)
        m['experiments'][0][field] = ['opaque B'] if field == 'command' else 'opaque B'
        if field == 'command':
            m['experiments'][0]['attempts'][0]['command'] = ['opaque B']
        fixture('591/experiment/opaque/' + field, m, floor_oracle)


def prior_identity_checks():
    e = clean_evidence()
    fixture('591/prior-identity/clean-read', e, floor_oracle)
    unrelated = changed(e, lambda m: m['experiments'][0].update(prior=[dict(id='B', result='denied')]))
    fixture('591/prior-identity/unrelated', unrelated, floor_oracle)
    matching = changed(unrelated, lambda m: m['experiments'][0]['prior'][0].update(id='A'))
    fixture('591/prior-identity/matching-attempt', matching, floor_oracle, '591/experiment/denied-retry')
    check('591/reconciliation/unsupported-settlement' in floor_oracle(matching),
          '591/prior-identity/matching-attempt/settlement', 'mutation')
    safe = changed(matching, lambda m: m['experiments'][0].update(disposition='refused', attempts=[]))
    safe['reconciliation']['disposition'] = 'unresolved'
    fixture('591/prior-identity/matching-refusal', safe, floor_oracle)
    for label, value in [('missing', None), ('empty', ''), ('null', None)]:
        for handling, control in [('attempt', matching), ('safe', safe)]:
            name = '591/prior-identity/' + label + '/' + handling
            mutant = negative(name, control if handling == 'safe' else unrelated, floor_oracle,
                              ['experiments', 0, 'prior', 0, 'id'], value,
                              '591/experiment/denied-retry', delete=label == 'missing')
            diagnostics = floor_oracle(mutant)
            check(('591/reconciliation/unsupported-settlement' in diagnostics) == (handling == 'attempt'),
                  name + '/settlement', 'mutation')
            if handling == 'safe':
                check(mutant['experiments'][0]['attempts'] == [], name + '/no-attempt')


def explicit_acceptance(row):
    return dict(kind='explicit', source='A', applicable_source='A', decisions=[row['id']],
                words='opaque A', scrutiny='individual' if row['vote'] == '2-1' else 'group')


def disclosure_request(rows, consumer=645, round_no=1, earlier=None):
    return dict(source='issue-comments', consumer=consumer, round=round_no,
                earlier_unaccepted=list(earlier or []),
                rows=sorted(copy.deepcopy(rows), key=lambda r: {'3-0': 0, '2-1': 1, None: 2}.get(r.get('vote'), 3)))


def disclosure_checks():
    for consumer in (645, 646, 647):
        rows = record_inventory()
        for row in rows[:2]:
            row.update(risk=True, limit_widening=True)
        for round_no in (1, 2):
            earlier = []
            if round_no == 2:
                rows[0].update(accepted=True, acceptance_evidence=explicit_acceptance(rows[0]))
                earlier = [r['id'] for r in rows if not r['accepted']]
                rows.append(record('new', '2-1'))
            request = disclosure_request(rows, consumer, round_no, earlier)
            oracle = lambda req: disclosure_oracle(rows, req, consumer, round_no, earlier)
            name = '592/' + str(consumer) + '/round-' + str(round_no)
            fixture(name + '/two-round-control', request, oracle)
            for i, row in enumerate(request['rows']):
                for field in row:
                    negative(name + '/' + row['id'] + '/delete/' + field, request, oracle,
                             ['rows', i, field], None, row['id'] + '/inventory/order/fields', True)
                for field in ('question', 'scope', 'rationale', 'resolution', 'risk', 'limit_widening'):
                    negative(name + '/' + row['id'] + '/copy/' + field, request, oracle, ['rows', i, field],
                             not row[field] if type(row[field]) is bool else 'opaque B', row['id'] + '/copy/' + field)
            lists(name + '/inventory', request, oracle, ['rows'], 'inventory/order/fields', 'id')
            negative(name + '/reverse', request, oracle, ['rows'], list(reversed(request['rows'])), 'inventory/order/fields')
            for field, values in [('source', ['session-memory', 'UNKNOWN', '']), ('consumer', [646 if consumer != 646 else 645, 'UNKNOWN', '']),
                                  ('round', [2 if round_no == 1 else 1, 'UNKNOWN', ''])]:
                for value in values:
                    negative(name + '/' + field + '/' + str(value), request, oracle, [field], value, 'inventory/' + field)
                negative(name + '/' + field + '/missing', request, oracle, [field], None, 'inventory/' + field, True)
            if earlier:
                lists(name + '/carryforward', request, oracle, ['earlier_unaccepted'], '/carryforward')


def acceptance_checks():
    for consumer in (645, 646, 647):
        for vote in VOTES:
            for flag in ('risk', 'limit_widening'):
                r = record('acceptance', vote)
                r[flag] = True
                for kind in ('explicit', 'silence', 'merge-permission', 'temporary-disposition', 'unanimity', 'release-merge', 'missing', 'UNKNOWN', 'other-decision'):
                    row = copy.deepcopy(r)
                    row['acceptance_evidence'] = explicit_acceptance(row)
                    if kind == 'other-decision':
                        row['acceptance_evidence']['decisions'] = ['B']
                    else:
                        row['acceptance_evidence']['kind'] = kind
                    prefix = '592/acceptance/' + str(consumer) + '/' + vote + '/' + flag + '/' + kind
                    oracle = lambda req: disclosure_oracle([row], req, consumer)
                    req = disclosure_request([row], consumer)
                    fixture(prefix + '/unaccepted-carryforward', req, oracle, '/acceptance-evidence' if kind == 'UNKNOWN' else None)
                    accepted = changed(req, lambda m: m['rows'][0].update(accepted=True))
                    row['accepted'] = True
                    fixture(prefix + '/accepted', accepted, oracle, None if kind == 'explicit' else '/acceptance-evidence')
                    row['accepted'] = False
                    if kind != 'UNKNOWN':
                        negative(prefix + '/erased-unaccepted', req, oracle, ['rows'], [], 'inventory/order/fields')
    for vote in VOTES:
        row = record('A', vote)
        row.update(accepted=True, acceptance_evidence=explicit_acceptance(row))
        req = disclosure_request([row])
        oracle = lambda value: disclosure_oracle([row], value)
        for field in row['acceptance_evidence']:
            # Mutate supplied evidence and its exact copy together: tests support,
            # independently of the separate copied-byte checks below.
            for label, value in [('missing', None), ('empty', '')]:
                m = copy.deepcopy(row)
                if label == 'missing':
                    del m['acceptance_evidence'][field]
                else:
                    m['acceptance_evidence'][field] = value
                fixture('592/' + vote + '/evidence/' + field + '/' + label, disclosure_request([m]),
                        lambda request: disclosure_oracle([m], request), '/acceptance-evidence')
                fixture('592/' + vote + '/evidence/' + field + '/' + label + '/control', req, oracle)
        for field, value in [('source', 'B'), ('decisions', ['B']), ('decisions', ['A', 'A']),
                              ('scrutiny', 'UNKNOWN'), ('scrutiny', 'group' if vote == '2-1' else '')]:
            m = copy.deepcopy(row)
            m['acceptance_evidence'][field] = value
            fixture('592/' + vote + '/evidence/' + field + '/' + repr(value), disclosure_request([m]),
                    lambda request: disclosure_oracle([m], request), '/acceptance-evidence')
        for field in row['acceptance_evidence']:
            negative('592/' + vote + '/copy/evidence/' + field, req, oracle, ['rows', 0, 'acceptance_evidence', field], 'B', '/copy/acceptance_evidence')
        m = copy.deepcopy(row)
        m['acceptance_evidence']['words'] = 'opaque B'
        fixture('592/' + vote + '/opaque-words', disclosure_request([m]), lambda request: disclosure_oracle([m], request))
    a, b = record('A'), record('B')
    for row in (a, b):
        row.update(accepted=True, acceptance_evidence=explicit_acceptance(row))
        row['acceptance_evidence']['decisions'] = ['A', 'B']
    fixture('592/unanimous-group', disclosure_request([a, b]), lambda req: disclosure_oracle([a, b], req))


def copied_boolean_checks():
    for field in ('risk', 'limit_widening', 'accepted'):
        for value in (True, False):
            row = record('A')
            row[field] = value
            if row['accepted']:
                row['acceptance_evidence'] = explicit_acceptance(row)
            req = disclosure_request([row])
            oracle = lambda request: disclosure_oracle([row], request)
            name = '592/copy-boolean/' + field + '/' + str(value)
            fixture(name + '/control', req, oracle)
            negative(name + '/integer', req, oracle, ['rows', 0, field], int(value), '592/A/copy/' + field)
            negative(name + '/opposite', req, oracle, ['rows', 0, field], not value, '592/A/copy/' + field)
        row = record('A')
        req = disclosure_request([row])
        oracle = lambda request: disclosure_oracle([row], request)
        for label, value in [('missing', None), ('empty', ''), ('null', None), ('UNKNOWN', 'UNKNOWN')]:
            mutant = negative('592/copy-boolean/' + field + '/' + label, req, oracle,
                              ['rows', 0, field], value, '592/A/copy/' + field, delete=label == 'missing')
            if label == 'missing':
                fixture('592/copy-boolean/' + field + '/missing/inventory', mutant, oracle,
                        '592/A/inventory/order/fields')


def controlled_grant(scope='skip=Planning', issue=645):
    return dict(state='accepted', kind='human', human='maintainer', issue=issue, id='A', link='A',
                applicable_source='A', scopes=[scope] if isinstance(scope, str) else scope,
                words='opaque A', conditions=dict(doc_only=True, executable_diff=False))


QA_CAPTURE = dict(base='A', head='A', content='opaque A')
QA_HASH = hashlib.sha256(QA_CAPTURE['content'].encode()).hexdigest()


def protection_conditions():
    return {
        'unanimous-skip': dict(votes=['skip'] * 3, required_vote='3-0', vote='3-0', scope='skip=Planning', eligible=['skip=Planning'],
                              source=controlled_grant(), actual=dict(doc_only=True, executable_diff=False),
                              protected=dict(adds_scenario=False, executable_diff=False, doc_only=True, requires=['Discovery', 'Review'], selected=list(STAGES))),
        'protected-work': dict(adds_scenario=True, executable_diff=True, doc_only=False,
                               requires=['Discovery', 'Test', 'Implementation', 'Review'], selected=list(STAGES)),
        'evidence-before-action': dict(evidence='A', action='A', evidence_at=1, action_at=2),
        'advance-ordering': dict(decision='A', waiver='A', commit='A', pr='A', decision_at=1, waiver_at=1, commit_at=2, pr_at=2),
        'fresh-review': dict(reviewer_session='A', previous_session='B', inherits=[]),
        'review-depth': dict(required='thorough', selected='thorough'),
        'valid-test-skip': dict(human_source=controlled_grant('skip=Test'), scope='skip=Test', actual=dict(doc_only=True, executable_diff=False), validation=dict(exit=0, scopes=['skip=Test'])),
        'A49-provenance': dict(base='A', head='A', qa='A', applicable='A', artifacts={'A': QA_CAPTURE, 'B': dict(base='A', head='A', content='opaque B')},
                               hashes=dict(qa=QA_HASH, head=QA_HASH), head_content='opaque A', comparison='match', comparison_at=1, review_at=2),
        'per-item-human-authority': dict(source=controlled_grant(), issue=645, scope='skip=Planning', actual=dict(doc_only=True, executable_diff=False))}


def authority_record(kind='posting'):
    source = controlled_grant(['skip=Planning', 'skip=Test'])
    conditions = protection_conditions()
    return dict(kind=kind, source=source, applied_scope=['skip=Planning', 'skip=Test'], conditions=dict(doc_only=True, executable_diff=False),
                posting=dict(role='orchestrator', human='maintainer', reason=source['words'], validation=dict(exit=0, scopes=['skip=Planning', 'skip=Test']),
                             round_trip=dict(words=source['words'], scopes=['skip=Planning', 'skip=Test']), pr_body='Closes #645', issue=645),
                protections=[dict(name=n, evidence='opaque A', work='opaque A', conditions=conditions[n], disposition='retained') for n in PROTECTIONS],
                panel=[record('authority')], result=dict(disposition='authorized-route', claims=['supplied-evidence-only'], attempts=[], limitation='supplied evidence only'))


def authority_negative(name, control, path, value, diagnostic, delete=False):
    m = negative(name, control, authority_oracle, path, value, diagnostic, delete)
    m['result'].update(disposition='referred', attempts=[], limitation='supplied evidence only')
    malformed = value == 'UNKNOWN' and path[-1] in ('state', 'kind')
    fixture(name + '/safe-referral', m, authority_oracle, diagnostic if malformed else None)
    if not malformed:
        negative(name + '/posting', m, authority_oracle, ['result', 'attempts'], ['post-override'], '593/posting-attempt')


def authority_checks():
    e = authority_record()
    fixture('593-authorized-human-source', e, authority_oracle)
    posting = changed(e, lambda m: m['result'].update(attempts=['post-override']))
    fixture('593-authorized-posting', posting, authority_oracle)
    panel = authority_record('eligible-panel')
    panel.update(source=None, proposal=proposal())
    panel['result']['disposition'] = 'temporary'
    fixture('593-valid-eligible-panel', panel, authority_oracle)
    negative('593/panel/posting', panel, authority_oracle, ['result', 'attempts'], ['post-override'], '593/posting-attempt')
    negative('593/panel/disposition', panel, authority_oracle, ['result', 'disposition'], 'authorized-route', '593/eligible-panel-disposition')
    strong = authority_record('stage-selection')
    strong['selection'] = list(STAGES)
    fixture('593-valid-strong-stage-selection', strong, authority_oracle)
    lists('593/stage-selection', strong, authority_oracle, ['selection'], '593/stage-selection')
    for state in SOURCE_STATES[1:] + ('UNKNOWN',):
        authority_negative('593/source/state/' + state, e, ['source', 'state'], state, '593/source/referral')
    for kind in ('panel', 'copied-approval', 'structural-check', 'UNKNOWN'):
        authority_negative('593/source/kind/' + kind, e, ['source', 'kind'], kind, '593/source/referral')
    authority_negative('593/source/absent', e, ['source'], None, '593/source/referral')
    for field in e['source']:
        authority_negative('593/source/delete/' + field, e, ['source', field], None, '593/source/referral', True)
    for field, value in [('id', 'B'), ('issue', 646), ('scopes', ['skip=Review']), ('conditions', dict(doc_only=False, executable_diff=False))]:
        authority_negative('593/source/mismatch/' + field, e, ['source', field], value, '593/source/referral')
    for field in ('id', 'link', 'human', 'words'):
        authority_negative('593/source/empty/' + field, e, ['source', field], '', '593/source/referral')
    for field, value, diag in [('role', 'Product', 'posting-role'), ('role', 'Architect', 'posting-role'), ('role', 'UNKNOWN', 'posting-role'),
                               ('human', 'B', 'human-identity'), ('reason', 'opaque B', 'human-words'), ('pr_body', 'Closes #646', 'Closes-issue-link'),
                               ('issue', 646, 'source/referral')]:
        authority_negative('593/posting/' + field + '/' + str(value), e, ['posting', field], value, '593/' + diag)
    for field in e['posting']:
        authority_negative('593/posting/delete/' + field, e, ['posting', field], None,
                           '593/' + {'role': 'posting-role', 'human': 'human-identity', 'reason': 'human-words', 'validation': 'validation',
                                     'round_trip': 'round-trip', 'pr_body': 'Closes-issue-link', 'issue': 'source/referral'}[field], True)
    for field in ('validation', 'round_trip'):
        for subfield in e['posting'][field]:
            authority_negative('593/' + field + '/delete/' + subfield, e, ['posting', field, subfield], None,
                               '593/validation' if field == 'validation' else '593/round-trip', True)
    for value in (1, 'missing', 'UNKNOWN'):
        authority_negative('593/validation/' + str(value), e, ['posting', 'validation', 'exit'], value, '593/validation')
    for path in (['applied_scope'], ['posting', 'validation', 'scopes'], ['posting', 'round_trip', 'scopes'], ['source', 'scopes']):
        for i, scope in enumerate(at(e, path)):
            original = at(e, path)
            for mode, value in [('missing', original[:i] + original[i + 1:]), ('duplicate', original + [scope]), ('wrong', original[:i] + ['skip=Review'] + original[i + 1:])]:
                authority_negative('593/scopes/' + '/'.join(path) + '/' + scope + '/' + mode, e, path, value,
                                   '593/round-trip' if 'round_trip' in path else '593/validation' if 'validation' in path else '593/source/referral')
    for value in ('opaque B', '', None):
        authority_negative('593/round-trip/words/' + str(value), e, ['posting', 'round_trip', 'words'], value, '593/round-trip', value is None)
    for claim in ('authenticated-human', 'live-obedience', 'verified-capability', 'UNKNOWN'):
        negative('593/claim/' + claim, e, authority_oracle, ['result', 'claims'], [claim], '593/claim/' + claim)
    for value in ('', None):
        negative('593/limitation/' + str(value), e, authority_oracle, ['result', 'limitation'], value, '593/evidence-limitation', value is None)
    for disposition in ('temporary', 'referred', 'UNKNOWN'):
        negative('593/disposition/' + disposition, e, authority_oracle, ['result', 'disposition'], disposition, '593/authorized-route-disposition')
    for attempt in ('bypass', 'bypass:Review', 'UNKNOWN'):
        negative('593/attempt/' + attempt, e, authority_oracle, ['result', 'attempts'], [attempt],
                 '593/bypass-attempt' if attempt.startswith('bypass') else '593/posting-attempt')
    for i, name in enumerate(PROTECTIONS):
        for mode, rows in [('missing', e['protections'][:i] + e['protections'][i + 1:]),
                           ('duplicate', e['protections'] + [e['protections'][i]]),
                           ('wrong', e['protections'][:i] + [dict(name='UNKNOWN')] + e['protections'][i + 1:])]:
            negative('593/protections/' + name + '/' + mode, e, authority_oracle, ['protections'], rows, '593/protection/' + name)
        for field in ('evidence', 'work', 'conditions', 'disposition'):
            missing('593/protection/' + name + '/' + field, e, authority_oracle, ['protections', i, field], '593/protection/' + name)
        m = copy.deepcopy(e)
        m['source']['kind'] = 'panel'
        m['panel'] = [record('bypass', '2-1')]
        m['result']['disposition'] = 'referred'
        fixture('593/majority-bypass/' + name + '/safe', m, authority_oracle)
        negative('593/majority-bypass/' + name, m, authority_oracle, ['protections', i, 'disposition'], 'bypass-authorized', '593/protection/' + name)
        negative('593/majority-bypass/' + name + '/attempt', m, authority_oracle, ['result', 'attempts'], ['bypass:' + name], '593/bypass-attempt')
    m = copy.deepcopy(e)
    m['source']['words'] = m['posting']['reason'] = m['posting']['round_trip']['words'] = 'opaque B'
    fixture('593/opaque-human-words', m, authority_oracle)


def protection_checks():
    e = authority_record()
    def bad(name, suffix, path, value=None, delete=False):
        i = PROTECTIONS.index(name)
        negative('593/conditions/' + name + '/' + suffix, e, authority_oracle,
                 ['protections', i, 'conditions'] + path, value, '593/protection/' + name, delete)
    for name, conditions in protection_conditions().items():
        fixture('593/' + name + '/positive', e, authority_oracle)
        for field in conditions:
            bad(name, 'delete/' + field, [field], delete=True)
    for stage in ('Planning', 'Test', 'Implementation'):
        m = copy.deepcopy(e)
        c = m['protections'][0]['conditions']
        c.update(scope='skip=' + stage, eligible=['skip=' + stage], source=controlled_grant('skip=' + stage))
        fixture('593/unanimous-skip/eligible/' + stage, m, authority_oracle)
    for stage in ('Discovery', 'Review'):
        for eligibility, values in [('truthful', ['skip=Planning', 'skip=Test', 'skip=Implementation']), ('lying', ['skip=' + stage])]:
            for disposition in ('retained', 'bypass-authorized'):
                m = copy.deepcopy(e)
                c = m['protections'][0]['conditions']
                c.update(scope='skip=' + stage, eligible=values)
                m['protections'][0]['disposition'] = disposition
                fixture('593/protected-skip/' + stage + '/' + eligibility + '/' + disposition, m, authority_oracle, '593/protection/unanimous-skip')
    skip_required_checks(e)
    bad('unanimous-skip', 'UNKNOWN-scope', ['scope'], 'UNKNOWN')
    for i, member in enumerate(MEMBERS):
        for vote in ('retain', 'UNKNOWN'):
            bad('unanimous-skip', member + '/' + vote, ['votes', i], vote)
    for field in ('votes', 'eligible'):
        original = e['protections'][0]['conditions'][field]
        for i, value in enumerate(original):
            for mode, replacement in [('missing', original[:i] + original[i + 1:]), ('duplicate', original + [value]), ('wrong', original[:i] + ['UNKNOWN'] + original[i + 1:])]:
                bad('unanimous-skip', field + '/' + str(i) + '/' + mode, [field], replacement)
    for field in ('vote', 'required_vote'):
        for value in ('2-1', 'UNKNOWN'):
            bad('unanimous-skip', field + '/' + value, [field], value)
    for field in ('actual', 'source'):
        bad('unanimous-skip', field + '/wrong', [field], {})
    for field in ('adds_scenario', 'executable_diff', 'doc_only'):
        bad('protected-work', field + '/UNKNOWN', [field], 'UNKNOWN')
        for value in (True, False):
            m = copy.deepcopy(e)
            m['protections'][1]['conditions'][field] = value
            fixture('593/protected-work/' + field + '/' + str(value), m, authority_oracle)
    # Each selected stage is independently represented as required in this control.
    m = copy.deepcopy(e)
    m['protections'][1]['conditions']['requires'] = list(STAGES)
    for field in ('requires', 'selected'):
        original = at(m, ['protections', 1, 'conditions', field])
        for i, stage in enumerate(original):
            for mode, value in [('missing', original[:i] + original[i + 1:]), ('duplicate', original + [stage]), ('wrong', original[:i] + ['UNKNOWN'] + original[i + 1:])]:
                if field == 'requires' and mode == 'missing':
                    fixture('593/stage-lists/requires/' + stage + '/missing-safe',
                            changed(m, lambda r: put(r, ['protections', 1, 'conditions', field], value)), authority_oracle)
                else:
                    negative('593/stage-lists/' + field + '/' + stage + '/' + mode, m, authority_oracle,
                             ['protections', 1, 'conditions', field], value, '593/protection/protected-work')
    for stage in ('Discovery', 'Test', 'Implementation', 'Review'):
        test = copy.deepcopy(e)
        c = test['protections'][1]['conditions']
        c['requires'].remove(stage)
        fixture('593/protected-work/claimed-omission/' + stage + '/safe-control', test, authority_oracle)
        negative('593/protected-work/claimed-omission/' + stage, test, authority_oracle,
                 ['protections', 1, 'conditions', 'selected'], [s for s in STAGES if s != stage], '593/protection/protected-work')
    for name, lefts, rights in [('evidence-before-action', ('evidence',), ('action',)),
                                ('advance-ordering', ('decision', 'waiver'), ('commit', 'pr'))]:
        for left in lefts:
            for right in rights:
                for relation, time in [('equal', 2), ('after', 3)]:
                    bad(name, left + '/' + right + '/' + relation, [left + '_at'], time)
        for identity in lefts + rights:
            bad(name, identity + '/empty', [identity], '')
    bad('fresh-review', 'same-session', ['reviewer_session'], 'B')
    bad('fresh-review', 'inherited', ['inherits'], ['A'])
    for field in ('reviewer_session', 'previous_session'):
        bad('fresh-review', field + '/empty', [field], '')
    for required, selected in [('quick', 'quick'), ('quick', 'thorough'), ('thorough', 'thorough')]:
        m = copy.deepcopy(e)
        m['protections'][5]['conditions'].update(required=required, selected=selected)
        fixture('593/review-depth/' + required + '/' + selected, m, authority_oracle)
    bad('review-depth', 'too-quick', ['selected'], 'quick')
    for field in ('required', 'selected'):
        bad('review-depth', field + '/UNKNOWN', [field], 'UNKNOWN')
    for name, field in [('valid-test-skip', 'human_source'), ('per-item-human-authority', 'source')]:
        for state in SOURCE_STATES[1:] + ('UNKNOWN',):
            bad(name, 'source/state/' + state, [field, 'state'], state)
        for kind in ('panel', 'copied-approval', 'structural-check', 'UNKNOWN'):
            bad(name, 'source/kind/' + kind, [field, 'kind'], kind)
        source = protection_conditions()[name][field]
        for key in source:
            bad(name, 'source/delete/' + key, [field, key], delete=True)
        for key, value in [('issue', 646), ('scopes', ['skip=Review']), ('id', 'B'), ('conditions', dict(doc_only=False, executable_diff=False))]:
            bad(name, 'source/mismatch/' + key, [field, key], value)
        bad(name, 'unmet-conditions', ['actual', 'executable_diff'], True)
    for value in (1, 'missing', 'UNKNOWN'):
        bad('valid-test-skip', 'validation/' + str(value), ['validation', 'exit'], value)
    for key in ('exit', 'scopes'):
        bad('valid-test-skip', 'validation/delete/' + key, ['validation', key], delete=True)
    for value in ([], ['skip=Planning'], ['skip=Test', 'skip=Test']):
        bad('valid-test-skip', 'validation/scopes/' + repr(value), ['validation', 'scopes'], value)
    for field, value in [('base', 'B'), ('head', 'B'), ('qa', 'B'), ('applicable', 'B'), ('head_content', 'opaque B'), ('comparison', 'different'), ('comparison', 'unusable'), ('comparison', 'UNKNOWN'), ('comparison_at', 2), ('comparison_at', 3)]:
        bad('A49-provenance', field + '/' + str(value), [field], value)
    for field in ('base', 'head', 'content'):
        bad('A49-provenance', 'artifact/' + field + '/mismatch', ['artifacts', 'A', field], 'B')
        bad('A49-provenance', 'artifact/' + field + '/missing', ['artifacts', 'A', field], delete=True)
    for field in ('qa', 'head'):
        bad('A49-provenance', 'hash/' + field, ['hashes', field], 'B')
        bad('A49-provenance', 'hash/' + field + '/missing', ['hashes', field], delete=True)


def skip_case(e, stage, adds=False, executable=False, requires=None):
    m = copy.deepcopy(e)
    c = m['protections'][0]['conditions']
    grant = controlled_grant('skip=' + stage)
    grant['conditions'] = dict(doc_only=not executable, executable_diff=executable)
    c.update(scope='skip=' + stage, eligible=['skip=' + stage], source=grant, actual=dict(grant['conditions']))
    c['protected'].update(adds_scenario=adds, executable_diff=executable, doc_only=not executable,
                          requires=requires or ['Discovery', 'Review'])
    return m


def skip_required_checks(e):
    """S593 finding 1: a unanimous skip may not name a stage the protected-work facts require."""
    diagnostic = '593/protection/unanimous-skip'
    cases = [('R1', 'Test', dict(adds=True, requires=['Discovery', 'Test', 'Review'])),
             ('R2', 'Test', dict(requires=['Discovery', 'Test', 'Review'])),
             ('R3', 'Test', dict(adds=True)),
             ('R4', 'Implementation', dict(requires=['Discovery', 'Implementation', 'Review'])),
             ('R5', 'Implementation', dict(executable=True)),
             ('R6', 'Planning', dict(requires=['Discovery', 'Planning', 'Review']))]
    for label, stage, kw in cases:
        fixture('593/unanimous-skip/required/' + label + '/control', skip_case(e, stage), authority_oracle)
        for disposition in ('retained', 'bypass-authorized'):
            m = skip_case(e, stage, **kw)
            m['protections'][0]['disposition'] = disposition
            fixture('593/unanimous-skip/required/' + label + '/' + disposition, m, only(authority_oracle, diagnostic), diagnostic)
    for label, stage, kw in [('C2', 'Test', dict(executable=True)), ('C3', 'Implementation', dict(adds=True)),
                             ('C4', 'Planning', dict(adds=True, executable=True))]:
        fixture('593/unanimous-skip/required/' + label, skip_case(e, stage, **kw), authority_oracle)


def eligible_panel_checks():
    """S593 finding 2: outer disposition follows the represented proposal's supported result."""
    def outer(p, disposition, limitation='supplied evidence only'):
        m = authority_record('eligible-panel')
        m.update(source=None, proposal=p)
        m['result'].update(disposition=disposition)
        if limitation is None:
            del m['result']['limitation']
        else:
            m['result']['limitation'] = limitation
        return m
    refused = proposal('docs-pr')
    refused['delegation']['state'] = 'refused'
    unresolved = proposal('docs-pr')
    panel_state(unresolved, 'incompatible-unresolved')
    referred = {'reserved': proposal('merge-main'), 'refused': refused, 'unresolved': unresolved}
    for name, p in referred.items():
        referral(p)
        fixture('593/eligible-panel/' + name + '-temporary', outer(p, 'temporary'),
                only(authority_oracle, '593/eligible-panel-disposition'), '593/eligible-panel-disposition')
        fixture('593/eligible-panel/' + name + '-referred', outer(p, 'referred'), authority_oracle)
        for label, limitation in [('empty', ''), ('missing', None)]:
            fixture('593/eligible-panel/' + name + '-referred/limitation-' + label, outer(p, 'referred', limitation),
                    only(authority_oracle, '593/evidence-limitation'), '593/evidence-limitation')
    # Nested oracle still reports an inner contradiction; the outer value cannot hide it.
    contradiction = proposal('merge-main')
    fixture('593/eligible-panel/inner-contradiction', outer(contradiction, 'temporary'), authority_oracle, '590/merge-main/referral')
    fixture('593/eligible-panel/temporary-limitation', outer(proposal(), 'temporary'), authority_oracle)


def qa_sweep_checks(ident):
    """QA round-five representatives of existing domains and copy relations."""
    if ident == 589:
        rows = record_inventory()
        expected = [r['id'] for r in rows]
        oracle = lambda value: records_oracle(value, expected, {'supersession': ['A']})
        for i, row in enumerate(rows[1:], 1):
            negative('589/sweep/inventory/' + row['id'] + '/empty', rows, oracle, [i, 'id'], '', '/inventory')
        fixture('589/sweep/expected-id/control', expected, lambda ids: records_oracle(rows, ids))
        negative('589/sweep/expected-id/empty', expected, lambda ids: records_oracle(rows, ids), [0], '', '/inventory')
        negative('589/sweep/supersedes/empty-token', rows, oracle, [5, 'supersedes', 0], '', '/supersession')
        for i, row in enumerate(rows):
            for field in ('risk', 'limit_widening', 'accepted'):
                for label, value in [('empty', ''), ('integer-one', 1), ('integer-zero', 0)]:
                    negative('589/sweep/boolean/' + row['id'] + '/' + field + '/' + label,
                             rows, oracle, [i, field], value, '/' + field)
    elif ident == 590:
        p = proposal()
        for action in ELIGIBLE:
            control = proposal(action)
            i = control['delegation']['scope'].index(action)
            unsupported_proposal('590/sweep/delegation/' + action + '/empty-token', control,
                                 ['delegation', 'scope', i], '', '/delegation')
        for field in ('scope', 'permitted'):
            unsupported_proposal('590/sweep/permission/' + field + '/empty-token', p,
                                 ['permissions', field, 0], '', '/permission')
        prior = changed(p, lambda m: m.update(prior_denials=[dict(action='docs-pr', result='none')]))
        missing('590/sweep/denial/action', prior, proposal_oracle, ['prior_denials', 0, 'action'], '/denied-retry')
        negative('590/sweep/denial/result/missing', prior, proposal_oracle,
                 ['prior_denials', 0, 'result'], None, '/denied-retry', True)
        unsupported_proposal('590/sweep/release/source/human/empty', release_proposal(),
                             ['release_authority', 'source', 'human'], '', '/release-authority')
    elif ident == 591:
        e = clean_evidence()
        for i, recipient in enumerate(('Product', 'Architect')):
            negative('591/sweep/' + recipient + '/recipient/empty', e, floor_oracle,
                     ['briefs', i, 'recipient'], '', '/brief')
            negative('591/sweep/' + recipient + '/inheritance/empty-token', e, floor_oracle,
                     ['briefs', i, 'inherits'], [''], '/inherited-dispatch')
        for i, session in enumerate(e['reconciliation']['used_sessions']):
            negative('591/sweep/used-session/' + session + '/empty', e, floor_oracle,
                     ['reconciliation', 'used_sessions', i], '', 'separate-sessions/reconciliation')
        for field in ('command', 'inputs'):
            negative('591/sweep/experiment/' + field + '/empty-token', e, floor_oracle,
                     ['experiments', 0, field, 0], '', 'experiment/' + field)
            aligned = copy.deepcopy(e)
            aligned['experiments'][0][field][0] = ''
            aligned['experiments'][0]['attempts'][0][field][0] = ''
            fixture('591/sweep/experiment/' + field + '/empty-token/aligned', aligned, floor_oracle,
                    'experiment/' + field)
            fixture('591/sweep/experiment/' + field + '/aligned/control', e, floor_oracle)
        for field in ('command', 'inputs'):
            negative('591/sweep/attempt/' + field + '/empty-token', e, floor_oracle,
                     ['experiments', 0, 'attempts', 0, field, 0], '', 'experiment/capture')
    elif ident == 592:
        rows = record_inventory()
        req = disclosure_request(rows)
        oracle = lambda value: disclosure_oracle(rows, value)
        for i, row in enumerate(req['rows']):
            for field in ('id', 'issue', 'home', 'link', 'pr_link', 'resolution'):
                negative('592/sweep/' + row['id'] + '/copy/' + field + '/empty', req, oracle,
                         ['rows', i, field], '', row['id'] + '/inventory/order/fields' if field == 'id' else row['id'] + '/copy/' + field)
            for field in ('positions', 'evidence', 'models', 'dissent'):
                for j, contribution in enumerate(row[field]):
                    negative('592/sweep/' + row['id'] + '/' + field + '/' + contribution['member'] + '/empty',
                             req, oracle, ['rows', i, field, j, 'member'], '', row['id'] + '/copy/' + field)
            for j, prior in enumerate(row['supersedes']):
                negative('592/sweep/' + row['id'] + '/supersedes/' + prior + '/empty', req, oracle,
                         ['rows', i, 'supersedes', j], '', row['id'] + '/copy/supersedes')
        earlier = [r['id'] for r in rows]
        carried = disclosure_request(rows, round_no=2, earlier=earlier)
        carry_oracle = lambda value: disclosure_oracle(rows, value, round_no=2, earlier=earlier)
        negative('592/sweep/earlier-unaccepted/missing', carried, carry_oracle,
                 ['earlier_unaccepted'], None, '592/inventory/carryforward', True)
        for i, token in enumerate(earlier):
            negative('592/sweep/earlier-unaccepted/' + token + '/empty', carried, carry_oracle,
                     ['earlier_unaccepted', i], '', '592/inventory/carryforward')
        row = record('A')
        row.update(accepted=True, acceptance_evidence=explicit_acceptance(row))
        req = disclosure_request([row])
        acceptance_oracle = lambda value: disclosure_oracle([row], value)
        malformed = copy.deepcopy(row)
        malformed['acceptance_evidence']['decisions'][0] = ''
        fixture('592/sweep/acceptance/decision-token/empty/control', req, acceptance_oracle)
        fixture('592/sweep/acceptance/decision-token/empty', disclosure_request([malformed]),
                lambda value: disclosure_oracle([malformed], value), '592/A/acceptance-evidence/decision')
        negative('592/sweep/acceptance/words-copy/empty', req, acceptance_oracle,
                 ['rows', 0, 'acceptance_evidence', 'words'], '', '592/A/copy/acceptance_evidence')
    elif ident == 593:
        e = authority_record()
        authority_negative('593/sweep/source/applicable-source/empty', e,
                           ['source', 'applicable_source'], '', '593/source/referral')
        for i, scope in enumerate(e['source']['scopes']):
            authority_negative('593/sweep/source/scope/' + scope + '/empty', e,
                               ['source', 'scopes', i], '', '593/source/referral')
        for owner, path in [('source', ['source', 'conditions']), ('actual', ['conditions'])]:
            for field in ('doc_only', 'executable_diff'):
                for label, value in [('missing', None), ('empty', ''), ('null', None), ('one', 1), ('zero', 0), ('UNKNOWN', 'UNKNOWN')]:
                    authority_negative('593/sweep/' + owner + '/boolean/' + field + '/' + label, e,
                                       path + [field], value, '593/source/referral', label == 'missing')
        authority_negative('593/sweep/posting/human/empty', e, ['posting', 'human'], '', '593/human-identity')
        for path, diagnostic in [(['applied_scope'], '593/source/referral'),
                                 (['posting', 'validation', 'scopes'], '593/validation'),
                                 (['posting', 'round_trip', 'scopes'], '593/round-trip')]:
            for i, scope in enumerate(at(e, path)):
                authority_negative('593/sweep/scope/' + '/'.join(path) + '/' + scope + '/empty', e,
                                   path + [i], '', diagnostic)
        authority_negative('593/sweep/posting/reason/empty', e, ['posting', 'reason'], '', '593/human-words')
        authority_negative('593/sweep/posting/issue/empty', e, ['posting', 'issue'], '', '593/source/referral')
        base = ['protections', 0, 'conditions']
        diagnostic = '593/protection/unanimous-skip'
        for field in ('id', 'human', 'issue', 'link', 'applicable_source'):
            missing('593/sweep/unanimous/source/' + field, e, authority_oracle, base + ['source', field], diagnostic)
        for owner, path, fields in [('source', ['source', 'conditions'], ('doc_only', 'executable_diff')),
                                    ('actual', ['actual'], ('doc_only', 'executable_diff')),
                                    ('protected', ['protected'], ('adds_scenario', 'executable_diff', 'doc_only'))]:
            for field in fields:
                for label, value in [('missing', None), ('empty', ''), ('null', None), ('one', 1), ('zero', 0), ('UNKNOWN', 'UNKNOWN')]:
                    negative('593/sweep/unanimous/' + owner + '/' + field + '/' + label, e, authority_oracle,
                             base + path + [field], value, diagnostic, label == 'missing')
        negative('593/sweep/unanimous/eligibility/empty-token', e, authority_oracle,
                 base + ['eligible', 0], '', diagnostic)
        negative('593/sweep/unanimous/source/scope/empty-token', e, authority_oracle,
                 base + ['source', 'scopes', 0], '', diagnostic)
        for field in ('adds_scenario', 'executable_diff', 'doc_only'):
            for label, value in [('empty', ''), ('null', None), ('one', 1), ('zero', 0)]:
                negative('593/sweep/protected-work/' + field + '/' + label, e, authority_oracle,
                         ['protections', 1, 'conditions', field], value, '593/protection/protected-work')
        negative('593/sweep/fresh-review/inheritance/empty-token', e, authority_oracle,
                 ['protections', 4, 'conditions', 'inherits'], [''], '593/protection/fresh-review')
        base = ['protections', 6, 'conditions']
        diagnostic = '593/protection/valid-test-skip'
        for field in ('id', 'human', 'issue', 'link', 'applicable_source'):
            negative('593/sweep/test-skip/source/' + field + '/empty', e, authority_oracle,
                     base + ['human_source', field], '', diagnostic)
        for owner, path in [('source', ['human_source', 'conditions']), ('actual', ['actual'])]:
            for field in ('doc_only', 'executable_diff'):
                for label, value in [('missing', None), ('empty', ''), ('null', None), ('one', 1), ('zero', 0), ('UNKNOWN', 'UNKNOWN')]:
                    negative('593/sweep/test-skip/' + owner + '/' + field + '/' + label, e, authority_oracle,
                             base + path + [field], value, diagnostic, label == 'missing')
        for path in (['human_source', 'scopes', 0], ['validation', 'scopes', 0]):
            negative('593/sweep/test-skip/' + '/'.join(map(str, path)) + '/empty', e, authority_oracle,
                     base + path, '', diagnostic)
        negative('593/sweep/test-skip/scope/empty', e, authority_oracle, base + ['scope'], '', diagnostic)
        for field in ('base', 'head'):
            negative('593/sweep/A49/artifact/' + field + '/empty', e, authority_oracle,
                     ['protections', 7, 'conditions', 'artifacts', 'A', field], '', '593/protection/A49-provenance')
        base = ['protections', 8, 'conditions']
        diagnostic = '593/protection/per-item-human-authority'
        for field in ('id', 'human', 'issue', 'link', 'applicable_source'):
            negative('593/sweep/per-item/source/' + field + '/empty', e, authority_oracle,
                     base + ['source', field], '', diagnostic)
        for owner, path in [('source', ['source', 'conditions']), ('actual', ['actual'])]:
            for field in ('doc_only', 'executable_diff'):
                for label, value in [('missing', None), ('empty', ''), ('null', None), ('one', 1), ('zero', 0), ('UNKNOWN', 'UNKNOWN')]:
                    negative('593/sweep/per-item/' + owner + '/' + field + '/' + label, e, authority_oracle,
                             base + path + [field], value, diagnostic, label == 'missing')
        negative('593/sweep/per-item/source/scope/empty-token', e, authority_oracle,
                 base + ['source', 'scopes', 0], '', diagnostic)
        negative('593/sweep/per-item/scope/empty', e, authority_oracle, base + ['scope'], '', diagnostic)


def remaining_manifest_checks(ident):
    """Single-field representatives and relation controls, without new products."""
    if ident == 589:
        rows = record_inventory()
        oracle = lambda value: records_oracle(value, [r['id'] for r in rows], {'supersession': ['A']})
        for i, r in enumerate(rows):
            for field in ('risk', 'limit_widening', 'accepted'):
                negative('589/boolean/' + r['id'] + '/' + field, rows, oracle, [i, field], 'UNKNOWN', '/' + field)
        for field in ('artifacts',):
            negative('589/opaque/' + field + '/empty-member', rows, oracle, [0, field], [''], '/' + field)
            fixture('589/opaque/' + field + '/B', changed(rows, lambda m: m[0].update(artifacts=['opaque B'])), oracle)
        for field in ('member', 'position'):
            majority = [record('B', '2-1')]
            missing('589/dissent/pair/' + field, majority, records_oracle, [0, 'dissent', 0, field], '/dissent')
    elif ident == 590:
        p = proposal()
        for field in ('scope', 'words'):
            unsupported_proposal('590/delegation/delete/' + field, p, ['delegation', field], None, '/delegation', True)
        for field in ('scope', 'permitted'):
            m = copy.deepcopy(p)
            m['permissions'][field] = ['docs-pr', 'B']
            # An unrelated permission cannot replace the required action. Extra
            # independently granted action IDs do not expand panel execution.
            fixture('590/permission/' + field + '/extra-control', m, proposal_oracle)
        p = release_proposal()
        p['prior_denials'] = [dict(action='B', result='denied')]
        fixture('590/denial/different-action', p, proposal_oracle)
        negative('590/denial/matching-release-action', p, proposal_oracle, ['prior_denials', 0, 'action'],
                 'merge-work-item-to-release', '/denied-retry')
        for field in ('id', 'words', 'base', 'action'):
            unsupported_proposal('590/release/source/empty/' + field, p,
                                 ['release_authority', 'source', field], '', '/release-authority')
        m = release_proposal()
        m['release_authority']['base'] = m['release_authority']['source']['base'] = 'release/B'
        m['release_authority']['source']['id'] = 'B'
        fixture('590/release/matching-B', m, proposal_oracle)
    elif ident == 591:
        e = clean_evidence()
        for i, recipient in enumerate(('Product', 'Architect')):
            missing('591/' + recipient + '/session-token', e, floor_oracle, ['briefs', i, 'session'], '/inherited-dispatch')
        m = copy.deepcopy(e)
        for i, token in enumerate(('A', 'B')):
            m['briefs'][i]['session'] = m['returns'][i]['session'] = token
        m['reconciliation']['used_sessions'] = ['A', 'B']
        fixture('591/matching-session-tokens', m, floor_oracle)
        m = copy.deepcopy(e)
        m['experiments'][0].update(id='B', inputs=['B'])
        m['experiments'][0]['attempts'][0].update(id='B', inputs=['B'])
        fixture('591/experiment/matching-B', m, floor_oracle)
        negative('591/experiment/input-copy-mismatch', e, floor_oracle, ['experiments', 0, 'attempts', 0, 'inputs'], ['B'], 'experiment/capture')
        negative('591/experiment/command-copy-mismatch', e, floor_oracle, ['experiments', 0, 'attempts', 0, 'command'], ['opaque B'], 'experiment/capture')
        fixture('591/complete-unresolved-control', changed(e, lambda m: m['reconciliation'].update(disposition='unresolved')), floor_oracle)
    elif ident == 592:
        for scrutiny in ('individual', 'group'):
            row = record('A')
            row.update(accepted=True, acceptance_evidence=explicit_acceptance(row))
            row['acceptance_evidence']['scrutiny'] = scrutiny
            fixture('592/unanimous-scrutiny/' + scrutiny, disclosure_request([row]), lambda req: disclosure_oracle([row], req))
        a, b = record('A'), record('B')
        for row in (a, b):
            row.update(accepted=True, acceptance_evidence=explicit_acceptance(row))
            row['acceptance_evidence']['decisions'] = ['A', 'B']
        rows = [a, b]
        for i, row in enumerate(rows):
            for j, token in enumerate(('A', 'B')):
                for mode, value in [('missing', ['B' if token == 'A' else 'A']), ('duplicate', ['A', 'B', token]), ('wrong', ['A', 'B'][:j] + ['UNKNOWN'] + ['A', 'B'][j + 1:])]:
                    m = copy.deepcopy(rows)
                    m[i]['acceptance_evidence']['decisions'] = value
                    # Removing the other decision narrows this row's grant and
                    # remains applicable; removing its own decision does not.
                    fixture('592/group-decisions/' + row['id'] + '/' + token + '/' + mode,
                            disclosure_request(m), lambda req: disclosure_oracle(m, req),
                            None if mode == 'missing' and token != row['id'] else '/acceptance-evidence/decision')
        m = copy.deepcopy(rows)
        for row in m:
            row['acceptance_evidence']['source'] = row['acceptance_evidence']['applicable_source'] = 'B'
        fixture('592/group-source/matching-B', disclosure_request(m), lambda req: disclosure_oracle(m, req))
    elif ident == 593:
        e = authority_record()
        for i, name in enumerate(PROTECTIONS):
            negative('593/protection/' + name + '/UNKNOWN-disposition', e, authority_oracle,
                     ['protections', i, 'disposition'], 'UNKNOWN', '593/protection/' + name)
        for field in ('doc_only', 'executable_diff'):
            for value in ('UNKNOWN', 1):
                authority_negative('593/source/boolean/' + field + '/' + str(value), e,
                                   ['source', 'conditions', field], value, '593/source/referral')
        for name, i in [('valid-test-skip', 6), ('per-item-human-authority', 8)]:
            negative('593/' + name + '/wrong-scope', e, authority_oracle,
                     ['protections', i, 'conditions', 'scope'], 'skip=Review', '593/protection/' + name)
        m = copy.deepcopy(e)
        m['source']['human'] = m['posting']['human'] = 'B'
        m['source']['id'] = m['source']['applicable_source'] = m['source']['link'] = 'B'
        fixture('593/matching-human-source-B', m, authority_oracle)
        m = copy.deepcopy(e)
        m['protections'][4]['conditions'].update(reviewer_session='B', previous_session='A')
        fixture('593/fresh-review/matching-B-A', m, authority_oracle)
        for i, fields in [(2, ('evidence', 'action')), (3, ('decision', 'waiver', 'commit', 'pr'))]:
            m = copy.deepcopy(e)
            for field in fields:
                m['protections'][i]['conditions'][field] = 'B'
            fixture('593/order-identities/B/' + str(i), m, authority_oracle)
        for path in (['protections', 7, 'conditions', 'base'], ['protections', 7, 'conditions', 'head'],
                     ['protections', 7, 'conditions', 'qa'], ['protections', 7, 'conditions', 'applicable'],
                     ['protections', 7, 'conditions', 'hashes', 'qa'], ['protections', 7, 'conditions', 'hashes', 'head'],
                     ['protections', 7, 'conditions', 'artifacts', 'A', 'content']):
            negative('593/provenance/empty/' + '/'.join(map(str, path)), e, authority_oracle, path, '', '593/protection/A49-provenance')


# Oracles below interpret only this finite structured vocabulary. Source pins are
# the sole text exceptions; all other prose has presence/copy checks only.

def present(value):
    return value is not None and value != '' and value != [] and value != {}


def unique(values):
    return isinstance(values, list) and len(values) == len({repr(v) for v in values})


def exact_members(values, expected):
    return unique(values) and set(values) == set(expected)


def before(left, right):
    return type(left) in (int, float) and type(right) in (int, float) and left < right


def records_oracle(items, expected=None, supersessions=None):
    problems = []
    ids = [r.get('id') for r in items]
    if expected is not None:
        for ident in set(expected) | set(ids):
            if not ident or ids.count(ident) != 1 or ident not in expected:
                problems.append('589/' + str(ident) + '/inventory')
    if not unique(ids):
        problems.append('589/duplicate-decision-ID/inventory')
    required = ('id', 'issue', 'label', 'home', 'link', 'pr_link', 'question', 'scope', 'artifacts',
                'positions', 'evidence', 'models', 'vote', 'dissent', 'outcome', 'rationale', 'reservation',
                'risk', 'limit_widening', 'resolution', 'supersedes', 'accepted')
    for r in items:
        name = '589/' + str(r.get('id', '?'))
        for field in required:
            if field not in r or (not present(r[field]) and field not in ('vote', 'dissent', 'supersedes')):
                problems.append(name + '/' + field)
        if r.get('label') != 'temporary, panel decision':
            problems.append(name + '/label')
        if r.get('home') != 'issue:' + str(r.get('issue')):
            problems.append(name + '/issue-home')
        if (r.get('issue') != '645' or not present(r.get('id'))
                or r.get('link') != 'issue:645#' + str(r.get('id'))):
            problems.append(name + '/issue-home-link')
        if not present(r.get('pr_link')) or r.get('pr_link') != r.get('link'):
            problems.append(name + '/pr-link')
        for field, content, label in [('positions', ('position',), 'position'),
                                      ('evidence', ('source',), 'evidence'), ('models', ('model', 'reasoning'), 'model')]:
            rows = r.get(field, [])
            names = [row.get('member') for row in rows]
            if not unique(names):
                problems.append(name + '/duplicate-participant/' + label)
            if any(n not in MEMBERS for n in names):
                problems.append(name + '/unknown-participant/' + label)
            for member in MEMBERS:
                contributions = [row for row in rows if row.get('member') == member]
                if len(contributions) != 1 or any(not present(contributions[0].get(c)) for c in content):
                    problems.append(name + '/' + member + '/' + label)
            if field == 'positions' and any(row.get('position') not in ('adopt', 'defer', 'reject') for row in rows):
                problems.append(name + '/position')
        positions = [p.get('position') for p in r.get('positions', [])]
        tally = max((positions.count(p) for p in positions), default=0)
        state, vote = r.get('outcome'), r.get('vote')
        if state not in ('resolved', 'unresolved', 'escalated'):
            problems.append(name + '/outcome')
        if state == 'resolved':
            if len(positions) != 3 or tally < 2:
                problems.append(name + '/outcome')
            if vote != ('3-0' if tally == 3 else '2-1'):
                problems.append(name + '/vote')
            dissent = [p for p in r.get('positions', []) if positions.count(p.get('position')) == 1] if tally == 2 else []
            if r.get('dissent') != dissent:
                problems.append(name + '/dissent')
        elif vote is not None:
            problems.append(name + '/fabricated-vote')
        for field in ('risk', 'limit_widening', 'accepted'):
            if type(r.get(field)) is not bool:
                problems.append(name + '/' + field)
        if r.get('reservation') not in ('pending', 'referred', 'none'):
            problems.append(name + '/reservation')
        if not isinstance(r.get('artifacts'), list) or not all(present(a) for a in r.get('artifacts', [])):
            problems.append(name + '/artifacts')
        supersedes = r.get('supersedes', [])
        if not unique(supersedes):
            problems.append(name + '/supersession')
        if supersessions is not None and supersedes != supersessions.get(r.get('id'), []):
            problems.append(name + '/supersession')
        for prior in supersedes:
            old = next((x for x in items if x.get('id') == prior), {})
            if not old or prior == r.get('id'):
                problems.append(name + '/supersession')
            if not old.get('resolution') or not r.get('resolution'):
                problems.append(name + '/resolution')
    return problems


def permission_supports(permission, action):
    return (present(permission.get('source')) and permission.get('role') == 'orchestrator'
            and unique(permission.get('scope')) and action in permission.get('scope', [])
            and unique(permission.get('permitted')) and action in permission.get('permitted', []))


def proposal_oracle(p):
    action = p.get('action', 'UNKNOWN')
    prefix = '590/' + action + '/'
    problems = records_oracle(p.get('panel', []))
    if action in TARGETED:
        # The structured target selects the token; proposal prose is never read.
        if p.get('target') not in TARGETS:
            problems.append(prefix + 'target')
        elif p['target'] == 'panel-rules':
            action = 'edit-panel-rules'
            prefix = '590/' + action + '/'
    if len(p.get('panel', [])) != 1:
        problems.append(prefix + 'panel-record')
    delegation = p.get('delegation') or {}
    delegated = (delegation.get('state') == 'accepted' and present(delegation.get('source'))
                 and present(delegation.get('words')) and unique(delegation.get('scope'))
                 and action in delegation.get('scope', []))
    permission = p.get('permissions') or {}
    permitted = permission_supports(permission, action)
    release = p.get('release_authority') or {}
    source = release.get('source') if isinstance(release.get('source'), dict) else {}
    release_defects = []
    if not (action == 'merge-work-item-to-release' and source.get('state') == 'accepted'
            and present(source.get('id')) and source.get('kind') == 'human' and present(source.get('human'))
            and source.get('action') == action and present(source.get('words'))):
        release_defects.append('source')
    if not (isinstance(release.get('base'), str) and release['base'].startswith('release/')
            and source.get('base') == release['base']):
        release_defects.append('base')
    for field, expected in [('ci', 'passed'), ('tests', 'passed'), ('review', 'approved')]:
        if release.get(field) != expected:
            release_defects.append(field)
    if not permitted:
        release_defects.append('permission')
    release_ok = not release_defects
    if delegation and delegation.get('state') not in SOURCE_STATES and 'state' in delegation:
        problems.append(prefix + 'delegation')
    if permission.get('role') not in MEMBERS and 'role' in permission and present(permission.get('role')):
        problems.append(prefix + 'permission')
    if source and source.get('state') not in SOURCE_STATES and 'state' in source:
        problems.append(prefix + 'release-authority/source')
    for field, domain in [('ci', ('passed', 'failed', 'missing')), ('tests', ('passed', 'failed', 'missing')), ('review', ('approved', 'changes-requested', 'missing'))]:
        if field in release and release[field] not in domain:
            problems.append(prefix + 'release-authority/' + field)
    result = p.get('result', {})
    route = result.get('route')
    if route == 'release-authority':
        problems += [prefix + 'release-authority/' + f for f in release_defects]
        if result.get('disposition') != 'authorized-existing-route':
            problems.append(prefix + 'disposition')
    elif action in ELIGIBLE and delegated and permitted:
        panel = p.get('panel', [])
        settled = len(panel) == 1 and panel[0].get('outcome') == 'resolved' and not records_oracle(panel)
        if settled:
            if route != 'panel' or result.get('disposition') != 'temporary':
                problems.append(prefix + 'disposition')
        elif route != 'maintainer' or result.get('disposition') != 'referred':
            problems.append(prefix + 'unresolved-panel-settlement')
    elif route != 'maintainer' or result.get('disposition') != 'referred':
        problems.append(prefix + ('referral' if action not in ELIGIBLE else 'delegation' if not delegated else 'permission'))
    if result.get('acceptance') != 'pending':
        problems.append(prefix + 'inferred-acceptance')
    for denial in p.get('prior_denials', []):
        if denial.get('result') not in ('denied', 'none') or not present(denial.get('action')):
            problems.append(prefix + 'denied-retry')
    for attempt in result.get('attempts', []):
        if any(d.get('result') == 'denied' and d.get('action') == attempt.get('action') for d in p.get('prior_denials', [])):
            problems.append(prefix + 'denied-retry')
        if not (release_ok and route == 'release-authority' and attempt.get('authority') == 'release-authority'
                and attempt.get('action') == action):
            problems.append(prefix + 'attempt')
    return problems


def floor_oracle(e):
    from datetime import date
    problems = []
    for subject in ('author',) + MEMBERS:
        model = e.get(subject, {})
        for field in ('model', 'variant', 'entry', 'date', 'score'):
            if not present(model.get(field)):
                problems.append('591/' + subject + '/' + field + '/missing')
        entry = INDEX.get(model.get('entry'))
        if entry is None:
            problems.append('591/' + subject + '/entry/unknown')
        else:
            for field, expected in zip(('model', 'variant', 'score'), entry):
                if model.get(field) != expected:
                    problems.append('591/' + subject + '/' + field + '/captured-entry-mismatch')
        try:
            date.fromisoformat(model.get('date', ''))
        except (TypeError, ValueError):
            problems.append('591/' + subject + '/date')
        score, author = model.get('score'), e.get('author', {}).get('score')
        if subject != 'author' and (type(score) not in (int, float) or type(author) not in (int, float) or score < author):
            problems.append('591/' + subject + '/below-author')
    briefs, returns, reconcile = e.get('briefs', []), e.get('returns', []), e.get('reconciliation', {})
    if len(briefs) != 2 or any(b.get('recipient') not in ('Product', 'Architect') for b in briefs):
        problems.append('591/brief')
    if len(returns) != 2 or any(r.get('member') not in ('Product', 'Architect') for r in returns):
        problems.append('591/return')
    sessions = []
    for recipient in ('Product', 'Architect'):
        supplied = [b for b in briefs if b.get('recipient') == recipient]
        if len(supplied) != 1:
            problems.append('591/' + recipient + '/brief')
            continue
        b = supplied[0]
        sessions.append(b.get('session'))
        if not present(b.get('session')) or b.get('inherits') != []:
            problems.append('591/' + recipient + '/inherited-dispatch')
        payload = b.get('payload', [])
        for tag in REQUIRED_TAGS:
            parts = [p for p in payload if p.get('kind') == tag]
            if len(parts) != 1 or not present(parts[0].get('text')):
                problems.append('591/' + recipient + '/brief/' + tag)
        for part in payload:
            tag = part.get('kind')
            if tag in PROHIBITED_TAGS:
                problems.append('591/' + recipient + '/prohibited-tag/' + tag)
            elif tag not in REQUIRED_TAGS:
                problems.append('591/' + recipient + '/brief/unknown-tag')
        procedure = ' '.join(p.get('text', '') for p in payload if p.get('kind') == 'procedure')
        if any(norm(c) not in norm(procedure) for c in CLAUSES[591]):
            problems.append('591/' + recipient + '/canonical-procedure')
        supplied_returns = [r for r in returns if r.get('member') == recipient]
        if (len(supplied_returns) != 1 or not present(supplied_returns[0].get('position'))
                or not present(supplied_returns[0].get('evidence')) or supplied_returns[0].get('session') != b.get('session')):
            problems.append('591/' + recipient + '/return')
        if (len(supplied_returns) != 1 or not before(b.get('at'), supplied_returns[0].get('at'))
                or not before(supplied_returns[0].get('at'), reconcile.get('at'))):
            problems.append('591/' + recipient + '/return-order')
    if len(sessions) != 2 or not unique(sessions) or reconcile.get('used_sessions') != sessions:
        problems.append('591/separate-sessions/reconciliation')
    own = e.get('own_position', {})
    if own.get('member') != 'orchestrator' or not present(own.get('position')) or not before(own.get('at'), reconcile.get('at')):
        problems.append('591/orchestrator-position-before-reconciliation')
    if reconcile.get('disposition') not in ('settled', 'unresolved'):
        problems.append('591/reconciliation/disposition')
    experiments = e.get('experiments', [])
    if not experiments:
        problems.append('591/experiment/missing')
    for exp in experiments:
        missing_fields = [f for f in ('id', 'command', 'inputs', 'result', 'limits')
                          if not present(exp.get(f)) or (f in ('command', 'inputs')
                          and isinstance(exp.get(f), list) and any(not present(token) for token in exp[f]))]
        if missing_fields:
            if exp.get('disposition') != 'incomplete' or exp.get('attempts') != [] or reconcile.get('disposition') != 'unresolved':
                problems += ['591/experiment/' + f for f in missing_fields]
                problems.append('591/experiment/incomplete')
            if reconcile.get('disposition') == 'settled':
                problems.append('591/reconciliation/unsupported-settlement')
            continue
        permissions = exp.get('permissions')
        if isinstance(permissions, list) and (not unique(permissions) or any(v not in ('local-read', 'none') for v in permissions)):
            problems.append('591/experiment/permission')
        kind = exp.get('kind')
        if kind not in ('local-read', 'local-write', 'network-mutation', 'denied-retry'):
            problems.append('591/experiment/kind')
        prior = exp.get('prior', [])
        malformed_prior = any(not present(p.get('id')) for p in prior)
        if malformed_prior:
            problems.append('591/experiment/denied-retry')
        denied = malformed_prior or any(p.get('id') == exp.get('id') and p.get('result') == 'denied' for p in prior)
        attempts = exp.get('attempts')
        if kind in ('local-write', 'network-mutation', 'denied-retry') or denied:
            if exp.get('disposition') != 'refused' or attempts != []:
                problems.append('591/experiment/' + ('denied-retry' if denied else kind))
        elif exp.get('permissions') != ['local-read']:
            if exp.get('disposition') != 'refused' or attempts != []:
                problems.append('591/experiment/permission')
        elif kind == 'local-read':
            capture = dict(id=exp['id'], command=exp['command'], inputs=exp['inputs'])
            if attempts != [capture]:
                problems.append('591/experiment/capture')
            if exp.get('disposition') != 'accepted':
                problems.append('591/experiment/disposition')
    if problems and reconcile.get('disposition') == 'settled':
        problems.append('591/reconciliation/unsupported-settlement')
    return problems


def grant_supports(source, issue, scopes, actual, doc_only_grant=True):
    # Supplied state/applicability facts only. No grammar establishes human intent.
    return (isinstance(source, dict) and source.get('state') == 'accepted' and source.get('kind') == 'human'
            and present(source.get('human')) and issue == source.get('issue') == 645
            and present(source.get('id')) and source['id'] == source.get('applicable_source') and present(source.get('link'))
            and present(source.get('words')) and unique(scopes) and bool(scopes)
            and set(scopes) <= {'skip=Planning', 'skip=Test', 'skip=Implementation'}
            and source.get('scopes') == scopes
            and source.get('conditions') == actual
            and (actual == dict(doc_only=True, executable_diff=False) if doc_only_grant
                 else isinstance(actual, dict) and set(actual) == {'doc_only', 'executable_diff'})
            and all(type(v) is bool for v in actual.values())
            and all(type(v) is bool for v in source['conditions'].values()))


def required_stages(c):
    """Stages the represented protected-work facts and the claimed requirement both demand."""
    required = {'Discovery', 'Review'} | set(c.get('requires') or [])
    if c.get('adds_scenario') is True:
        required.add('Test')
    if c.get('executable_diff') is True:
        required.add('Implementation')
    return required


def protection_supported(name, c):
    if not isinstance(c, dict):
        return False
    if name == 'unanimous-skip':
        scope = c.get('scope')
        return (scope in ('skip=Planning', 'skip=Test', 'skip=Implementation')
                and c.get('votes') == ['skip'] * 3 and c.get('vote') == c.get('required_vote') == '3-0'
                and unique(c.get('eligible')) and scope in c.get('eligible', [])
                and grant_supports(c.get('source'), 645, [scope], c.get('actual'), doc_only_grant=False)
                and protection_supported('protected-work', c.get('protected'))
                and scope[len('skip='):] not in required_stages(c.get('protected'))
                and c.get('protected', {}).get('executable_diff') == c.get('actual', {}).get('executable_diff')
                and c.get('protected', {}).get('doc_only') == c.get('actual', {}).get('doc_only'))
    if name == 'protected-work':
        if any(type(c.get(f)) is not bool for f in ('adds_scenario', 'executable_diff', 'doc_only')):
            return False
        required, selected = c.get('requires'), c.get('selected')
        if not unique(required) or not unique(selected) or not set(required) <= set(STAGES) or not set(selected) <= set(STAGES):
            return False
        return required_stages(c) <= set(selected)
    if name == 'evidence-before-action':
        return all(present(c.get(f)) for f in ('evidence', 'action')) and before(c.get('evidence_at'), c.get('action_at'))
    if name == 'advance-ordering':
        return (all(present(c.get(f)) for f in ('decision', 'waiver', 'commit', 'pr'))
                and all(before(c.get(l + '_at'), c.get(r + '_at')) for l in ('decision', 'waiver') for r in ('commit', 'pr')))
    if name == 'fresh-review':
        return (present(c.get('reviewer_session')) and present(c.get('previous_session'))
                and c['reviewer_session'] != c['previous_session'] and c.get('inherits') == [])
    if name == 'review-depth':
        ranks = {'quick': 0, 'thorough': 1}
        return c.get('required') in ranks and c.get('selected') in ranks and ranks[c['selected']] >= ranks[c['required']]
    if name == 'valid-test-skip':
        validation = c.get('validation') or {}
        return (c.get('scope') == 'skip=Test' and grant_supports(c.get('human_source'), 645, ['skip=Test'], c.get('actual'))
                and type(validation.get('exit')) is int and validation['exit'] == 0 and validation.get('scopes') == ['skip=Test'])
    if name == 'per-item-human-authority':
        return c.get('scope') == 'skip=Planning' and grant_supports(c.get('source'), c.get('issue'), ['skip=Planning'], c.get('actual'))
    if name == 'A49-provenance':
        artifact = (c.get('artifacts') or {}).get(c.get('qa'), {})
        hashes = c.get('hashes') or {}
        return (all(present(c.get(f)) for f in ('base', 'head', 'qa', 'applicable')) and c['qa'] == c['applicable']
                and artifact.get('base') == c['base'] and artifact.get('head') == c['head']
                and present(artifact.get('content')) and present(c.get('head_content'))
                and hashlib.sha256(artifact['content'].encode()).hexdigest() == hashes.get('qa')
                and hashlib.sha256(c['head_content'].encode()).hexdigest() == hashes.get('head')
                and artifact['content'] == c['head_content'] and c.get('comparison') == 'match'
                and before(c.get('comparison_at'), c.get('review_at')))
    return False


def authority_oracle(e):
    problems = records_oracle(e.get('panel', []))
    source, posting, result = e.get('source') or {}, e.get('posting', {}), e.get('result', {})
    defects = []
    if ((source and 'state' in source and source['state'] not in SOURCE_STATES)
            or (source and 'kind' in source and source['kind'] not in ('human', 'panel', 'copied-approval', 'structural-check'))):
        problems.append('593/source/referral')
    if not grant_supports(source, posting.get('issue'), e.get('applied_scope'), e.get('conditions')):
        defects.append('593/source/referral')
    if posting.get('role') != 'orchestrator':
        defects.append('593/posting-role')
    if not present(posting.get('human')) or posting.get('human') != source.get('human'):
        defects.append('593/human-identity')
    if not present(posting.get('reason')) or posting.get('reason') != source.get('words'):
        defects.append('593/human-words')
    validation = posting.get('validation') or {}
    if type(validation.get('exit')) is not int or validation['exit'] != 0 or validation.get('scopes') != e.get('applied_scope'):
        defects.append('593/validation')
    trip = posting.get('round_trip') or {}
    if (not present(trip.get('words')) or trip.get('words') != posting.get('reason')
            or not unique(trip.get('scopes')) or trip.get('scopes') != e.get('applied_scope')):
        defects.append('593/round-trip')
    if not re.search(r'\bCloses #' + str(posting.get('issue', '?')) + r'\b', posting.get('pr_body', '')):
        defects.append('593/Closes-issue-link')
    protections = e.get('protections', [])
    for name in PROTECTIONS:
        rows = [p for p in protections if p.get('name') == name]
        if (len(rows) != 1 or not present(rows[0].get('evidence')) or not present(rows[0].get('work'))
                or rows[0].get('disposition') != 'retained' or not protection_supported(name, rows[0].get('conditions'))):
            problems.append('593/protection/' + name)
    if any(p.get('name') not in PROTECTIONS for p in protections):
        problems.append('593/protection/UNKNOWN')
    if e.get('kind') == 'stage-selection' and not exact_members(e.get('selection'), STAGES):
        problems.append('593/stage-selection')
    if e.get('kind') == 'eligible-panel':
        proposal_problems = proposal_oracle(e.get('proposal', {}))
        problems += proposal_problems
        # The outer disposition follows the represented proposal's supported result.
        supported = not proposal_problems and (e.get('proposal') or {}).get('result', {}).get('disposition') == 'temporary'
        if result.get('disposition') != ('temporary' if supported else 'referred'):
            problems.append('593/eligible-panel-disposition')
        may_post = False
    else:
        may_post = not defects and not problems
        if defects:
            if result.get('disposition') != 'referred':
                problems += defects
        elif result.get('disposition') != 'authorized-route':
            problems.append('593/authorized-route-disposition')
    if not present(result.get('limitation')):
        problems.append('593/evidence-limitation')
    for claim in result.get('claims', []):
        if claim != 'supplied-evidence-only':
            problems.append('593/claim/' + claim)
    for attempt in result.get('attempts', []):
        if attempt.startswith('bypass'):
            problems.append('593/bypass-attempt')
        elif attempt != 'post-override' or not may_post:
            problems.append('593/posting-attempt')
    return problems


def disclosure_oracle(inventory, request, consumer=645, round_no=1, earlier=None):
    problems = records_oracle(inventory)
    for field, expected in [('source', 'issue-comments'), ('consumer', consumer), ('round', round_no)]:
        if request.get(field) != expected:
            problems.append('592/inventory/' + field)
    if request.get('earlier_unaccepted') != list(earlier or []):
        problems.append('592/inventory/carryforward')
    expected = sorted(inventory, key=lambda r: {'3-0': 0, '2-1': 1, None: 2}.get(r.get('vote'), 3))
    rows = request.get('rows', [])
    ids = [r.get('id') for r in rows]
    if rows != expected:
        problems.append('592/inventory/order/fields')
    for row in expected:
        copies = [r for r in rows if r.get('id') == row['id']]
        if len(copies) != 1 or copies[0] != row:
            problems.append('592/' + row['id'] + '/inventory/order/fields')
        if len(copies) == 1:
            for field in row:
                copied = copies[0].get(field)
                if (copied != row[field]
                        or (field in ('risk', 'limit_widening', 'accepted') and type(copied) is not bool)):
                    problems.append('592/' + row['id'] + '/copy/' + field)
    for ident in earlier or []:
        if ids.count(ident) != 1:
            problems.append('592/' + ident + '/carryforward')
    inventory_ids = [r.get('id') for r in inventory]
    for row in inventory:
        evidence = row.get('acceptance_evidence') or {}
        if 'kind' in evidence and evidence['kind'] not in ('explicit', 'silence', 'merge-permission', 'temporary-disposition', 'unanimity', 'release-merge', 'missing'):
            problems.append('592/' + row['id'] + '/acceptance-evidence')
        if row.get('accepted'):
            ev = row.get('acceptance_evidence') or {}
            prefix = '592/' + row['id'] + '/acceptance-evidence'
            if ev.get('kind') != 'explicit' or not present(ev.get('words')):
                problems.append(prefix)
            if not present(ev.get('source')) or ev.get('source') != ev.get('applicable_source'):
                problems.append(prefix + '/source')
            decisions = ev.get('decisions')
            if not unique(decisions) or row['id'] not in (decisions or []) or not set(decisions or []) <= set(inventory_ids):
                problems.append(prefix + '/decision')
            if (ev.get('scrutiny') not in ('group', 'individual')
                    or (row.get('vote') == '2-1' and (ev.get('scrutiny') != 'individual' or decisions != [row['id']]))):
                problems.append(prefix + '/scrutiny')
    return problems


def preservation_checks():
    base = 'b22b4760fa3dcfd79a1c2557899bd735c6fafefc'
    check(subprocess.run(['git', 'merge-base', '--is-ancestor', base, 'HEAD'], cwd=ROOT).returncode == 0, 'recorded preservation baseline ancestor')
    paths = ['skills/role-contracts/ORCHESTRATOR.md', 'pipeline-override.sh', 'skills/role-contracts/orchestrator-rules.tsv']
    paths += [p.relative_to(ROOT).as_posix() for directory in ('hooks', 'skills/pre-merge-review')
              for p in (ROOT / directory).rglob('*') if p.is_file()]
    for path in paths:
        baseline = subprocess.check_output(['git', 'show', base + ':' + path], cwd=ROOT)
        actual = (ROOT / path).read_bytes()
        digest = hashlib.sha256(baseline).digest()
        oracle = lambda data: [] if hashlib.sha256(data).digest() == digest else ['593/protected-byte/' + path]
        check(not oracle(baseline), 'preserved assertion green at merge base ' + path)
        check(not oracle(actual), 'unchanged ' + path)
        rejects(oracle, actual, actual + b'\n', '593/protected-byte/' + path)
    result = subprocess.run([str(ROOT / 'check-workflow-adapters.sh')], cwd=ROOT, capture_output=True, text=True)
    check(result.returncode == 0, 'generated projection equality: ' + result.stdout + result.stderr)
    # Existing generation oracle must reject a real isolated projection edit.
    import tempfile
    import shutil
    with tempfile.TemporaryDirectory(prefix='panel-projection-') as tmp:
        target = Path(tmp) / 'repo'
        shutil.copytree(ROOT, target, ignore=shutil.ignore_patterns('.git', '__pycache__'))
        for path in ('WORKFLOW.md', 'adapters/codex/AGENTS.md', 'AGENTS.md'):
            projection = target / path
            original = projection.read_bytes()
            result = subprocess.run([str(target / 'check-workflow-adapters.sh'), str(target)], capture_output=True, text=True)
            check(result.returncode == 0, '593/projection/' + path + '/control')
            projection.write_bytes(original.replace(b'Temporary-decision panel', b'Corrupted-panel reference', 1))
            check(projection.read_bytes() != original, '593/projection/' + path + '/changed-bytes')
            result = subprocess.run([str(target / 'check-workflow-adapters.sh'), str(target)], capture_output=True, text=True)
            check(result.returncode != 0, '593/projection/' + path, 'mutation')
            projection.write_bytes(original)


source_checks()
remaining_manifest_checks(IDENT)
qa_sweep_checks(IDENT)
if IDENT == 589:
    inventory_checks()
elif IDENT == 590:
    eligibility_checks()
    outcome_checks()
elif IDENT == 591:
    floor_checks()
    prior_identity_checks()
elif IDENT == 592:
    disclosure_checks()
    acceptance_checks()
    copied_boolean_checks()
elif IDENT == 593:
    authority_checks()
    eligible_panel_checks()
    protection_checks()
    preservation_checks()
print(f'S{IDENT} represented fixtures: {FIXTURE_COUNTS}')
print(f'S{IDENT}: {COUNTS["positive"]} positive checks, {COUNTS["mutation"]} mutations rejected, {len(ERRORS)} failures; mechanical only; behavior UNRUN')
sys.exit(bool(ERRORS))

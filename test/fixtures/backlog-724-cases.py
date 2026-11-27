"""#724 executable CLI scenarios. Each run invokes the actual public script.

Snapshots are inputs, never expected comparator output. Fake-gh itself is built
by test/lib.sh:fake_gh_bin in the shell case. No production implementation import.
"""
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(sys.argv[1])
GROUP = int(sys.argv[2])
BOX = Path(os.environ['SANDBOX']) / 'backlog'
BOX.mkdir()
os.environ['BACKLOG_724_FIXTURE'] = str(BOX)
REPO = 'TiesL/spec-driven-guardrails'
URL = 'https://github.com/' + REPO + '/issues/'
PREFIX = 'repos/' + REPO + '/issues'
errors = []


def issue(n, body, state='open', labels=None):
    return {'number': n, 'id': n + 9000, 'node_id': 'ISSUE_' + str(n),
            'url': 'https://api.github.com/' + PREFIX + '/' + str(n),
            'html_url': URL + str(n), 'body': body, 'state': state,
            'title': 'Fixture ' + str(n), 'labels': [{'name': s} for s in (labels or ['enhancement', 'status:backlog'])]}


def snapshot(repo=REPO):
    # 10 is a supported top-level epic; 20 is nested; 30 is closed and on page 2.
    issues = [issue(10, '**Covers:** F77, S726\n**Blocked by:** none\n**Blocks:** none\n## Work items\n- [ ] #20\n', labels=['epic', 'enhancement', 'status:backlog']),
              issue(20, '**Epic:** #10\n**Covers:** F77, S726\n**Blocked by:** #30\n**Blocks:** none\n'),
              issue(30, '**Epic:** #40\n**Covers:** F77, S726\n**Blocked by:** none\n**Blocks:** #20\n', 'closed', ['enhancement']),
              issue(40, '**Covers:** F77, S726\n**Blocked by:** none\n**Blocks:** none\n## Work items\n- [x] #30\n', labels=['epic', 'enhancement', 'status:backlog'])]
    rest = {PREFIX: {'_pages': [issues[:2], issues[2:], []]}}
    for obj in issues:
        n = obj['number']; base = PREFIX + '/' + str(n)
        rest[base] = obj
        rest[base + '/comments'] = {'_pages': [[], []]}
        rest[base + '/parent'] = {20: issues[0], 30: issues[3]}.get(n)
        rest[base + '/sub_issues'] = {'_pages': [[i for i in issues if {20: 10, 30: 40}.get(i['number']) == n], []]}
        rest[base + '/dependencies/blocked_by'] = {'_pages': [[issues[2]] if n == 20 else [], []]}
        rest[base + '/dependencies/blocking'] = {'_pages': [[issues[1]] if n == 30 else [], []]}
    fields = [
        {'__typename': 'ProjectV2SingleSelectField', 'id': 'STATUS', 'name': 'Status', 'dataType': 'SINGLE_SELECT', 'options': [{'id': str(i), 'name': v} for i, v in enumerate(['Backlog', 'Ready', 'In progress', 'In review', 'Done'])]},
        {'__typename': 'ProjectV2SingleSelectField', 'id': 'HORIZON', 'name': 'Horizon', 'dataType': 'SINGLE_SELECT', 'options': [{'id': v, 'name': v} for v in ['Now', 'Next', 'Soon', 'Later']]},
        {'__typename': 'ProjectV2Field', 'id': 'RANK', 'name': 'Backlog rank', 'dataType': 'NUMBER'}]
    items = []
    for i in issues:
        content = dict(i, __typename='Issue', url=i['html_url'], state=i['state'].upper(), repository={'nameWithOwner': REPO})
        items.append({'id': 'ITEM_' + str(i['number']), 'type': 'ISSUE', 'isArchived': i['number'] == 30, 'content': content,
                      'fieldValues': {'_pages': [[
                          {'__typename': 'ProjectV2ItemFieldSingleSelectValue', 'name': 'Done' if i['state'] == 'closed' else 'Backlog', 'optionId': '4' if i['state'] == 'closed' else '0', 'field': fields[0]},
                          {'__typename': 'ProjectV2ItemFieldSingleSelectValue', 'name': 'Next', 'optionId': 'Next', 'field': fields[1]}],
                          [{'__typename': 'ProjectV2ItemFieldNumberValue', 'number': 4, 'field': fields[2]}]]}})
    result = {'repo': REPO, 'rest': rest, 'project': {'id': 'PROJECT_1', 'number': 1, 'title': 'Fixture backlog', 'url': 'https://github.com/orgs/TiesL/projects/1',
                                    'fields': {'_pages': [fields[:2], fields[2:]]}, 'items': {'_pages': [items[:2], items[2:]]}}}
    # The historical JSON-null adapter isolates comparison tests. The explicit
    # empty-204 witness below is the supported-absence transport regression;
    # this compatibility shape is never offered as live endpoint evidence.
    result['parent_response'] = 'json-null'
    return json.loads(json.dumps(result).replace(REPO, repo))


def body(config, n, value):
    config['rest'][PREFIX + '/' + str(n)]['body'] = value


def item(config, n):
    return next(i for page in config['project']['items']['_pages'] for i in page if i['content']['number'] == n)


def field(config, n, name, value):
    for page in item(config, n)['fieldValues']['_pages']:
        for v in list(page):
            if v['field']['name'] == name:
                if value is None:
                    page.remove(v)
                else:
                    v['number' if name == 'Backlog rank' else 'name'] = value


def check(label, condition, detail):
    if not condition:
        caller = sys._getframe(1)
        errors.append(f'S{GROUP}/{label} at {Path(caller.f_code.co_filename).name}:{caller.f_lineno}: {detail}')


def run(label, config, expected, tokens=(), board=True, nogh=False,
        owner='TiesL', project='1', repo_arg=None):
    before = len(errors)
    (BOX / 'snapshot.json').write_text(json.dumps(config))
    for name in ('calls.jsonl', 'requests.jsonl', 'witness.jsonl'):
        (BOX / name).write_text('')
    argv = [str(ROOT / 'backlog-drift.sh'), '--repo', repo_arg or config['repo']]
    if board:
        argv += ['--project-owner', owner, '--project', project]
    env = dict(os.environ)
    if nogh:
        env['PATH'] = env['BACKLOG_724_NOGH']
    try:
        p = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, text=True, timeout=15)
        output, code = p.stdout, p.returncode
        diagnostics = p.stderr
    except FileNotFoundError:
        output, code = 'backlog-drift.sh absent on supplied head', 127
        diagnostics = ''
    except subprocess.TimeoutExpired:
        output, code = 'report did not terminate on incomplete/cyclic input', 124
        diagnostics = ''
    check(label, code == 0 and f'result={expected}' in output,
          f'expected advisory exit 0/result={expected}; got exit {code}: {output[:240]}')
    for token in tokens:
        check(label + '/' + token, token.lower() in output.lower(), 'missing finding/evidence: ' + token)
    if expected == 'incomplete':
        check(label + '/never-clean', 'result=clean' not in output and re.search(r'unchecked', output, re.I), 'incomplete evidence must name unchecked scope')
    if expected == 'drift':
        check(label + '/observed-expected', re.search(r'observed|actual', output, re.I) and re.search(r'expected', output, re.I), 'finding must distinguish observed and expected values')
    check(label + '/no-secret', 'SECRET_724' not in output + diagnostics, 'raw credential-bearing stderr escaped')
    check(label + '/read-only', not (BOX / 'witness.jsonl').read_text(), (BOX / 'witness.jsonl').read_text())
    print(f'CASE S{GROUP}/{label}: {"PASS" if len(errors) == before else "RED"} exit={code} '
          + next((line for line in output.splitlines() if line.startswith('result=')), 'result=absent'))
    return output, [json.loads(s) for s in (BOX / 'calls.jsonl').read_text().splitlines()]


if GROUP == 726:
    for name, suffix, value, tokens in [
        ('wrong-parent', '/parent', None, ('20', 'parent')),
        ('removed-blocker', '/dependencies/blocked_by', {'_pages': [[], []]}, ('20', '30')),
        ('extra-blocker', '/dependencies/blocked_by', {'_pages': [[snapshot()['rest'][PREFIX + '/10']], []]}, ('20', '10')),
    ]:
        c = snapshot(); c['rest'][PREFIX + '/20' + suffix] = value
        run(name, c, 'drift', (URL + '20', *tokens))
    c = snapshot(); c['rest'][PREFIX + '/30/dependencies/blocking'] = {'_pages': [[], []]}
    run('inverse-only', c, 'drift', (URL + '30', '20'))
    c = snapshot(); body(c, 40, '**Covers:** F77\n**Blocked by:** none\n**Blocks:** none\n## Work items\n- [ ] #20\n')
    run('old-parent-child-entry', c, 'drift', ('40', '20'))
    c = snapshot(); body(c, 20, c['rest'][PREFIX + '/20']['body'] + '**Epic:** #40\n')
    run('duplicate-parent', c, 'incomplete', ('20', 'Epic'))
    c = snapshot(); body(c, 20, '**Epic:** #10\n**Covers:** F77\n**Blocks:** none\n')
    run('missing-not-empty', c, 'incomplete', ('20', 'Blocked by'))
    c = snapshot(); body(c, 20, c['rest'][PREFIX + '/20']['body'] + '\n> **Epic:** #999\n```\n**Blocks:** #999\n```\n    **Epic:** #998\n')
    run('ignore-quoted-fenced-indented', c, 'clean')
    c = snapshot(); c['rest'][PREFIX + '/20']['labels'] = [{'name': 'enhancement'}, {'name': 'status:in-progress'}, {'name': 'role:reviewer'}]
    run('review-status', c, 'drift', (URL + '20', 'In review'))
    c = snapshot(); c['rest'][PREFIX + '/30']['labels'] = [{'name': 'enhancement'}, {'name': 'status:in-progress'}, {'name': 'role:reviewer'}]
    run('closed-drops-active-labels', c, 'drift', (URL + '30', 'role'))
    c = snapshot(); c['rest'][PREFIX + '/20']['labels'].append({'name': 'epic'})
    body(c, 20, c['rest'][PREFIX + '/20']['body'] + '\n## Work items\nnone\n')
    run('nested-epic', c, 'clean')
    # Review R1: transport absence, identity collisions and canonical statuses.
    run('r1-local-edge-valid-control', snapshot(), 'clean')
    c = snapshot(); c['parent_response'] = 'empty-204'
    run('r1-empty-204-top-level', c, 'clean')
    for include in (False, True):
        p = subprocess.run(['gh', 'api', '--method', 'GET', PREFIX + '/10/parent',
                            *(['--include'] if include else [])], capture_output=True, text=True)
        check('r1-real-shaped-204-adapter-control-' + str(include),
              p.returncode == 0 and p.stdout == ('HTTP/2 204\n\n' if include else ''),
              '204 adapter must expose exit 0, empty body and optional status headers: ' + repr(p.stdout))
    print('CONTROL: HTTP 204 adapter exposes exit 0, empty body and optional status headers')
    c['rest'][PREFIX + '/20/parent'] = None
    run('r1-empty-204-declared-parent-missing-control', c, 'drift', (URL + '20', 'parent'))
    c = snapshot(); c['parent_response'] = 'empty-200'
    run('r1-empty-200-not-established-absence-control', c, 'incomplete', ('parent',))
    c = snapshot()
    foreign = copy.deepcopy(c['rest'][PREFIX + '/30'])
    foreign.update(id=880030, node_id='FOREIGN_30',
                   url='https://api.github.com/repos/other/repo/issues/30',
                   html_url='https://github.com/other/repo/issues/30')
    c['rest'][PREFIX + '/20/dependencies/blocked_by']['_pages'][0].append(foreign)
    out, _ = run('r1-foreign-colliding-blocker', c, 'drift',
                 (URL + '20', 'https://github.com/other/repo/issues/30', 'blocked_by'))
    check('r1-foreign-edge-linked-finding', any('observed=' in line and 'https://github.com/other/repo/issues/30' in line for line in out.splitlines()),
          'distinct foreign edge needs linked observed/expected evidence, not merely an aggregate warning: ' + out)
    for status in ('status:typo', 'status:garbage'):
        c = snapshot(); c['rest'][PREFIX + '/20']['labels'] = [{'name': 'enhancement'}, {'name': status}]
        run('r1-unknown-' + status, c, 'incomplete', (URL + '20', status, 'status'))
    for status, expected_status in [('status:backlog', 'Backlog'), ('status:in-progress', 'In progress')]:
        c = snapshot(); c['rest'][PREFIX + '/20']['labels'] = [{'name': 'enhancement'}, {'name': status}]
        field(c, 20, 'Status', expected_status)
        run('r1-valid-' + status, c, 'clean')
elif GROUP == 727:
    for name in ('Backlog rank', 'Horizon'):
        c = snapshot(); field(c, 30, name, None)
        run('missing-' + name, c, 'drift', (URL + '30', name))
    for disposition in ('awaiting-maintainer', 'parked'):
        c = snapshot(); field(c, 20, 'Backlog rank', None)
        note = '\n## Board decisions\n| Field | Reason | Proposed value | Disposition | Decision/reference |\n| Backlog rank | Inherits epic order; awaiting confirmation | undecided | ' + disposition + ' | ' + URL + '10#issuecomment-100 |\n'
        body(c, 20, c['rest'][PREFIX + '/20']['body'] + note)
        run('valid-' + disposition, c, 'clean', ('Backlog rank', disposition, URL + '10#issuecomment-100'))
        field(c, 20, 'Horizon', None)
        run('rank-cannot-excuse-horizon-' + disposition, c, 'drift', (URL + '20', 'Horizon'))
    c = snapshot(); field(c, 20, 'Horizon', None)
    c['rest'][PREFIX + '/20/comments'] = {'_pages': [[], [{'id': 100, 'html_url': URL + '20#issuecomment-100', 'body': '## Board decisions\n| Field | Reason | Proposed value | Disposition | Decision/reference |\n| Horizon | Maintainer deciding | Soon | awaiting-maintainer | ' + URL + '20#issuecomment-100 |'}], []]}
    run('comment-page-two-exception', c, 'clean', ('Horizon', 'awaiting-maintainer'))
    c = snapshot(); field(c, 20, 'Horizon', None); body(c, 20, c['rest'][PREFIX + '/20']['body'] + '\npriority TBD\n')
    run('generic-note-insufficient', c, 'drift', (URL + '20', 'Horizon'))
    for label, reason, proposal, reference in [('missing-reason', '', 'Soon', URL + '20#issuecomment-100'), ('missing-reference', 'Maintainer deciding', 'Soon', ''), ('missing-proposal', 'Maintainer deciding', '', URL + '20#issuecomment-100')]:
        c = snapshot(); field(c, 20, 'Horizon', None)
        note = '\n## Board decisions\n| Field | Reason | Proposed value | Disposition | Decision/reference |\n| Horizon | ' + reason + ' | ' + proposal + ' | awaiting-maintainer | ' + reference + ' |\n'
        body(c, 20, c['rest'][PREFIX + '/20']['body'] + note)
        run(label, c, 'drift', (URL + '20', 'Horizon'))
    c = snapshot(); field(c, 20, 'Horizon', None)
    notes = '\n## Board decisions\n| Field | Reason | Proposed value | Disposition | Decision/reference |\n| Horizon | Order uncertain | Soon | awaiting-maintainer | ' + URL + '20#issuecomment-100 |\n| Horizon | Keep empty | undecided | parked | ' + URL + '20#issuecomment-101 |\n'
    body(c, 20, c['rest'][PREFIX + '/20']['body'] + notes)
    run('contradictory-unresolved-notes', c, 'incomplete', ('Horizon',))
elif GROUP == 728:
    _, calls = run('complete-multipage', snapshot(), 'clean')
    requests = [json.loads(s) for s in (BOX / 'requests.jsonl').read_text().splitlines()]
    queries = [r['fields'].get('query', '') for r in requests if r['endpoint'] == 'graphql']
    for selection in ('items', 'fields', 'fieldValues', 'pageInfo'):
        check('graphql-selection-' + selection, any(re.search(r'\b' + selection + r'\b', q) for q in queries), 'GraphQL request must actually select ' + selection)
    check('rest-issue-pagination', any('api' in a and any(PREFIX in x for x in a) and '--paginate' in a for a in calls), 'repository issues must be paginated, including closed issues')
    check('all-issue-states', any('state=all' in json.dumps(a) for a in calls), 'issue collection must explicitly include closed issues')
    check('project-pagination', any('graphql' in a and 'items-next' in json.dumps(a) for a in calls), 'second project items page was never requested')
    check('field-pagination', any('graphql' in a and 'fields-next' in json.dumps(a) for a in calls), 'second project fields page was never requested')
    check('nested-pagination', any('graphql' in a and 'values-ITEM_' in json.dumps(a) for a in calls), 'nested fieldValues page two was never requested')
    c = snapshot(); c['project']['items']['_pages'][1] = [i for i in c['project']['items']['_pages'][1] if i['content']['number'] != 30]
    run('missing-closed-membership-page-two', c, 'drift', (URL + '30', 'membership'))
    for typename, value in [('Text', {'text': 'Fixture title'}), ('Date', {'date': '2026-11-27'}),
                            ('Iteration', {'title': 'Sprint 1', 'iterationId': 'ITER_1', 'startDate': '2026-11-23', 'duration': 7})]:
        c = snapshot()
        ordinary = dict(value, __typename='ProjectV2ItemField' + typename + 'Value',
                        field={'id': 'UNRELATED_' + typename, 'name': 'Title' if typename == 'Text' else typename})
        item(c, 20)['fieldValues']['_pages'][1].append(ordinary)
        run('r1-unrelated-' + typename, c, 'clean')
    run('r1-required-values-valid-control', snapshot(), 'clean')
    for name in ('Backlog rank', 'Horizon', 'Status'):
        c = snapshot()
        for page in item(c, 20)['fieldValues']['_pages']:
            for v in page:
                if v['field']['name'] == name:
                    v['number' if name == 'Backlog rank' else 'optionId'] = {'malformed': True}
        run('r1-malformed-required-' + name, c, 'incomplete', (URL + '20', name))
    # Positive controls execute the same actual fake-gh boundary, including
    # implicit REST POST and JSON --input GraphQL mutation payloads.
    for name, args in [('unknown', ['api', 'unexpected']), ('post', ['api', '-X', 'POST', PREFIX + '/20/dependencies/blocked_by', '-F', 'issue_id=9030']),
                       ('delete', ['api', '--method', 'DELETE', PREFIX + '/20/dependencies/blocked_by/9030']),
                       ('implicit-post', ['api', PREFIX + '/20', '-f', 'body=unauthorized']),
                       ('mutation', ['api', 'graphql', '-f', 'query=mutation { deleteProjectV2Item(input:{itemId:"ITEM_20"}) { deletedItemId } }'])]:
        (BOX / 'witness.jsonl').write_text('')
        p = subprocess.run(['gh', *args], capture_output=True, text=True)
        check('positive-write-witness-' + name, p.returncode == 97 and bool((BOX / 'witness.jsonl').read_text()), 'reachable witness did not reject injected write/unexpected call')
    mutation = BOX / 'mutation.json'
    mutation.write_text(json.dumps({'query': 'mutation { deleteProjectV2Item(input:{itemId:"ITEM_20"}) { deletedItemId } }'}))
    (BOX / 'witness.jsonl').write_text('')
    p = subprocess.run(['gh', 'api', 'graphql', '--input', str(mutation)], capture_output=True, text=True)
    check('positive-json-mutation-witness', p.returncode == 97 and bool((BOX / 'witness.jsonl').read_text()), 'JSON mutation bypassed read-only guard')
    # A malicious report can swallow gh's failure and still print clean. This
    # injected executable proves the external witness would reject that run.
    injected = BOX / 'injected-report.sh'
    injected.write_text('#!/usr/bin/env bash\ngh api -X PATCH repos/fixture/backlog/issues/20 -f body=unauthorized >/dev/null 2>&1 || true\nprintf "result=clean\\n"\n')
    injected.chmod(0o755)
    (BOX / 'witness.jsonl').write_text('')
    p = subprocess.run([str(injected)], capture_output=True, text=True)
    check('positive-swallowed-write-control', p.returncode == 0 and 'result=clean' in p.stdout and bool((BOX / 'witness.jsonl').read_text()), 'write injection was not externally visible after swallowed failure')
    (BOX / 'witness.jsonl').write_text('')
    p = subprocess.run(['gh', 'api', 'graphql', '-X', 'POST', '-f', 'query=query { organization(login:"fixture") { projectV2(number:1) { id } } }'], capture_output=True, text=True)
    check('query-post-allowed-control', p.returncode == 0 and not (BOX / 'witness.jsonl').read_text(), 'read-only GraphQL transport POST was rejected')
    print('CONTROL: reachable unknown/REST/GraphQL/JSON/swallowed-write witnesses rejected injections; query POST allowed')
elif GROUP == 729:
    for failure in ('network', 'rest-denied', 'unsupported-parent', 'board-denied', 'graphql-errors', 'graphql-page-two-failure', 'malformed-json', 'missing-issue-fields', 'page-two-failure', 'cursor-cycle', 'cursor-truncated', 'missing-page-info', 'missing-project-field', 'comments-denied'):
        c = snapshot(); c['failure'] = failure
        operation = {'network': 'gh', 'rest-denied': 'blocked_by', 'unsupported-parent': 'parent', 'board-denied': 'project', 'graphql-errors': 'project', 'graphql-page-two-failure': 'project', 'malformed-json': 'issues', 'missing-issue-fields': '20', 'page-two-failure': 'issues', 'cursor-cycle': 'items', 'cursor-truncated': 'items', 'missing-page-info': 'items', 'missing-project-field': 'Horizon', 'comments-denied': 'comments'}[failure]
        run(failure, c, 'incomplete', (operation,))
    run('no-gh', snapshot(), 'incomplete', ('gh',), nogh=True)
    c = snapshot(); c['failure'] = 'comments-denied'; field(c, 30, 'Status', 'Backlog')
    run('known-drift-survives-failed-comments', c, 'incomplete', (URL + '30', 'Done'))
    for failure in ('board-denied', 'graphql-page-two-failure'):
        c = snapshot(); c['failure'] = failure
        out, _ = run('r1-unverified-membership-' + failure, c, 'incomplete', ('membership',))
        check('r1-no-invented-absence-' + failure,
              not re.search(r'membership[^\n]*observed="missing"', out),
              'partial/denied inventory invented missing membership: ' + out)
        check('r1-unchecked-membership-' + failure,
              any('unchecked' in line.lower() and 'membership' in line.lower() for line in out.splitlines()),
              'name unchecked membership scope: ' + out)
    c = snapshot(); c['failure'] = 'board-denied'
    c['rest'][PREFIX + '/20/dependencies/blocked_by'] = {'_pages': [[], []]}
    run('r1-independent-edge-survives-denied-inventory', c, 'incomplete', (URL + '20', 'blocked_by', 'observed='))
elif GROUP == 730:
    c = snapshot(); field(c, 30, 'Status', 'In review')
    run('closed-not-done', c, 'drift', (URL + '30', 'In review', 'Done'))
    run('closed-done-archived-second-page', snapshot(), 'clean')
elif GROUP == 731:
    output, calls = run('board-omitted', snapshot(), 'clean', ('not-applicable',), board=False)
    check('board-omitted-no-discovery', bool(calls) and not any('graphql' in a for a in calls), 'must still read native relations without discovering an arbitrary board')
    c = snapshot(); c['rest'][PREFIX + '/20/parent'] = None
    run('board-omitted-native-drift', c, 'drift', (URL + '20', 'parent', 'not-applicable'), board=False)
    c = snapshot(); c['failure'] = 'board-denied'
    run('configured-board-is-not-na', c, 'incomplete')
    c = snapshot('other/adopter')
    c['rest']['repos/other/adopter/issues/20']['labels'] = [{'name': 'feature'}]
    out, _ = run('r1-foreign-feature-boardless', c, 'incomplete', ('label', 'not-applicable'), board=False)
    check('r1-no-exported-label-drift', not re.search(r'(type|status|role) labels[^\n]*observed=', out),
          'SDG label policy leaked to adopter: ' + out)
    check('r1-unchecked-label-mapping', any('unchecked' in line.lower() and re.search(r'label|vocabulary', line, re.I) for line in out.splitlines()),
          'unsupported label vocabulary must be explicitly unchecked: ' + out)
    c['rest']['repos/other/adopter/issues/20/dependencies/blocked_by'] = {'_pages': [[], []]}
    run('r1-foreign-independent-edge-retained', c, 'incomplete',
        ('https://github.com/other/adopter/issues/20', 'blocked_by', 'observed='), board=False)
    for owner, project in [('other', '1'), ('TiesL', '2')]:
        c = snapshot(); field(c, 20, 'Status', 'Queue')
        c['project'].update(number=int(project), url=f'https://github.com/orgs/{owner}/projects/{project}')
        for page in c['project']['fields']['_pages']:
            for f in page:
                if f['name'] == 'Status':
                    f['options'] = [{'id': 'queue', 'name': 'Queue'}]
        out, _ = run('r1-unsupported-board-' + owner + '-' + project, c, 'incomplete', ('Status',), owner=owner, project=project)
        check('r1-no-exported-Status-' + owner + '-' + project,
              not re.search(r'\bStatus observed=', out), 'SDG board mapping leaked: ' + out)
        check('r1-unchecked-board-mapping-' + owner + '-' + project,
              any('unchecked' in line.lower() and re.search(r'Status|lifecycle|mapping', line, re.I) for line in out.splitlines()),
              'unsupported board lifecycle must be explicitly unchecked: ' + out)
    for missing in ('membership', 'Backlog rank', 'Horizon'):
        c = snapshot()
        if missing == 'membership':
            c['project']['items']['_pages'][1] = [i for i in c['project']['items']['_pages'][1] if i['content']['number'] != 30]
        else:
            field(c, 30, missing, None)
        run('r1-unmapped-board-independent-' + missing, c, 'incomplete',
            (URL + '30', missing, 'observed='), owner='other')
    run('r1-supported-SDG-project-control', snapshot(), 'clean')
    run('r1-case-insensitive-repository-control', snapshot(), 'clean', board=False,
        repo_arg='tiesl/SPEC-DRIVEN-GUARDRAILS')
else:
    raise AssertionError(GROUP)

for error in errors:
    print('FAIL: ' + error)
sys.exit(bool(errors))

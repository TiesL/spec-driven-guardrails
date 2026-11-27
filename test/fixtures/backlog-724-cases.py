"""#724 executable CLI scenarios. Each run invokes the actual public script.

Snapshots are inputs, never expected comparator output. Fake-gh itself is built
by test/lib.sh:fake_gh_bin in the shell case. No production implementation import.
"""
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


def snapshot():
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
    result = {'rest': rest, 'project': {'id': 'PROJECT_1', 'number': 1, 'title': 'Fixture backlog', 'url': 'https://github.com/orgs/TiesL/projects/1',
                                    'fields': {'_pages': [fields[:2], fields[2:]]}, 'items': {'_pages': [items[:2], items[2:]]}}}
    return result


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


def run(label, config, expected, tokens=(), nogh=False, cwd=None):
    before = len(errors)
    (BOX / 'snapshot.json').write_text(json.dumps(config))
    for name in ('calls.jsonl', 'requests.jsonl', 'witness.jsonl'):
        (BOX / name).write_text('')
    argv = [str(ROOT / 'backlog-drift.sh')]
    env = dict(os.environ)
    if nogh:
        env['PATH'] = env['BACKLOG_724_NOGH']
    try:
        p = subprocess.run(argv, cwd=cwd or ROOT, env=env, capture_output=True, text=True, timeout=15)
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
        check(label + '/never-clean', 'result=clean' not in output, 'incomplete evidence must never become clean')
    if expected == 'drift':
        check(label + '/observed-expected', re.search(r'observed|actual', output, re.I) and re.search(r'expected', output, re.I), 'finding must distinguish observed and expected values')
    check(label + '/no-raw-diagnostic', not any(s in output + diagnostics for s in ('SECRET_724', 'SERVER_DIAGNOSTIC_724')), 'raw server diagnostic escaped')
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
    run('local-edge-valid-control', snapshot(), 'clean')
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
    # Every shape is independent; no certainty taxonomy or fallback probe.
    for failure, operation in [
        ('network', 'gh'), ('rest-denied', 'blocked_by'),
        ('parent-404', 'parent'), ('board-denied', 'project'),
        ('graphql-errors', 'project'), ('graphql-page-two-failure', 'project'),
        ('malformed-json', 'issues'), ('missing-issue-fields', '20'),
        ('page-two-failure', 'issues'), ('cursor-cycle', 'items'),
        ('cursor-truncated', 'items'), ('missing-page-info', 'items'),
        ('missing-project-field', 'Horizon'), ('comments-denied', 'comments')]:
        c = snapshot(); c['failure'] = failure
        out, _ = run(failure, c, 'incomplete', (operation,))
        # Independent transport control: prove faults are reachable even while
        # the current reporter still stops at the new fixed-scope boundary.
        probes = {
            'network': (PREFIX + '?state=all', []),
            'rest-denied': (PREFIX + '/20/dependencies/blocked_by', ['--paginate', '--slurp']),
            'parent-404': (PREFIX + '/20/parent', ['--include']),
            'comments-denied': (PREFIX + '/20/comments', ['--paginate', '--slurp']),
            'malformed-json': (PREFIX, ['--paginate', '--slurp']),
            'missing-issue-fields': (PREFIX + '/20', []),
            'page-two-failure': (PREFIX, ['--paginate', '--slurp']),
        }
        if failure in probes:
            endpoint, flags = probes[failure]
            p = subprocess.run(['gh', 'api', '--method', 'GET', endpoint, *flags],
                               capture_output=True, text=True)
            if failure in ('malformed-json', 'missing-issue-fields'):
                injected = p.stdout == '{bad\n' if failure == 'malformed-json' else json.loads(p.stdout).get('body') is None
                check(failure + '/fault-control', p.returncode == 0 and injected, 'malformed-data injection was not reachable')
            else:
                check(failure + '/fault-control', p.returncode != 0, 'non-success injection was not reachable')
        else:
            p = subprocess.run(['gh', 'api', 'graphql', '-f',
                                'query=query { repositoryOwner(login:"TiesL") { ... on User { projectV2(number:1) { items(first:100, after:"items-next") { pageInfo { hasNextPage endCursor } } fields(first:100) { nodes { ... on ProjectV2Field { id name } } } } } } }',
                                '-f', 'cursor=items-next'], capture_output=True, text=True)
            data = json.loads(p.stdout) if p.stdout else {}
            if failure in ('board-denied', 'graphql-page-two-failure'):
                injected = p.returncode != 0
            elif failure == 'graphql-errors':
                injected = p.returncode == 0 and bool(data.get('errors'))
            else:
                project = data['data']['repositoryOwner']['projectV2']
                page_info = project['items'].get('pageInfo')
                injected = {
                    'cursor-cycle': page_info == {'hasNextPage': True, 'endCursor': 'items-next'},
                    'cursor-truncated': page_info == {'hasNextPage': True, 'endCursor': None},
                    'missing-page-info': page_info is None,
                    'missing-project-field': all(f['name'] != 'Horizon' for f in project['fields']['nodes']),
                }[failure]
            check(failure + '/fault-control', injected, 'GraphQL fault injection was not reachable')
        check(failure + '/no-invented-finding', not any('observed=' in line for line in out.splitlines()),
              'a consistent snapshot plus failed reads must not invent drift: ' + out)
        if failure not in ('network', 'malformed-json'):
            affected = (20,) if failure in ('rest-denied', 'parent-404', 'missing-issue-fields', 'comments-denied') else (10, 20, 30, 40)
            # A failed global inventory can only enumerate already-known URLs.
            if failure != 'page-two-failure':
                for n in affected:
                    check(failure + '/affected-' + str(n), URL + str(n) in out,
                          'human diagnostic must identify affected issue URL')
        if failure in ('malformed-json', 'page-two-failure'):
            check(failure + '/unknown-remainder',
                  re.search(r'unknown|unenumerat|inventory.{0,60}incomplete|incomplete.{0,60}inventory', out, re.I),
                  'failed global inventory must not claim the unknown remainder was enumerated')
    print('CONTROL: independent REST/GraphQL failure injections exercised')
    run('no-gh', snapshot(), 'incomplete', ('gh',), nogh=True)
    for failure in ('rest-denied', 'parent-404', 'missing-issue-fields', 'comments-denied'):
        c = snapshot(); c['failure'] = failure
        # Successful reads would expose these deliberate issue-20 mismatches;
        # failure means skip all remaining checks for 20, not partial findings.
        c['rest'][PREFIX + '/20/dependencies/blocked_by'] = {'_pages': [[], []]}
        field(c, 20, 'Status', 'Ready')
        # Issue 10 precedes the failed issue; issue 30 is unaffected and later.
        c['rest'][PREFIX + '/10/sub_issues'] = {'_pages': [[], []]}
        field(c, 30, 'Status', 'Backlog')
        out, calls = run('skip-and-continue-' + failure, c, 'incomplete',
                         (URL + '20', URL + '10', URL + '30', 'Done'))
        finding_lines = [line for line in out.splitlines() if 'observed=' in line]
        check(failure + '/skip-affected', not any(URL + '20 ' in line for line in finding_lines),
              'failed issue must have no downstream comparison findings: ' + out)
        for n in (10, 30):
            check(failure + '/retain-or-continue-' + str(n),
                  any(URL + str(n) + ' ' in line for line in finding_lines),
                  'retain prior findings and continue unaffected issues: ' + out)
        operation = {'rest-denied': 'dependencies/blocked_by', 'parent-404': 'parent',
                     'missing-issue-fields': '', 'comments-denied': 'comments'}[failure]
        endpoints = [a for a in calls if any(PREFIX + '/20' in x for x in a)]
        failed_index = next((i for i, a in enumerate(endpoints)
                             if any(re.search(re.escape(PREFIX + '/20' + ('/' + operation if operation else '')) + r'(?:\?|$)', x) for x in a)), None)
        check(failure + '/stop-dependent-reads', failed_index is not None and failed_index == len(endpoints)-1,
              'remaining issue reads must stop at the failed operation: ' + json.dumps(endpoints))
    for failure in ('board-denied', 'graphql-page-two-failure'):
        c = snapshot(); c['failure'] = failure
        c['rest'][PREFIX + '/10/sub_issues'] = {'_pages': [[], []]}
        out, _ = run('prior-finding-survives-' + failure, c, 'incomplete',
                     (URL + '10', 'observed='))
        check(failure + '/no-missing-membership',
              not re.search(r'membership[^\n]*observed="missing"', out),
              'failed inventory cannot establish missing membership: ' + out)
elif GROUP == 730:
    c = snapshot(); field(c, 30, 'Status', 'In review')
    run('closed-not-done', c, 'drift', (URL + '30', 'In review', 'Done'))
    run('closed-done-archived-second-page', snapshot(), 'clean')
elif GROUP == 731:
    out, calls = run('fixed-SDG-project-from-other-directory', snapshot(), 'clean',
                     ('TiesL/spec-driven-guardrails', 'TiesL/1'), cwd=BOX)
    check('no-current-repo-discovery', not any('repos/{owner}/{repo}' in str(a) for a in calls),
          'fixed scope must not discover the checkout repository')
    requests = [json.loads(line) for line in (BOX / 'requests.jsonl').read_text().splitlines()]
    check('fixed-project-read', any(re.search(r'login:\s*"TiesL"', r['fields'].get('query', ''))
                                   and re.search(r'projectV2\(number:\s*1\)', r['fields'].get('query', ''))
                                   for r in requests if r['endpoint'] == 'graphql'),
          'no-argument invocation must read TiesL Project 1')
    for args in [('--repo', REPO), ('--project-owner', 'TiesL', '--project', '1')]:
        (BOX / 'calls.jsonl').write_text('')
        p = subprocess.run([str(ROOT / 'backlog-drift.sh'), *args], cwd=BOX,
                           capture_output=True, text=True)
        check('reject-' + args[0], p.returncode == 2 and not (BOX / 'calls.jsonl').read_text(),
              'removed scope option must be rejected before gh: ' + p.stdout + p.stderr)
else:
    raise AssertionError(GROUP)

for error in errors:
    print('FAIL: ' + error)
sys.exit(bool(errors))

"""#724 gh adapter: raw REST/Projects-v2 JSON, argv log and reachable witness.

Only a test fake. No comparison logic and no real gh/network fallback. GET
pagination and GraphQL POST queries are allowed; every write is witnessed.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

args = sys.argv[1:]
folder = Path(os.environ['BACKLOG_724_FIXTURE'])
with (folder / 'calls.jsonl').open('a') as stream:
    stream.write(json.dumps(args) + '\n')


def refuse(reason):
    with (folder / 'witness.jsonl').open('a') as stream:
        stream.write(json.dumps({'reason': reason, 'argv': args}) + '\n')
    sys.exit(97)


def option(*names):
    for i, arg in enumerate(args):
        for name in names:
            if arg == name and i + 1 < len(args):
                return args[i + 1]
            if arg.startswith(name + '='):
                return arg[len(name) + 1:]
    return None


if not args or args[0] != 'api':
    refuse('unexpected-command')
method = (option('--method', '-X') or '').upper()
fields = {}
for i, arg in enumerate(args):
    if arg in ('-f', '-F', '--field', '--raw-field') and i + 1 < len(args):
        key, _, value = args[i + 1].partition('=')
        fields[key] = value
if option('--input'):
    source = option('--input')
    fields.update(json.loads(sys.stdin.read() if source == '-' else Path(source).read_text()))
# Endpoint is the first positional operand after api; tolerate leading flags.
skip = False
endpoint = None
valued = ('--method', '-X', '--header', '-H', '-f', '-F', '--field',
          '--raw-field', '--jq', '-q', '--input', '--hostname', '--template', '-t')
for arg in args[1:]:
    if skip:
        skip = False
    elif arg in valued:
        skip = True
    elif not arg.startswith('-') and endpoint is None:
        endpoint = arg.lstrip('/')
graphql = endpoint == 'graphql'
query = fields.get('query', '')
with (folder / 'requests.jsonl').open('a') as stream:
    stream.write(json.dumps({'argv': args, 'endpoint': endpoint, 'method': method, 'fields': fields}) + '\n')
if graphql:
    # Reject a mutation even in JSON --input; allow POST *queries*.
    if re.search(r'\bmutation\b', query) or method not in ('', 'GET', 'POST'):
        refuse('graphql-write')
    if not re.search(r'\bquery\b|^\s*\{', query):
        refuse('unrecognized-graphql-query')
    if not re.search(r'\bprojectV2\s*\(|\bnode\s*\(', query):
        refuse('unexpected-graphql-resource')
elif method not in ('', 'GET', 'HEAD') or (fields and method != 'GET'):
    refuse('rest-write')

config = json.loads((folder / 'snapshot.json').read_text())
mode = config.get('failure', '')
if mode == 'network':
    print('fixture network unavailable: token=SECRET_724', file=sys.stderr)
    sys.exit(1)


def emit(value, status=200):
    if '--include' in args or '-i' in args:
        print('HTTP/2 ' + str(status) + '\n')
    # Real gh emits no JSON body for 204. JSON null is available only as an
    # explicitly labelled historical comparator-isolation input.
    if (status == 204 and config.get('parent_response') != 'json-null') or (value is None and config.get('parent_response') == 'empty-200'):
        return
    jq = option('--jq', '-q')
    if jq:
        done = subprocess.run(['jq', '-r', jq], input=json.dumps(value), text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        sys.stdout.write(done.stdout)
        sys.exit(done.returncode) if done.returncode else None
    else:
        print(json.dumps(value))


if graphql:
    if mode == 'board-denied':
        print('permission denied: token=SECRET_724', file=sys.stderr)
        sys.exit(1)
    if mode == 'graphql-errors':
        emit({'data': None, 'errors': [{'message': 'fixture denied'}]})
        sys.exit(0)
    if mode == 'graphql-page-two-failure' and 'items-next' in json.dumps(fields):
        sys.exit(1)
    project = config['project']
    # Connections deliberately have distinct cursors. A client must finish
    # fields, items AND each item's fieldValues, not merely outer items.
    supplied = json.dumps(fields) + query
    project = json.loads(json.dumps(project))
    for connection, cursor in (('fields', 'fields-next'), ('items', 'items-next')):
        connection_data = project[connection]
        pages = connection_data.pop('_pages')
        second = cursor in supplied
        connection_data['nodes'] = pages[1 if second else 0]
        connection_data['pageInfo'] = {'hasNextPage': not second, 'endCursor': None if second else cursor}
    for item in project['items']['nodes']:
        values = item['fieldValues']
        pages = values.pop('_pages')
        second = 'values-' + item['id'] in supplied
        values['nodes'] = pages[1 if second else 0]
        values['pageInfo'] = {'hasNextPage': not second, 'endCursor': None if second else 'values-' + item['id']}
    if mode == 'cursor-cycle':
        project['items']['pageInfo'] = {'hasNextPage': True, 'endCursor': 'items-next'}
    if mode == 'cursor-truncated':
        project['items']['pageInfo'] = {'hasNextPage': True, 'endCursor': None}
    if mode == 'missing-page-info':
        del project['items']['pageInfo']
    if mode == 'missing-project-field':
        project['fields']['nodes'] = [n for n in project['fields']['nodes'] if n['name'] != 'Horizon']
    node = project
    for page in config['project']['items']['_pages']:
        for item in page:
            if item['id'] in supplied:
                node = json.loads(json.dumps(item))
                pages = node['fieldValues'].pop('_pages')
                second = 'values-' + item['id'] in supplied
                node['fieldValues'].update(nodes=pages[1 if second else 0], pageInfo={
                    'hasNextPage': not second, 'endCursor': None if second else 'values-' + item['id']})
    def selected_values(obj):
        if isinstance(obj, dict):
            typename = obj.get('__typename', '')
            if typename in ('ProjectV2ItemFieldTextValue', 'ProjectV2ItemFieldDateValue', 'ProjectV2ItemFieldIterationValue'):
                # Return the current query's actual typename-only shape when
                # its type fragment is absent, not invented field identities.
                if not re.search(r'\bon\s+' + typename + r'\s*\{', query):
                    return {'__typename': typename}
            return {k: selected_values(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [selected_values(v) for v in obj]
        return obj
    emit(selected_values({'data': {'organization': {'projectV2': project}, 'user': {'projectV2': project}, 'node': node}}))
    sys.exit(0)

if endpoint is None:
    refuse('missing-endpoint')
repo = config['repo']
endpoint = endpoint.replace('{owner}/{repo}', repo)
# GitHub repository names are case insensitive; returned identities remain
# canonical, independently of the spelling in the requested endpoint.
endpoint = re.sub(r'^repos/' + re.escape(repo) + r'(?=/|\?|$)',
                  lambda _: 'repos/' + repo, endpoint, flags=re.I)
endpoint, _, parameters = endpoint.partition('?')
if endpoint == 'repos/' + repo:
    emit({'full_name': repo, 'owner': {'login': repo.split('/')[0], 'type': 'Organization'}, 'name': repo.split('/')[1]})
    sys.exit(0)
if endpoint not in config['rest']:
    refuse('unexpected-endpoint')
if mode == 'rest-denied' and endpoint.endswith('/dependencies/blocked_by'):
    print('403 fixture denied', file=sys.stderr)
    sys.exit(1)
if mode == 'unsupported-parent' and endpoint.endswith('/parent'):
    print('404 unsupported endpoint', file=sys.stderr)
    sys.exit(1)
if mode == 'comments-denied' and endpoint.endswith('/comments'):
    sys.exit(1)
value = config['rest'][endpoint]
if mode == 'malformed-json' and endpoint == 'repos/' + repo + '/issues':
    print('{bad')
    sys.exit(0)
if mode == 'missing-issue-fields' and endpoint == 'repos/' + repo + '/issues/20':
    emit({'number': 20, 'body': None})
    sys.exit(0)
if isinstance(value, dict) and '_pages' in value:
    if '--paginate' not in args and not re.search(r'(?:^|&)page=\d+', parameters):
        refuse('unpaginated-list')
    pages = value['_pages']
    start = int(re.search(r'(?:^|&)page=(\d+)', parameters)[1]) - 1 if re.search(r'(?:^|&)page=(\d+)', parameters) else 0
    selected = pages[start:] if '--paginate' in args else pages[start:start+1]
    if '--slurp' in args and mode != 'page-two-failure':
        emit(selected)
        sys.exit(0)
    for index, page in enumerate(selected, start):
        if mode == 'page-two-failure' and endpoint == 'repos/' + repo + '/issues' and index == 1:
            print('fixture page two unavailable', file=sys.stderr)
            sys.exit(1)
        emit(page)
else:
    emit(value, 204 if value is None and config.get('parent_response') != 'empty-200' else 200)

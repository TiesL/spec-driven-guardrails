"""Public CLI/dispatch/doc seams for #599. No product writes; mutations use scratch copies."""
import ast
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(sys.argv[2])
TMP = Path(sys.argv[3])
ROWS = [('Product', 'Product', 'Discovery'), ('Architect', 'Architect', 'Planning'),
        ('QA', 'QA', 'Test'), ('Fullstack Developer', 'Developer', 'Implementation'),
        ('Reviewer', 'Reviewer', 'Review')]
EMIT = 'skills/pre-merge-review/model-record-emit.sh'
ORCH = 'skills/role-contracts/ORCHESTRATOR.md'
HOOK = 'hooks/agent-dispatch.py'
TSV = 'skills/role-contracts/orchestrator-rules.tsv'
failures = []
assertions = 0
TERMINATORS = ['', ';', ',', ')', '`', '"', "'"]

def check(ok, reason):
    global assertions
    assertions += 1
    if not ok:
        failures.append(reason)
        print('FAIL: ' + reason)
    return ok

def run(args, root=ROOT, data=None, timeout=None):
    return subprocess.run([str(x) for x in args], cwd=root, input=data,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=timeout)

def emit(args, root=ROOT):
    return run([root / EMIT] + args, root)

def model(role):
    return ['--model', 'test-model'] + (['--floor-basis', 'same capability as Implementation'] if role == 'Reviewer' else [])

def prompt(prefix, flags):
    return ('ROLE SESSION: ' + prefix + '\n\nQuoted contract.\n/c/model-record-emit.sh ' + flags +
            '\nPR #42, head 0123abcdef, finding-carryforward-gate.sh 42\n')

def terminated_prompt(flags, suffix):
    text = prompt('Product', flags + suffix)
    # Closing quotes/backticks belong to a quoted command in the dispatch brief.
    if suffix in ['`', '"', "'"]:
        text = text.replace('/c/model-record-emit.sh', suffix + '/c/model-record-emit.sh', 1)
    return text

def hook(text, root=ROOT, timeout=None):
    data = {'tool_name': 'Agent', 'tool_input': {'prompt': text, 'model': 'test-model', 'subagent_type': 'general-purpose'}}
    return run(['python3', '-I', root / HOOK, root / ORCH, root / TSV], root, json.dumps(data).encode(), timeout=timeout)

def rule(n, root=ROOT):
    return next(l.encode() for l in (root / ORCH).read_text().splitlines() if l.startswith('- ' + n + ' '))

def allowed(p, label, root=ROOT):
    r=hook(p,root)
    check((r.returncode,r.stdout,r.stderr)==(0,b'',b''), label + ': expected silent allow' +
          ' (exit %s, stdout %s bytes, stderr %s lines)' % (r.returncode,len(r.stdout),len(r.stderr.splitlines())))

def denied(p, ids, label, result=None):
    r = hook(p) if result is None else result
    lines=r.stderr.splitlines()
    check(r.returncode==2 and not r.stdout, label + ': expected exit 2 and empty stdout' +
          ' (exit %s, stdout %s bytes)' % (r.returncode,len(r.stdout)))
    expected=[rule(i) for i in ids]
    check(lines[:-1]==expected and len(lines)==len(expected)+1, label + ': expected only ' + ','.join(ids) + ' core lines once plus AVOID')
    check(bool(lines) and b'--role' in lines[-1] and b'--stage' in lines[-1], label + ': AVOID must cover role and stage')

def refusal(args, label, words=(), root=ROOT):
    r=emit(args,root)
    check(r.returncode==2 and r.stdout==b'' and len(r.stderr.splitlines())==1,
          label + ': expected exit 2, empty stdout, one stderr reason' +
          ' (exit %s, stdout %s bytes, stderr %s lines)' % (r.returncode,len(r.stdout),len(r.stderr.splitlines())))
    for w in words:
        check(w.lower().encode() in r.stderr.lower(), label + ': reason must name ' + w)
    return r

def copy(name):
    dest=TMP/name
    dest.mkdir()
    for f in [EMIT,ORCH,HOOK,TSV]:
        (dest/f).parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/f,dest/f)
    shutil.copytree(ROOT/'lib',dest/'lib')
    return dest

def historical_baseline(name, paths, merge_base=False):
    # S336 uses the merge base when available; S286 reports an unavailable
    # historical arm explicitly. Do not require local branches/history in CI.
    for ref in ['main', 'origin/main']:
        args = (['git', 'merge-base', 'HEAD', ref] if merge_base else
                ['git', 'rev-parse', '--verify', ref + '^{commit}'])
        result = run(args)
        if result.returncode == 0:
            revision = result.stdout.decode().strip()
            break
    else:
        print('SKIP: ' + name + ': main/origin/main history unavailable; '
              'only historical comparisons skipped (full clones run them)')
        return None
    baseline = copy(name)
    for path in paths:
        result = run(['git', 'show', revision + ':' + path])
        if not check(result.returncode == 0, name + ' git show ' + path):
            return None
        (baseline / path).write_bytes(result.stdout)
    return baseline

def unchecked(result, label):
    lines = result.stderr.splitlines()
    check(result.returncode == 0 and not result.stdout and len(lines) == 1 and
          len(result.stderr) <= 1024 and lines[0].endswith(b'dispatch allowed unchecked') and
          result.stderr.count(b'dispatch allowed unchecked') == 1 and
          b'Traceback' not in result.stderr and b'PRIVATE_PROMPT_SENTINEL' not in result.stderr,
          label + ': expected exit 0, empty stdout, exactly one bounded diagnostic ending '
          'dispatch allowed unchecked; got ' + verdict(result))


def round8_escaped_whitespace():
    # Real Bash defines word/comment boundaries; the real emitter defines
    # role/stage agreement. Never obtain an expected verdict from the hook.
    slash = chr(92)
    cases = [
        ('model escaped space', '--model', 'build' + slash + ' #601', 'build #601', True),
        ('model genuine comment', '--model', 'build #601', 'build', False),
        ('model escaped tab', '--model', 'build' + slash + '\t#601', 'build\t#601', True),
        ('model two backslashes', '--model', 'build' + slash * 2 + ' #601', 'build' + slash, False),
        ('model three backslashes', '--model', 'build' + slash * 3 + ' #601', 'build' + slash + ' #601', True),
        ('model single-quoted escaped space', '--model', "'build" + slash + " #601'", 'build' + slash + ' #601', True),
        ('model double-quoted escaped space', '--model', '"build' + slash + ' #601"', 'build' + slash + ' #601', True),
    ]
    for flag in ['--floor-basis', '--effort']:
        cases += [
            (flag + ' escaped space', flag, 'build' + slash + ' #601', 'build #601', True),
            (flag + ' genuine comment', flag, 'build #601', 'build', False),
        ]
    red = green = 0
    for name, flag, spelling, value, stage_survives in cases:
        label = 'round-8 ' + name
        base = ['--role', 'Product'] + (['--model', 'm'] if flag != '--model' else [])
        flags = ' '.join(base) + ' ' + flag + ' ' + spelling + ' ' + slash + '\n--stage Planning\n'
        argv = base + [flag, value] + (['--stage', 'Planning'] if stage_survives else [])
        sh = run(['bash', '-c', 'capture() { printf "%s\\0" "$@"; }; capture ' + flags, 'oracle'])
        if not check(sh.stdout == b''.join(x.encode() + b'\0' for x in argv) and
                     sh.returncode == (0 if stage_survives else 127) and
                     (sh.stderr == b'' if stage_survives else
                      sh.stderr.endswith(b'--stage: command not found\n')),
                     label + ': Bash complete argv and physical comment boundary'):
            continue
        # Use Bash's actual decoded argv for the emitter, after pinning it
        # independently above. Even a malformed fixture cannot supply RED.
        decoded = [x.decode() for x in sh.stdout.split(b'\0')[:-1]]
        oracle = emit(decoded)
        if stage_survives:
            valid_oracle = check(oracle.returncode == 2 and not oracle.stdout and
                                 len(oracle.stderr.splitlines()) == 1 and
                                 b'Discovery' in oracle.stderr and b'Planning' in oracle.stderr,
                                 label + ': real emitter refuses Product/Planning mismatch')
        else:
            control = emit(['--stage', 'Discovery'] + decoded[2:])
            # Comment controls can still fail emitter-only validation:
            # a literal backslash is invalid in a model, and Product cannot
            # carry floor-basis. Neither changes role/stage agreement (A48).
            reason = (b'model must be one token' if name == 'model two backslashes' else
                      b'only a Review marker carries a floor-basis' if flag == '--floor-basis' else None)
            valid_oracle = check((oracle.returncode, oracle.stdout, oracle.stderr) ==
                                 (control.returncode, control.stdout, control.stderr) and
                                 (oracle.returncode == 2 and not oracle.stdout and reason in oracle.stderr
                                  if reason else oracle.returncode == 0 and bool(oracle.stdout)),
                                 label + ': real emitter matches Discovery control, including value validation')
        shell_emit = run(['bash', '-c', '"$1" ' + flags, 'oracle', ROOT / EMIT])
        same_lines = check((shell_emit.returncode, shell_emit.stdout, shell_emit.stderr) ==
                           (oracle.returncode if stage_survives else 127,
                            oracle.stdout, oracle.stderr + sh.stderr),
                           label + ': real emitter on identical physical lines')
        print('ORACLE: ' + label + ': argv=' + repr(decoded) +
              ', emitter exit=' + str(oracle.returncode) +
              ', shell exit=' + str(shell_emit.returncode) +
              ', stderr=' + repr(oracle.stderr.decode()))
        if not (valid_oracle and same_lines):
            continue
        text = 'ROLE SESSION: Product\n/c/model-record-emit.sh ' + flags
        before = len(failures)
        if b'role Product owns stage Discovery, not supplied stage Planning' in oracle.stderr:
            denied(text, ['OR31'], label)
        else:
            allowed(text, label)
        red += len(failures) > before
        green += len(failures) == before
    print('ROUND-8 escaped-whitespace: %d red, %d green cases' % (red, green))


def round7_dispatch():
    C = '/c/model-record-emit.sh'
    prefix = 'ROLE SESSION: Product\n'
    good = C + ' --role Product --model m'
    wrong = C + ' --role Architect --model m'
    started = time.monotonic()
    groups = {}

    def expect(text, expected, label, group='prose', data=None, paths=None, timed=False):
        before = len(failures)
        tick = time.monotonic()
        try:
            if data is not None or paths is not None:
                result = run(['python3', '-I', ROOT / HOOK] +
                             (paths or [ROOT / ORCH, ROOT / TSV]),
                             data=data if data is not None else payload(text), timeout=2.5)
            else:
                result = hook(text, timeout=2.5)
        except subprocess.TimeoutExpired:
            check(False, label + ': hook exceeded 2.5 s; timeout is not validation')
        else:
            if expected == 'unchecked':
                unchecked(result, label)
            elif expected == 'allow':
                check((result.returncode, result.stdout, result.stderr) == (0, b'', b''),
                      label + ': expected silent allow, got ' + verdict(result))
            else:
                denied(text, expected.split(','), label, result=result)
        elapsed = time.monotonic() - tick
        if timed:
            print('TIMING: round-7 ' + label + ': %.3f s' % elapsed)
            check(elapsed < 3, label + ': must finish under 3 s')
        tally = groups.setdefault(group, [0, 0])
        tally[0] += len(failures) > before
        tally[1] += 1

    def payload(text):
        return json.dumps({'tool_name': 'Agent', 'tool_input': {
            'prompt': text, 'model': 'test-model', 'subagent_type': 'general-purpose'}}).encode()

    # Presentation before a script mention has no shell semantics. Exercise
    # every shape both with and without a prefix, and role/stage disagreement.
    introductions = ['- ', '1. ', '$ ', '> ', 'Run: ', 'cd x && ', 'bash -c ',
                     'First line of the report: output of ']
    prose_pairs = [('', ''),
                   ("Don't retype model-record-emit.sh as your report's first line:\n", "Don't edit it.\n"),
                   ('An unmatched " before the command.\n', 'An unmatched " after it.\n'),
                   ('A ` before it.\n', 'A ` after it.\n'),
                   ("model-record-emit.sh prose-only path\\\n", "It's prose.\n")]
    for intro in introductions:
        for before, after in prose_pairs:
            for prefixed, flags, expected in [
                (True, '--role Product', 'allow'), (False, '--role Product', 'OR8'),
                (True, '--role Architect', 'OR31'), (True, '--stage Planning', 'OR31')]:
                text = (prefix if prefixed else '') + before + intro + C + ' ' + flags + ' --model m\n' + after
                expect(text, expected, 'round-7 ' + repr(intro) + ' ' + repr(before) + ' ' + flags +
                       (' prefixed' if prefixed else ' missing prefix'))
    for pos in range(3):
        commands = [good] * 3
        commands[pos] = wrong
        expect(prefix + "Don't open a shell quote.\n" + '\n'.join(commands) +
               '\nAn unmatched " follows.\n', 'OR31', 'mismatch unit position ' + str(pos))
    expect(prefix + good + '; ' + wrong + '\n', 'OR31', 'multiple top-level commands on one line')
    expect(prefix + C + ' explanation --role Architect\n', 'OR31', 'guarded flag after suffix prose')
    # Synthetic briefs contain no actual external commands; only the public hook runs.
    briefs = [
        ('Architect', "ROLE SESSION: Architect\nRead A48 and F40. Don't edit product code.\n"
         "Run model-record-emit.sh as the report's first line:\nRun: " + C +
         " --role Architect --model m\nDon't paraphrase its output.\n", 'allow'),
        ('QA report first line', "ROLE SESSION: QA\nRead the Reviewer's findings.\n"
         "First line of the report: output of " + C + " --stage Review --model m\n"
         "Don't edit product files.\n", 'OR31'),
        ('Reviewer', "ROLE SESSION: Reviewer\nReview PR #601 at head fe0fbbf.\n"
         "Run finding-carryforward-gate.sh 601. Don't merge.\n- " + C +
         " --role Reviewer --model m --floor-basis 'same capability'\nIt's checked.\n", 'allow'),
        ('QA control', "ROLE SESSION: QA\nDon't change the implementation.\n"
         "First line of the report: output of " + C + " --role QA --model m\nIt's mandatory.\n", 'allow')]
    for label, text, expected in briefs:
        expect(text, expected, 'synthetic ' + label, 'briefs')

    # Independently confirm complete argv using real Bash, then use the real
    # emitter as the marker oracle. These contain no expansion spellings.
    supported = [
        ('consumed flags in model', '--role Product --model "x --role Architect --stage Planning"',
         ['--role', 'Product', '--model', 'x --role Architect --stage Planning'], 'allow'),
        ('opaque equals model', '--role Product --model="x --role Architect"',
         ['--role', 'Product', '--model=x --role Architect'], 'allow'),
        ('adjacent continued role', '--role "Prod' + chr(92) + '\nuct" --model m',
         ['--role', 'Product', '--model', 'm'], 'allow'),
        ('continued role mismatch', '--role "Prod' + chr(92) + '\nuct Architect" --model m',
         ['--role', 'Product Architect', '--model', 'm'], 'OR31'),
    ]
    for label, flags, argv, expected in supported:
        sh = run(['bash', '-c', 'set -- ' + flags + '; printf "%s\\0" "$@"'])
        check((sh.returncode, sh.stdout, sh.stderr) ==
              (0, b''.join(x.encode() + b'\0' for x in argv), b''), label + ': Bash complete argv')
        expect(prefix + C + ' ' + flags + '\n', expected, label, 'arguments')
        r = emit(argv)
        control = emit(['--stage', 'Discovery'] + argv[2:]) if expected == 'allow' else None
        if expected == 'allow':
            check((r.returncode, r.stdout, r.stderr) ==
                  (control.returncode, control.stdout, control.stderr), label + ': real emitter legacy marker oracle')
        else:
            check(r.returncode == 2 and not r.stdout and len(r.stderr.splitlines()) == 1,
                  label + ': emitter rejects complete invalid role')
    for flag in ['--model', '--floor-basis', '--effort']:
        expect(prefix + good + ' ' + flag + ' "--role Architect --stage Planning"\n',
               'allow', 'consumed ' + flag + ' flags', 'arguments')
        expect(prefix + good + ' ' + flag + '="--role Architect --stage Planning"\n',
               'allow', 'opaque equals ' + flag, 'arguments')
    for wrapper in ["'", '"', '`']:
        expect(prefix + 'Run: ' + wrapper + good + wrapper + '\n', 'allow', 'mid-line wrapper ' + wrapper, 'arguments')
        expect(prefix + 'Run: ' + wrapper + wrong + wrapper + '\n', 'OR31', 'wrong mid-line wrapper ' + wrapper, 'arguments')
    for wrapper in ["'", '"', '`']:
        expect(prefix + 'Run: ' + wrapper + good + '\n', 'unchecked',
               'unmatched presentation wrapper ' + wrapper, 'malformed')
    expect(prefix + good + '\n' + C + ' --role --stage Discovery\n', 'OR31',
           'missing role cannot hide beside matching command', 'arguments')
    for tail in [" # don't edit", " # don't edit \\", " # don't edit ' \" `"]:
        expect(prefix + good + tail + '\n' + wrong + '\n', 'OR31', 'comment ' + repr(tail), 'comments')
    expect((prefix + good + ' ' + chr(92) + '\n--stage Planning\n').replace('\n', '\r\n'),
           'OR31', 'CRLF continuation', 'continuations')
    for count in [1, 2, 3, 4, 5]:
        # A48: "Remove the last backslash and the line ending; preserve all
        # other characters and spacing." Bash is the argv oracle: odd runs
        # continue, but counts 3/5 attach literal backslashes to --stage.
        # Even runs end the command and leave --stage as a separate command.
        label = 'trailing backslash count ' + str(count)
        flags = '--role Product --model m ' + chr(92) * count + '\n--stage Planning\n'
        argv = ['--role', 'Product', '--model', 'm']
        argv += ([chr(92) * (count // 2) + '--stage', 'Planning'] if count % 2 else
                 [chr(92) * (count // 2)])
        sh = run(['bash', '-c', 'capture() { printf "%s\\0" "$@"; }; capture ' + flags, 'oracle'])
        check(sh.returncode == (0 if count % 2 else 127) and
              sh.stdout == b''.join(x.encode() + b'\0' for x in argv) and
              (sh.stderr == b'' if count % 2 else
               sh.stderr.endswith(b'--stage: command not found\n')),
              label + ': Bash complete argv and continuation boundary')
        r = refusal(argv, label + ' real emitter argv',
                    ['Discovery', 'Planning'] if count == 1 else ['unknown argument', argv[4]])
        shell_emit = run(['bash', '-c', '"$1" ' + flags, 'oracle', ROOT / EMIT])
        check((shell_emit.returncode, shell_emit.stdout, shell_emit.stderr) ==
              (2 if count % 2 else 127, b'', r.stderr + sh.stderr),
              label + ': real emitter with identical physical lines')
        print('ORACLE: ' + label + ': argv=' + repr(argv) +
              ', emitter exit=' + str(r.returncode) + ', stderr=' + repr(r.stderr.decode()))
        expect(prefix + C + ' ' + flags, 'OR31' if count == 1 else 'allow', label, 'continuations')
    expect(prefix + good + ' ' + chr(92) + ' \n--stage Planning\n', 'allow',
           'trailing space prevents continuation', 'continuations')
    expect(prefix + good + ' ' + chr(92), 'unchecked', 'dangling EOF continuation', 'malformed')
    for count in [32, 33]:
        text = prefix + good + (' ' + chr(92) + '\n') * (count - 1) + ' --stage Discovery\n'
        expect(text, 'allow' if count == 32 else 'unchecked', 'physical line cap ' + str(count), 'limits', timed=True)
    for quote in ["'", '"']:
        text = prefix + C + ' --role Product --model ' + quote + 'PRIVATE_PROMPT_SENTINEL\nx' + quote + '\n'
        expect(text, 'unchecked', 'no implicit continuation ' + quote, 'malformed')
        expect(text + wrong + '\n', 'unchecked', 'malformed unit beside mismatch ' + quote, 'malformed')
        expect(prefix + wrong + '\n' + text[len(prefix):], 'unchecked', 'mismatch before malformed ' + quote, 'malformed')
        # A script mention is ordinary consumed value text when explicitly continued.
        text = prefix + C + ' --role Product --model ' + quote + 'x ' + chr(92) + '\n' + wrong + quote + '\n'
        expect(text, 'allow', 'consumed continued script mention ' + quote, 'continuations')
    expect(prefix + good + ' --model "PRIVATE_PROMPT_SENTINEL\n', 'unchecked', 'unbalanced model quote', 'malformed')
    expect('', 'unchecked', 'bad JSON', 'malformed', data=b'{')
    expect('', 'unchecked', 'bad encoding', 'malformed', data=b'\xff')
    expect(prefix + wrong, 'unchecked', 'unreadable policy', 'malformed', paths=[TMP / 'absent-policy', ROOT / TSV])

    # Inclusive caps use literal lengths, independent of implementation constants.
    unit_cap, prompt_cap, byte_cap = 64 * 1024, 4 * 1024 * 1024, 32 * 1024 * 1024
    for delta in [-1, 0, 1]:
        # Count the entire original unit, including a continuation and its newline.
        seed = good + ' ' + chr(92) + '\n --model '
        single = good + ' --model '
        text = prefix + single + 'x' * (unit_cap + delta - len(single))
        expect(text, 'allow' if delta <= 0 else 'unchecked', 'single-line unit cap ' + str(unit_cap + delta), 'limits', timed=True)
        text = prefix + seed + 'x' * (unit_cap + delta - len(seed))
        expect(text, 'allow' if delta <= 0 else 'unchecked', 'unit cap ' + str(unit_cap + delta), 'limits', timed=True)
        text = prefix + good + '\n'
        text += 'x' * (prompt_cap + delta - len(text))
        expect(text, 'allow' if delta <= 0 else 'unchecked', 'prompt cap ' + str(prompt_cap + delta), 'limits', timed=True)
        text = 'x' * (prompt_cap + delta)
        expect(text, 'allow' if delta <= 0 else 'unchecked', 'no-prefix prompt cap ' + str(prompt_cap + delta), 'limits', timed=True)
        data = payload(prefix + good)
        data += b' ' * (byte_cap + delta - len(data))
        expect('', 'allow' if delta <= 0 else 'unchecked', 'stdin byte cap ' + str(byte_cap + delta),
               'limits', data=data, timed=True)
    for label, text, expected in [
        ('bounded invalid role', prefix + C + ' --role ' + 'X' * 60000, 'OR31'),
        ('adversarial quote pieces', prefix + C + ' --role ' + '"X"' * 18000, 'OR31'),
        ('many units', prefix + (good + '\n') * 20000 + wrong, 'OR31'),
        ('many continued units', prefix + (good + ' ' + chr(92) + '\n --stage Discovery\n') * 10000 + wrong, 'OR31'),
    ]:
        expect(text, expected, label, 'performance', timed=True)
    # Five deliberately faulty scratch mutations. Require each oracle to
    # reject its injected defect; never patch the working hook. A48 retains
    # STAGE_FLAG: disabling it must expose ignored legacy-stage mismatches
    # both mid-line and in a later unit, regardless of the unit reader used.
    mutants = [
        ('implicit quote continuation',
         'prompt = ti.get(F_PROMPT)',
         'prompt = ti.get(F_PROMPT).replace(chr(10), " ")',
         prefix + C + ' --role Product --model "x\ny"\n', 'unchecked'),
        ('skipped mid-line mismatch',
         'STAGE_FLAG', 're.compile(r"(?!)")',
         prefix + good + '\ncd x && ' + C + ' --stage Planning --model m\n', 'OR31'),
        ('ignored prompt cap',
         'prompt = ti.get(F_PROMPT)',
         'prompt = ti.get(F_PROMPT)[:4 * 1024 * 1024]',
         prefix + good + '\n' + 'x' * prompt_cap, 'unchecked'),
        ('swallowed later unit',
         'STAGE_FLAG', 're.compile(r"(?!)")',
         prefix + good + '\nLATER_UNIT\n' + C + ' --stage Planning --model m\n', 'OR31'),
        ('missing unchecked diagnostic',
         'print("agent-dispatch: %s; dispatch allowed unchecked" % msg, file=sys.stderr)',
         'pass  # MUTANT: silent fail-open',
         prefix + C + ' --role "PRIVATE_PROMPT_SENTINEL\n', 'unchecked'),
    ]
    for name, old, new, text, expected in mutants:
        root = copy('round7-mutant-' + name.replace(' ', '-'))
        path = root / HOOK
        source = path.read_text()
        if old == 'STAGE_FLAG':
            # Locate the specified assignment structurally, not by its
            # formatting, regex spelling or the removed tokenizer's text.
            assignment = next((node for node in ast.parse(source).body
                               if isinstance(node, ast.Assign) and
                               any(isinstance(target, ast.Name) and target.id == old
                                   for target in node.targets)), None)
            if not check(assignment is not None, 'mutation anchor available: ' + name):
                continue
            value = assignment.value
            lines = source.splitlines(keepends=True)
            start = sum(len(line.encode()) for line in lines[:value.lineno - 1]) + value.col_offset
            end = sum(len(line.encode()) for line in lines[:value.end_lineno - 1]) + value.end_col_offset
            source_bytes = source.encode()
            path.write_bytes(source_bytes[:start] + new.encode() + source_bytes[end:])
        else:
            if not check(old in source, 'mutation anchor available: ' + name):
                continue
            path.write_text(source.replace(old, new, 1))
        result = hook(text, root, timeout=2.5)
        if expected == 'unchecked':
            lines = result.stderr.splitlines()
            accepted = (result.returncode == 0 and not result.stdout and len(lines) == 1 and
                        lines[0].endswith(b'dispatch allowed unchecked'))
        else:
            accepted = verdict(result) == 'deny ' + expected
        check(not accepted, 'round-7 oracle must kill mutation: ' + name)
    for group, (red, total) in sorted(groups.items()):
        print('RESULT: round-7 %s: %d/%d %s' % (group, red, total, 'RED' if red else 'GREEN'))
    print('TIMING: round-7 total %.3f s' % (time.monotonic() - started))

def round3_dispatch(baseline):
    # Controlled Bash snippets are fixture data only. The hook receives the
    # literal spelling; expansion here establishes argv independently of it.
    forms = [
        ('adjacent backtick substitution', 'Product`printf Architect`', 'ProductArchitect', False),
        ('adjacent dollar substitution', 'Product$(printf Architect)', 'ProductArchitect', False),
        ('adjacent parameter expansion', 'Product${X}', 'ProductArchitect', False),
        ('double-quoted literal newline', '"Product\nArchitect"', 'Product\nArchitect', False),
        ('single-quoted literal newline', "'Product\nArchitect'", 'Product\nArchitect', False),
        ('unquoted backslash newline invalid', 'Product' + chr(92) + '\nArchitect', 'ProductArchitect', False),
        ('quoted backslash newline invalid', '"Product' + chr(92) + '\nArchitect"', 'ProductArchitect', False),
        ('quoted backslash newline valid', '"Prod' + chr(92) + '\nuct"', 'Product', True),
    ]
    for label, spelling, value, valid in forms:
        shell = run(['bash', '-c', 'X=Architect; set -- ' + spelling +
                     '; printf "%s\\n" "$#"; printf "%s" "$1"'])
        check((shell.returncode, shell.stdout, shell.stderr) ==
              (0, b'1\n' + value.encode(), b''), label + ': Bash complete argument')
        text = prompt('Product', '--role ' + spelling)
        if 'literal newline' in label:
            unchecked(hook(text), label + ': unsupported literal multiline role')
            refusal(['--role', value, '--model', 'm'], label + ' emitter control', ['role'])
        elif valid:
            result = hook(text)
            # Pin the requested allow verdict. Invalid neighbours below must
            # prove validation; an allow alone cannot establish it ran.
            check(result.returncode == 0 and not result.stdout, label + ': expected allow and empty stdout')
            print('OBSERVATION: ' + label + ': current stderr=' + repr(result.stderr.decode()))
            result = emit(['--role', value, '--model', 'm'])
            check(result.returncode == 0 and bool(result.stdout) and not result.stderr,
                  label + ': complete valid role emitter control')
        else:
            denied(text, ['OR31'], label)
            refusal(['--role', value, '--model', 'm'], label + ' emitter control', ['role'])
        if baseline is not None:
            result = hook(text, baseline)
            print('OBSERVATION: main ' + label + ': exit=' + str(result.returncode) +
                  ', stdout bytes=' + str(len(result.stdout)) +
                  ', stderr=' + repr(result.stderr.decode()))
    # Unsupported literal multiline units and malformed input retain the
    # fail-open policy. Pin the single visible diagnostic.
    text = prompt('Product', '--role "Product')
    result = hook(text)
    check(result.returncode == 0 and not result.stdout and
          len(result.stderr.splitlines()) == 1 and
          b'cannot parse role shell word' in result.stderr and
          b'dispatch allowed unchecked' in result.stderr,
          'genuinely unterminated quote: allow with one unchecked diagnostic')
    if baseline is not None:
        result = hook(text, baseline)
        print('OBSERVATION: main genuinely unterminated quote: exit=' + str(result.returncode) +
              ', stdout bytes=' + str(len(result.stdout)) + ', stderr=' + repr(result.stderr.decode()))
    # A48 replaces oversized-role denial with a fast unchecked diagnostic.
    # Ordinary prose still receives a fast missing-command denial. A killed
    # process is never validation; both probes retain the 2.5 s deadline.
    for label, text in [
        ('million-character invalid role', prompt('Product', '--role ' + 'X' * 1_000_000)),
        ('million-character ordinary line control', 'ROLE SESSION: Product\n' + 'X' * 1_000_000 + '\n'),
    ]:
        started = time.monotonic()
        try:
            result = hook(text, timeout=2.5)
        except subprocess.TimeoutExpired:
            elapsed = time.monotonic() - started
            check(False, label + ': no effective denial before 2.5 s deadline (%.3f s)' % elapsed)
            continue
        elapsed = time.monotonic() - started
        print('TIMING: ' + label + ': %.3f s' % elapsed)
        check(elapsed < 3.0, label + ': wall time must be under 3 s (%.3f s)' % elapsed)
        if 'invalid role' in label:
            unchecked(result, label + ': over unit cap')
        else:
            denied(text, ['OR31'], label, result=result)

def round4_dispatch(baseline):
    # Whole-command continuation is distinct from a continuation inside a value.
    # Independently establish Bash argv before asserting the hook's verdict.
    for depth in [1, 3]:
        join = (' ' + chr(92) + '\n') * depth
        cases = [
            ('stage mismatch on continuation', '--role Product', '--stage Planning',
             ['--role', 'Product', '--stage', 'Planning'], ['Product', 'Planning', 'Discovery']),
            ('stage mismatch on first line', '--stage Planning', '--role Product',
             ['--stage', 'Planning', '--role', 'Product'], ['Product', 'Planning', 'Discovery']),
            ('repeated role mismatch on continuation', '--role Product', '--role Architect',
             ['--role', 'Product', '--role', 'Architect'], ['twice']),
            ('repeated role mismatch on first line', '--role Architect', '--role Product',
             ['--role', 'Architect', '--role', 'Product'], ['twice']),
        ]
        for label, first, last, args, reason in cases:
            label = 'continued command depth ' + str(depth) + ' ' + label
            flags = first + join + last + ' --model m'
            expected = args + ['--model', 'm']
            shell = run(['bash', '-c', 'set -- ' + flags + '; printf "%s\\0" "$@"'])
            check((shell.returncode, shell.stdout, shell.stderr) ==
                  (0, b''.join(x.encode() + b'\0' for x in expected), b''),
                  label + ': Bash complete argv')
            before = len(failures)
            denied(prompt('Product', flags), ['OR31'], label)
            print('RESULT: ' + label + ': hook ' + ('RED' if len(failures) > before else 'GREEN'))
            refusal(expected, label + ' emitter control', reason)
        flags = '--role Product' + join + '--stage Discovery --model m'
        allowed(prompt('Product', flags), 'continued matching command depth ' + str(depth))
        result = emit(['--role', 'Product', '--stage', 'Discovery', '--model', 'm'])
        check(result.returncode == 0 and bool(result.stdout) and not result.stderr,
              'continued matching command depth ' + str(depth) + ': emitter control')
        # Legacy stage recognition is explicitly observation-only, including
        # whether the stage flag is before or after the continuation.
        for stage in ['Discovery', 'Planning']:
            for first, last in [('--stage ' + stage, '--model m'),
                                ('--model m', '--stage ' + stage)]:
                text = prompt('Product', first + join + last)
                for name, root in [('current', ROOT), ('main', baseline)]:
                    if root is None:
                        continue
                    result = hook(text, root)
                    print('OBSERVATION: ' + name + ' continued stage-only depth ' + str(depth) +
                          ' ' + repr(first + join + last) + ': exit=' + str(result.returncode) +
                          ', stdout bytes=' + str(len(result.stdout)) +
                          ', stderr=' + repr(result.stderr.decode()) + '; no stage hook oracle pinned')

def round5_quoted_forms():
    # Quote kind x one or two literal line breaks x with or without that quote
    # kind escaped around the break, as a balanced half fraction: every pair of
    # these factors appears, at half the runtime of the full 2x2x2 product.
    forms = []
    for quote in ['"', "'"]:
        for breaks in [1, 2]:
            for escaped in [(quote == '"') == (breaks == 2)]:
                value = '\n'.join(['one', 'two', 'three'][:breaks + 1])
                if escaped:
                    value = 'a ' + quote + value + quote + ' z'
                if quote == '"':
                    spelling = '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
                else:
                    spelling = "'" + value.replace("'", "'" + chr(92) + "''") + "'"
                label = ('double' if quote == '"' else 'single') + ' quotes, ' + \
                        str(breaks) + ' newline(s)' + (', escaped quotes' if escaped else '')
                forms.append((label, spelling, value))
    return forms

def round5_emitter_controls():
    # A48 retires the whole-shell hook matrix, not the emitter contract.
    # Retain its Bash argv and emitter controls independently of the hook.
    from concurrent.futures import ThreadPoolExecutor
    from itertools import permutations
    kinds = [  # (label, flag spelling, argv, expected hook verdict, emitter reason words)
        ('stage mismatch', '--stage Planning', ['--stage', 'Planning'], 'deny', ['Product', 'Planning', 'Discovery']),
        ('repeated role', '--role Architect', ['--role', 'Architect'], 'deny', ['twice']),
        ('matching stage', '--stage Discovery', ['--stage', 'Discovery'], 'allow', []),
    ]
    seps = [('space', ' '), ('cont1', ' ' + chr(92) + '\n'), ('cont3', (' ' + chr(92) + '\n') * 3)]
    cases = []
    for qlabel, spelling, value in round5_quoted_forms():
        for klabel, xflag, xargv, verdict, words in kinds:
            tokens = {'R': ('--role Product', ['--role', 'Product']), 'X': (xflag, xargv),
                      'M': ('--model ' + spelling, ['--model', value])}
            for order in permutations('RXM'):
                for (s1, sep1) in seps:
                    for (s2, sep2) in seps:
                        flags = tokens[order[0]][0] + sep1 + tokens[order[1]][0] + sep2 + tokens[order[2]][0]
                        argv = sum((tokens[t][1] for t in order), [])
                        cases.append({'kind': klabel, 'quote': qlabel, 'order': ''.join(order),
                                      'seps': s1 + '+' + s2, 'flags': flags, 'argv': argv,
                                      'verdict': verdict, 'words': words})
    def shell(case):
        return run(['bash', '-c', 'set -- ' + case['flags'] + '; printf "%s\\0" "$@"'])
    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=8) as pool:
        shells = list(pool.map(shell, cases))
        argvs = sorted({tuple(c['argv']) for c in cases})
        emitted = dict(zip(argvs, pool.map(lambda a: emit(list(a)), argvs)))
        plain = {a: tuple('m' if i > 0 and a[i - 1] == '--model' else x for i, x in enumerate(a)) for a in argvs}
        emitted_plain = dict(zip(argvs, pool.map(lambda a: emit(list(plain[a])), argvs)))
    print('TIMING: round-5 quoted multiline matrix: %d cases, %.3f s' % (len(cases), time.monotonic() - started))
    for case, sh in zip(cases, shells):
        check((sh.returncode, sh.stdout, sh.stderr) ==
              (0, b''.join(x.encode() + b'\0' for x in case['argv']), b''),
              'round-5 retained emitter matrix: Bash complete argv ' + repr(case['argv']))
    # Emitter controls on the exact Bash argv, and with the quoted value replaced
    # by a valid model so the refusal or success is about role and stage.
    kind_of = {tuple(c['argv']): next(k for k in kinds if k[0] == c['kind']) for c in cases}
    for argv in argvs:
        kind = kind_of[argv]
        label = 'round-5 emitter control ' + repr(list(argv))
        for result, name in [(emitted[argv], 'quoted value'), (emitted_plain[argv], 'valid model')]:
            if kind[3] == 'deny':
                check(result.returncode == 2 and not result.stdout and
                      all(w.lower().encode() in result.stderr.lower() for w in kind[4]),
                      label + ' ' + name + ': expected refusal naming ' + ', '.join(kind[4]))
            elif name == 'valid model':
                check(result.returncode == 0 and bool(result.stdout) and not result.stderr,
                      label + ' valid model: matching role and stage must succeed')
            else:
                check(result.returncode == 2 and not result.stdout and b'model' in result.stderr
                      and b'role' not in result.stderr.lower() and b'stage' not in result.stderr.lower(),
                      label + ' quoted value: only the model value may be refused')

PREVIOUS_HEAD = '2d93c25'  # last head before the whole-prompt shell word stream (round 5)

def previous_head_baseline():
    # The prose cases below are pinned to the verdicts of the head before the
    # structural change. Each case also records that verdict, so a shallow
    # clone without this commit still runs every current-hook assertion.
    if run(['git', 'rev-parse', '--verify', PREVIOUS_HEAD + '^{commit}']).returncode:
        print('SKIP: round-6 previous head ' + PREVIOUS_HEAD + ' unavailable; '
              'only its comparisons skipped, recorded expectations still pinned')
        return None
    base = copy('previous-head')
    result = run(['git', 'show', PREVIOUS_HEAD + ':' + HOOK])
    if not check(result.returncode == 0, 'round-6 git show ' + PREVIOUS_HEAD + ':' + HOOK):
        return None
    (base / HOOK).write_bytes(result.stdout)
    return base

def verdict(r):
    # 'allow', 'deny OR8,OR31' (core lines once each, then AVOID) or 'other ...'.
    lines = r.stderr.splitlines()
    if (r.returncode, r.stdout, r.stderr) == (0, b'', b''):
        return 'allow'
    if (r.returncode == 2 and not r.stdout and lines and b'--role' in lines[-1] and b'--stage' in lines[-1]
            and all(re.match(rb'- OR\d+ ', l) for l in lines[:-1])):
        ids = [l.split()[1].decode() for l in lines[:-1]]
        if len(set(ids)) == len(ids) and all(rule(i) == l for i, l in zip(ids, lines[:-1])):
            return 'deny ' + ','.join(ids)
    return 'other (exit %s, stdout %s bytes, stderr %r)' % (r.returncode, len(r.stdout), r.stderr.decode()[:160])

def round6_prose_cases():
    # Prose is not shell: an apostrophe or double quote in a sentence that
    # mentions the emitter must not hide the line-start commands after it.
    # (label, opener line or None, closer line, quote opened)
    C = '/c/model-record-emit.sh'
    openers = [
        ('apostrophe after mention', "Run model-record-emit.sh and paste its output as your report's first line:", "Don't type it by hand."),
        ('apostrophe before and after mention', "Don't retype it: run model-record-emit.sh and paste it as the report's first line:", "Don't type it by hand."),
        ('several apostrophes after mention', "Run model-record-emit.sh; don't edit it, it's the report's first line:", "It's checked."),
        ('double quote after mention', 'Run model-record-emit.sh and paste its output under "Model record:', 'That ends the block".'),
        ('backtick mention, apostrophe after', "Run `model-record-emit.sh` and paste its output as your report's first line:", "Don't type it by hand."),
        ('apostrophe in trailing comment', None, "It's done."),
        ('control: balanced apostrophes after mention', "Run model-record-emit.sh; don't edit it, it's fixed:", "Don't type it by hand."),
        ('control: balanced double quotes after mention', 'Run model-record-emit.sh and paste the "Model record" line:', 'That ends the block.'),
    ]
    good, wrong = {'role': '--role Product --model m', 'stage': '--stage Discovery --model m'}, \
                  {'role': '--role Architect --model m', 'stage': '--stage Planning --model m'}
    kinds = [  # (label, prefix line, mismatch flag kind or None, recorded verdict)
        ('missing prefix', False, None, 'deny OR8'),
        ('correct brief', True, None, 'allow'),
        ('hidden role mismatch', True, 'role', 'deny OR31'),
        ('hidden stage mismatch', True, 'stage', 'deny OR31'),
    ]
    cases = []
    for olabel, opener, closer in openers:
        for klabel, prefixed, mismatch, expected in kinds:
            for span in [1, 2]:
                for position in ([None] if mismatch is None else range(span)):
                    for tail in [False, True]:
                        cmds = [C + ' ' + (wrong[mismatch] if i == position else good['role'])
                                for i in range(span)]
                        lines = ['ROLE SESSION: Product'] if prefixed else []
                        lines.append('You are Product for #12.')
                        if opener is None:
                            # The opener is a correct command whose bash comment holds the apostrophe.
                            lines.append(C + ' ' + good['role'] + "   # don't edit")
                        else:
                            lines.append(opener)
                        lines += cmds + [closer] + ([C + ' ' + good['role']] if tail else [])
                        cases.append({'opener': olabel, 'kind': klabel, 'span': span, 'tail': tail,
                                      'position': position, 'expected': expected,
                                      'text': '\n'.join(lines) + '\n',
                                      'label': 'round-6 prose %s, %s, %d command(s) in span%s, %s' % (
                                          olabel, klabel, span,
                                          '' if position is None else ', mismatch at %d' % position,
                                          'correct command after' if tail else 'nothing after')})
    return cases

def round6_briefs():
    # Short synthetic briefs shaped like real orchestrator dispatches: prose
    # with apostrophes around the line-start command. (label, text, recorded verdict)
    C = '/c/skills/pre-merge-review/model-record-emit.sh'
    qa = ("ROLE SESSION: QA\nYou are the QA role (stage Test). Don't run git write commands.\n"
          "Read the Reviewer's findings first. The report's first line is the output of\n"
          "model-record-emit.sh, which you'll run as:\n%s\n"
          "Don't paraphrase it; it's checked by the gate.\n")
    dev = ("ROLE SESSION: Fullstack Developer\nFix the Reviewer's finding on PR #601.\n"
           "First line of the report: model-record-emit.sh output (it's mandatory):\n%s\n"
           "Then run the tests. Don't push; the orchestrator's session does.\n")
    rev = ("Review PR #601 at head 4ef7c95d398e. Run finding-carryforward-gate.sh 601 first.\n"
           "Paste model-record-emit.sh's output as the review's first line:\n%s\n"
           "Don't approve on a red gate.\n")
    return [
        ('QA brief, matching role', qa % (C + ' --role QA --model <id>'), 'allow'),
        ('QA brief, stage of another role', qa % (C + ' --stage Planning --model <id>'), 'deny OR31'),
        ('Developer brief, matching role with comment', dev % (C + " --role Developer --model <id>  # don't edit"), 'allow'),
        ('Developer brief, role of another role', dev % (C + ' --role Architect --model <id>'), 'deny OR31'),
        ('Reviewer brief without prefix', rev % (C + ' --role Reviewer --model <id> --floor-basis x'), 'deny OR8'),
    ]

def round6_quoted_apostrophes():
    # A legitimately quoted multi-line --model value containing the other
    # quote kind stays one argument; Bash establishes the argv. The prose
    # around it may open quotes of its own: the verdict must not change.
    values = [('double quotes with an apostrophe', '"it' + "'" + 's\nfine"', "it's\nfine"),
              ('double quotes with two apostrophes', '"don' + "'" + 't\nit' + "'" + 's\nok"', "don't\nit's\nok"),
              ('single quotes with a double quote', "'say \"hi\nthere'", 'say "hi\nthere')]
    kinds = [('stage mismatch', '--stage Planning', ['--stage', 'Planning'], 'deny OR31'),
             ('repeated role', '--role Architect', ['--role', 'Architect'], 'deny OR31'),
             ('matching stage', '--stage Discovery', ['--stage', 'Discovery'], 'allow')]
    proses = [('no prose', '', ''),
              ('apostrophe prose around', "Run model-record-emit.sh as your report's first line:\n", "Don't type it by hand.\n")]
    cases = []
    for vlabel, spelling, value in values:
        for klabel, flag, argv, expected in kinds:
            for slabel, sep in [('space', ' '), ('cont1', ' ' + chr(92) + '\n')]:
                for plabel, before, after in proses:
                    flags = '--role Product --model ' + spelling + sep + flag
                    text = ('ROLE SESSION: Product\n' + before + '/c/model-record-emit.sh ' + flags + '\n' + after)
                    cases.append({'flags': flags, 'argv': ['--role', 'Product', '--model', value] + argv,
                                  'text': text, 'expected': 'unchecked',
                                  'label': 'round-6 quoted %s, %s, %s, %s' % (vlabel, klabel, slabel, plabel)})
    return cases

def round6_dispatch(previous):
    from concurrent.futures import ThreadPoolExecutor
    started = time.monotonic()
    prose = round6_prose_cases()
    briefs = [{'label': 'round-6 brief ' + l, 'text': t, 'expected': e} for l, t, e in round6_briefs()]
    quoted_cases = round6_quoted_apostrophes()
    pinned = prose + briefs
    with ThreadPoolExecutor(max_workers=8) as pool:
        current = list(pool.map(lambda c: verdict(hook(c['text'])), pinned))
        quoted_results = list(pool.map(lambda c: hook(c['text']), quoted_cases))
        before = (list(pool.map(lambda c: verdict(hook(c['text'], previous)), pinned))
                  if previous is not None else [None] * len(pinned))
        shells = list(pool.map(lambda c: run(['bash', '-c', 'set -- ' + c['flags'] + '; printf "%s\\0" "$@"']),
                               quoted_cases))
    groups = {}
    for case, now, then in zip(pinned, current, before):
        if then is not None:
            # Same verdict as before the structural change: the recorded
            # expectation is the previous head's verdict, checked here.
            check(then == case['expected'], case['label'] + ': recorded expectation ' + case['expected'] +
                  ' must equal previous head ' + PREVIOUS_HEAD + ' verdict ' + then)
        ok = check(now == case['expected'], case['label'] + ': expected ' + case['expected'] + ', got ' + now)
        if 'opener' in case:
            keys = ['opener ' + case['opener'], 'kind ' + case['kind'], 'span %d' % case['span'],
                    'tail ' + ('command' if case['tail'] else 'none')]
        else:
            keys = ['briefs' if case in briefs else 'quoted apostrophe values']
        for key in keys:
            tally = groups.setdefault(key, [0, 0])
            tally[0] += not ok
            tally[1] += 1
    for case, result in zip(quoted_cases, quoted_results):
        unchecked(result, case['label'] + ': no implicit quoted continuation')
    for case, sh in zip(quoted_cases, shells):
        check((sh.returncode, sh.stdout, sh.stderr) ==
              (0, b''.join(x.encode() + b'\0' for x in case['argv']), b''), case['label'] + ': Bash complete argv')
    # The comment is bash's, not part of the argv: independent of the hook.
    sh = run(['bash', '-c', "set -- --role Product --model m   # don't edit\nprintf '%s\\0' \"$@\""])
    check((sh.returncode, sh.stdout) == (0, b'--role\0Product\0--model\0m\0'), 'round-6 Bash: trailing comment is no argument')
    for key, (red, total) in sorted(groups.items()):
        print('RESULT: round-6 %s: %d/%d %s' % (key, red, total, 'RED' if red else 'GREEN'))
    print('TIMING: round-6 prose, brief and quoted-apostrophe cases: %d cases, %.3f s' % (
        len(pinned) + len(quoted_cases), time.monotonic() - started))
    # The Reviewer's four scenarios verbatim, pinned to the previous head's verdicts.
    C = '/c/model-record-emit.sh'
    a = ("You are Product for #12.\nRun model-record-emit.sh and paste its output as your report's first line:\n"
         + C + " --role Product --model <id>\nDon't type it by hand.\n")
    reviewer = [
        ('(a) missing prefix', a, 'deny OR8'),
        ('(b) correct brief', 'ROLE SESSION: Product\n' + a, 'allow'),
        ('(c) role mismatch', "ROLE SESSION: Product\nRun model-record-emit.sh and paste its output as your report's first line:\n"
         + C + " --role Architect --model m\nDon't type it by hand.\n" + C + ' --role Product --model m\n', 'deny OR31'),
        ('(c) Reviewer variant', "ROLE SESSION: Reviewer\nPR #42, head 0123abcdef, finding-carryforward-gate.sh 42\n"
         "Run model-record-emit.sh and paste its output as your report's first line:\n" + C +
         " --stage Planning --model m\nDon't type it by hand.\n" + C + ' --role Reviewer --model m --floor-basis x\n', 'deny OR31'),
        ('(d) comment apostrophe', 'ROLE SESSION: Product\n' + C + " --role Product --model m   # don't edit\n" +
         C + " --stage Planning --model m\nIt's done.\n", 'deny OR31'),
    ]
    for label, text, expected in reviewer:
        label = 'round-6 Reviewer scenario ' + label
        if previous is not None:
            then = verdict(hook(text, previous))
            check(then == expected, label + ': recorded ' + expected + ' must equal previous head verdict ' + then)
        before_count = len(failures)
        now = verdict(hook(text))
        check(now == expected, label + ': expected ' + expected + ', got ' + now)
        print('RESULT: ' + label + ': ' + ('RED' if len(failures) > before_count else 'GREEN'))
    # role-unterminated-continuation: a quote that never closes, with a continued
    # flag after it. Bash itself fails here, so the existing malformed-input
    # rule requires exit 0 and exactly one unchecked diagnostic.
    for qlabel, quote in [('double', '"'), ('single', "'")]:
        text = 'ROLE SESSION: Product\n' + C + ' --role Product --model ' + quote + 'x ' + chr(92) + '\n--stage Planning\n'
        label = 'round-6 unterminated %s-quoted model with continued stage' % qlabel
        sh = run(['bash', '-n', '-c', 'set -- --role Product --model ' + quote + 'x ' + chr(92) + '\n--stage Planning'])
        check(sh.returncode != 0, label + ': Bash must reject the unterminated quote')
        r = hook(text)
        lines = r.stderr.splitlines()
        noted = (r.returncode == 0 and not r.stdout and len(lines) == 1 and b'dispatch allowed unchecked' in lines[0])
        before_count = len(failures)
        check(noted, label + ': expected exit 0 and exactly one '
              '"dispatch allowed unchecked" diagnostic, not a silent allow; got ' + verdict(r))
        print('RESULT: ' + label + ': ' + ('RED' if len(failures) > before_count else 'GREEN'))
        if previous is not None:
            print('OBSERVATION: previous head ' + label + ': ' + verdict(hook(text, previous)))
    # Observation only: the same double quote without the backslash was a silent
    # allow on the previous head as well; no oracle pinned.
    text = 'ROLE SESSION: Product\n' + C + ' --role Product --model "x \n--stage Planning\n'
    print('OBSERVATION: unterminated double quote, newline without backslash: current ' + verdict(hook(text)) +
          ('' if previous is None else '; previous head ' + verdict(hook(text, previous))))

def dispatch():
    for prefix,role,stage in ROWS:
        allowed(prompt(prefix,'--role '+role),role+' role-only')
        allowed(prompt(prefix,'--stage '+stage),role+' legacy-stage control')
    for flags in ['--model test-model','--role Fullstack','--role=Product','--roles Product']:
        denied(prompt('Product',flags),['OR31'],'no-valid-form '+flags)
    denied('/c/model-record-emit.sh --role Product\n',['OR8'],'role-only detection without prefix')
    # Exact word guard: neither typo alone triggers detection without a prefix.
    for flags in ['--roles Product','--role=Product']:
        allowed('/c/model-record-emit.sh '+flags,'detection word guard '+flags)
    allowed(prompt('Product','--stage=Discovery'),'kept legacy --stage=X hook recognition gap')
    baseline = historical_baseline('main-dispatch', [HOOK, ORCH, TSV])
    for suffix in TERMINATORS:
        label='terminator '+repr(suffix or 'EOL')
        text=terminated_prompt('--stage Discovery',suffix)
        if baseline is not None:
            allowed(text,'main stage '+label,baseline)
        allowed(text,'current stage '+label)
        allowed(terminated_prompt('--role Product',suffix),'current role '+label)
    for quote in ['"', "'"]:
        allowed(prompt('Product','--role '+quote+'Product'+quote),'properly quoted role '+quote)
        allowed(prompt('Product','--stage '+quote+'Discovery'+quote),'properly quoted stage '+quote)
        for value in ['Product Architect','Product ']:
            label='quoted role '+repr(quote+value+quote)
            denied(prompt('Product','--role '+quote+value+quote),['OR31'],label)
            refusal(['--role',value,'--model','m'],label+' emitter control',['role'])
    # Literal shell spellings exercise the public prompt boundary. Confirm Bash's
    # complete argv independently so a truncated scanner cannot define the oracle.
    concatenated = [
        ('Product', 'Product', '"Product"" Architect"', 'Product Architect'),
        ('Product', 'Product', "'Product'' '", 'Product '),
        ('Product', 'Product', '"Product"\\ Architect', 'Product Architect'),
    ] + [(prefix, role, '"' + role + '"" extra"', role + ' extra')
         for prefix, role, _ in ROWS if role != 'Product']
    for prefix, role, spelling, value in concatenated:
        label = 'concatenated role ' + role + ' ' + repr(spelling)
        shell = run(['bash', '-c', 'set -- ' + spelling +
                     '; printf "%s\\n" "$#"; printf "%s" "$1"'])
        check((shell.returncode, shell.stdout, shell.stderr) ==
              (0, b'1\n' + value.encode(), b''), label + ': Bash must join one complete argument')
        denied(prompt(prefix, '--role ' + spelling), ['OR31'], label)
        refusal(['--role', value, '--model', 'm'], label + ' emitter control', ['role'])
    # Bash joins this to the exact allowed role, so the correct verdict is allow.
    spelling = '"Prod""uct"'
    shell = run(['bash', '-c', 'set -- ' + spelling +
                 '; printf "%s\\n" "$#"; printf "%s" "$1"'])
    check((shell.returncode, shell.stdout, shell.stderr) == (0, b'1\nProduct', b''),
          'concatenated valid role: Bash must join Product')
    allowed(prompt('Product', '--role ' + spelling), 'concatenated valid role ' + spelling)
    r = emit(['--role', 'Product', '--model', 'm'])
    check((r.returncode, r.stderr) == (0, b'') and bool(r.stdout),
          'concatenated valid role emitter control: complete Product must succeed')
    # Stage concatenations are observations only, including their main behavior.
    for spelling in ['"Discovery"" extra"', "'Discovery'' '", '"Discovery"\\ extra']:
        text = prompt('Product', '--stage ' + spelling)
        if baseline is None:
            continue
        a, b = hook(text, baseline), hook(text)
        print('OBSERVATION: concatenated stage ' + repr(spelling) +
              ': main exit=' + str(a.returncode) + ', current exit=' + str(b.returncode) +
              '; main stdout bytes=' + str(len(a.stdout)) + ', stderr lines=' + str(len(a.stderr.splitlines())) +
              '; current stdout bytes=' + str(len(b.stdout)) + ', stderr lines=' + str(len(b.stderr.splitlines())) +
              '; no stage hook oracle pinned')
    # Observations only: main already accepts these invalid stage arguments.
    # Do not silently promote that pre-existing gap into a new hook rule.
    for value in ['Discovery extra','Discovery ']:
        text=prompt('Product','--stage "'+value+'"')
        if baseline is not None:
            a,b=hook(text,baseline),hook(text)
            print('QUESTION: quoted stage '+repr(value)+': main exit='+str(a.returncode)+
                  ', current exit='+str(b.returncode)+'; main silent='+str(not a.stdout and not a.stderr)+
                  ', current silent='+str(not b.stdout and not b.stderr)+'; no hook oracle pinned')
        refusal(['--stage',value,'--model','m'],'quoted stage emitter control '+repr(value),['stage'])
    round3_dispatch(baseline)
    round4_dispatch(baseline)
    round5_emitter_controls()
    round6_dispatch(previous_head_baseline())
    round7_dispatch()
    round8_escaped_whitespace()

def agreement():
    # #595: preserve the legacy prompt shape; denial must come from OR31.
    denied(prompt('Product','--stage Planning'),['OR31'],'exact #595 stage-only mismatch')
    denied(prompt('Product','--role Product --stage Planning'),['OR31'],'contradictory flags')
    denied(prompt('Product','--role Architect'),['OR31'],'prefix versus role')
    allowed(prompt('Fullstack Developer','--role Developer'),'Fullstack Developer alias')
    for suffix in TERMINATORS:
        for flags in ['--stage Planning','--role Architect']:
            denied(terminated_prompt(flags,suffix),['OR31'],'mismatch '+flags+' terminator '+repr(suffix or 'EOL'))

def pairs():
    for _,role,expected in ROWS:
        args=model(role)
        stageonly=emit(['--stage',expected]+args)
        literal=('<!-- model-record: stage='+expected+' model="test-model"'+
                 (' floor-basis="same capability as Implementation"' if role=='Reviewer' else '')+' -->\n').encode()
        check((stageonly.returncode,stageonly.stdout,stageonly.stderr)==(0,literal,b''),role+' literal legacy marker control')
        for flags in [['--role',role],['--role',role,'--stage',expected],['--stage',expected,'--role',role]]:
            r=emit(flags+args)
            check((r.returncode,r.stdout,r.stderr)==(0,literal,b''),role+' diagonal/order '+str(flags)+': marker must be byte-identical and stderr empty')
        for _,_,stage in ROWS:
            if stage!=expected:
                refusal(['--role',role,'--stage',stage]+args,'off-diagonal '+role+'/'+stage,[role,stage,expected])
    # Isolate refusal precedence by comparing the exact established downstream reason.
    downstream=emit(['--stage','Review','--model','test-model'])
    r=refusal(['--role','Reviewer','--stage','Review','--model','test-model'],'matching Reviewer missing floor',['floor-basis'])
    check(r.stderr==downstream.stderr,'matching Reviewer must reach marker_emit reason unchanged')
    refusal(['--role','Product','--stage','Planning','--model','bad model'],'mismatch before marker validation',['Product','Planning','Discovery'])
    refusal(['--role','Product','--stage','Planning','--model','m','--bogus','x'],'parse before mismatch',['unknown','--bogus'])

def compatibility():
    baseline = historical_baseline('baseline', [EMIT, 'lib/model-record.sh',
        'skills/pre-merge-review/model-record-gate.sh', 'compliance-evidence.sh'], merge_base=True)
    if baseline is not None:
        for _,role,stage in ROWS:
            for extra in [[],['--effort','low']]:
                args=['--stage',stage]+model(role)+extra
                a,b=emit(args),emit(args,baseline)
                check((a.returncode,a.stdout,a.stderr)==(b.returncode,b.stdout,b.stderr),role+' stage-only baseline bytes/status/effort')
        for args in [[],['--stage','wrong','--model','m'],['--stage','Review','--model','m'],['--stage']]:
            a,b=emit(args),emit(args,baseline)
            check((a.returncode,a.stdout)==(b.returncode,b.stdout),'legacy refusal exit/stdout '+str(args))
    # Kill a mandatory-role regression while keeping the original stage-only control.
    mutant=copy('role-required'); p=mutant/EMIT
    s=p.read_text();needle='while [ $# -gt 0 ]; do';assert needle in s
    p.write_text(s.replace(needle,'case " $* " in *" --role "*) : ;; *) echo "MUTANT role required" >&2; exit 2 ;; esac\n'+needle,1))
    r=emit(['--stage','Planning','--model','m'],mutant)
    check(r.returncode==2 and not r.stdout and r.stderr==b'MUTANT role required\n','stage-only oracle must kill role-required mutation')
    # The gate and collector remain byte-identical to the merge-base; reader grammar is
    # exercised by S204, not duplicated here as an implementation-text oracle.
    for f in ['skills/pre-merge-review/model-record-gate.sh','compliance-evidence.sh']:
        if baseline is not None:
            check((baseline/f).read_bytes()==(ROOT/f).read_bytes(),'AC7 unchanged '+f)

def bad_inputs():
    for value in ['product','Fullstack','Fullstack Developer','Discovery','Planning','Test','Implementation','Review','']:
        refusal(['--role',value,'--model','m'],'invalid role '+repr(value),['role'])
    for args,label,words in [
        (['--role=Product','--model','m'],'equals role',['unknown']),
        (['--roles','Product','--model','m'],'plural flag',['unknown']),
        (['--role','Product','--role','Product','--model','m'],'repeat',['twice']),
        (['--model','m','--role'],'valueless',['value']),
        (['--model','m'],'neither',['--role','--stage','required']),
        (['--role','Developer','--model','m','--floor-basis','basis'],'Developer floor',['floor-basis']),
    ]: refusal(args,label,words)
    flags=['--role','--stage','--model','--effort','--floor-basis']
    for flag in flags:
        refusal(['--role',flag,'--model','m'],'role flag-as-value '+flag,['value'])
        refusal(['--stage','Planning','--model',flag],'model flag-as-value '+flag,['value'])
    r=emit(['--role','Product','--model','m'])
    check((r.returncode,r.stderr)==(0,b''),'success stderr empty')
    r=refusal(['--role','Product\nArchitect','--model','m'],'newline role',['role'])
    check(r.stderr.count(b'Product')>=2 and r.stderr.count(b'Architect')>=2,
          'newline role: reason must retain both offending input components beyond the allowed-role list')
    r=refusal(['--role','Product','--stage','Discovery\nArchitect','--model','m'],
              'newline supplied stage',['Product','Discovery','Architect'])
    check(r.stderr.count(b'Discovery')>=2,
          'newline supplied stage: reason must retain supplied Discovery as well as expected Discovery')

def quoted():
    # CURRENT DEFAULT PENDING TiesL's decision: flip this ONE assertion if quoted
    # commands become exempt. Other multi-line agreement arms remain mandatory.
    denied(prompt('Product','--stage Discovery')+'\n```sh\n/c/model-record-emit.sh --stage Planning\n```\n',
           ['OR31'],'CURRENT DEFAULT pending TiesL: quoted other-role command denied')
    denied(prompt('Product','--stage Discovery')+'\n/c/model-record-emit.sh --stage Planning\n',
           ['OR31'],'several emit lines one mismatch')
    denied(prompt('Product','--role Product')+'\n/c/model-record-emit.sh --role Architect\n',
           ['OR31'],'several role emit lines one mismatch')
    # A missing prefix fails OR8 only: role-stage must be inapplicable.
    denied('/c/model-record-emit.sh --stage Planning\n',['OR8'],'no prefix cross-check inapplicable')

def drift_errors(root):
    errors=[]
    r=run(['python3','-I',root/HOOK,'--list-roles'],root)
    # Output delimiter is deliberately not pinned; the public rows carry three fields,
    # and the prefix is the only two-word field. No new JSON interface is assumed.
    rows=[]
    for line in r.stdout.decode().splitlines():
        m=re.fullmatch(r'(Product|Architect|QA|Fullstack Developer|Reviewer)\s+(Product|Architect|QA|Developer|Reviewer)\s+(Discovery|Planning|Test|Implementation|Review)',line)
        if m:rows.append(m.groups())
    if r.returncode or r.stderr or rows!=ROWS:errors.append('hook rows')
    for prefix,role,stage in ROWS:
        r=run(['bash','-c','. "$1/lib/model-record.sh"; role_stage "$2"','fixture',str(root),role],root)
        if (r.returncode,r.stdout,r.stderr)!=(0,(stage+'\n').encode(),b''):errors.append('lib '+role)
        line=next((l for l in (root/ORCH).read_text().splitlines() if l.startswith('- OR5 ')),'')
        label={'Product':'product','Architect':'architect','QA':'qa','Developer':'dev','Reviewer':'reviewer'}[role]
        if stage+'/'+prefix+'/`role:'+label+'`/'+stage not in line:errors.append('OR5 '+role)
    return errors

def drift():
    check(not drift_errors(ROOT),'AC9 role rows, role_stage and OR5 must agree: '+str(drift_errors(ROOT)))
    for path,kind in [(HOOK,'hook'),('lib/model-record.sh','lib'),(ORCH,'OR5')]:
        mutant=copy('drift-'+kind);p=mutant/path;s=p.read_text()
        # Change a stage token in the map source, not a comment or another interface.
        if kind=='OR5':
            lines=s.splitlines(True);hits=[i for i,l in enumerate(lines) if l.startswith('- OR5 ')];assert len(hits)==1
            i=hits[0];assert 'Discovery/Product' in lines[i];lines[i]=lines[i].replace('Discovery/Product','Planning/Product',1);s=''.join(lines)
        else:
            if kind=='lib':
                match=re.search(r'^role_stage\s*\(\)\s*\{',s,re.M)
                if not match:
                    check(False,'AC9 mutation unavailable: role_stage not implemented');continue
                start=match.start()
            else:
                # One tuple owns the rows. Find its Product row, regardless of tuple name.
                match=re.search(r'[\(\[]\s*[\'\"]Product[\'\"]\s*,\s*[\'\"]Product[\'\"]\s*,\s*[\'\"]Discovery[\'\"]',s)
                if not match:
                    check(False,'AC9 mutation unavailable: hook role tuple not implemented');continue
                start=match.start()
            tail=s[start:];assert 'Discovery' in tail;s=s[:start]+tail.replace('Discovery','Planning',1)
        p.write_text(s)
        check(bool(drift_errors(mutant)),'AC9 must kill '+kind+' map mutation')

def doc_errors(root):
    errors=[]
    text=(root/ORCH).read_text(); line=next(l for l in text.splitlines() if l.startswith('- OR31 '))
    if '--role' not in line or 'OR5' not in line or not re.search(r'agree|match',line,re.I):errors.append('OR31 role, OR5 and agreement')
    if '--stage' in line and not re.search(r'compatib|old|legacy',line,re.I):errors.append('OR31 unlabelled legacy stage')
    if re.search(r'model-record: stage=|stage="',text):errors.append('ORCHESTRATOR grammar copy')
    for l in text.splitlines():
        if not l.startswith('- OR5 ') and re.search(r'(Discovery/Product|Planning/Architect|Implementation/Fullstack Developer)',l):errors.append('stage table duplicated outside OR5')
    for path,role in [('skills/model-choice/SKILL.md','<Role>'),('skills/pre-merge-review/SKILL.md','Reviewer')]:
        t=' '.join((root/path).read_text().split())
        if not re.search(r'model-record-emit\.sh --role '+re.escape(role),t):errors.append(path+' instructs role')
        for m in re.finditer(r'model-record-emit\.sh --stage',t):
            if not re.search(r'backward.compatib|old prompts|legacy',t[max(0,m.start()-120):m.end()+120],re.I):errors.append(path+' unlabelled stage command')
    emitter=(root/EMIT).read_text().splitlines()
    if not any(re.search(r'^# +model-record-emit\.sh .*--role',l) for l in emitter):errors.append('emitter header role pin S238')
    if not any(l.startswith('usage=') and '--role' in l for l in emitter):errors.append('emitter usage role pin S238')
    return errors

def docs():
    check(not doc_errors(ROOT),'AC6 doc pins: '+str(doc_errors(ROOT)))
    # Mutation oracles execute independently of baseline failures, with a conforming
    # text-only fixture. Never patch product files in the working tree.
    root=copy('docs');
    for path in ['skills/model-choice/SKILL.md','skills/pre-merge-review/SKILL.md']:
        (root/path).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/path,root/path)
    p=root/ORCH;s=p.read_text();s=re.sub(r'^- OR31 .*$', '- OR31 Give the role the model-record-emit.sh command with --role filled in; emit role and stage match the prefix role. Role mapping: OR5.',s,flags=re.M);p.write_text(s)
    for path in ['skills/model-choice/SKILL.md','skills/pre-merge-review/SKILL.md']:
        p=root/path;p.write_text(p.read_text().replace('--stage <Stage>','--role <Role>').replace('--stage Review','--role Reviewer'))
    p=root/EMIT
    p.write_text('\n'.join(l.replace('--stage <Stage>','--role <Role>') if l.startswith('usage=') or re.search(r'^# +model-record-emit\.sh ',l) else l for l in p.read_text().split('\n')))
    check(not doc_errors(root),'doc mutation positive control must pass')
    for label in ['header','usage']:
        p=root/EMIT;saved=p.read_text()
        p.write_text('\n'.join(l.replace('--role','--stage') if (l.startswith('usage=') if label=='usage' else bool(re.search(r'^# +model-record-emit\.sh ',l))) else l for l in saved.split('\n')))
        check('emitter '+label+' role pin S238' in doc_errors(root),'AC6 must kill S238 '+label+' mutation')
        p.write_text(saved)
    for path,old,new in [(ORCH,'--role','--stage'),(ORCH,'Role mapping: OR5.','Role mapping removed.'),
                         (ORCH,'match the prefix role','ignore the prefix role'),
                         ('skills/model-choice/SKILL.md','--role <Role>','--stage <Stage>'),
                         ('skills/pre-merge-review/SKILL.md','--role Reviewer','--stage Review')]:
        p=root/path;s=p.read_text();assert old in s;p.write_text(s.replace(old,new))
        check(bool(doc_errors(root)),'AC6 must kill doc mutation '+path+' '+old);p.write_text(s)

fixture_started = time.monotonic()
{'dispatch':dispatch,'agreement':agreement,'pairs':pairs,'compatibility':compatibility,
 'bad':bad_inputs,'quoted':quoted,'drift':drift,'docs':docs}[sys.argv[1]]()
if sys.argv[1] == 'dispatch':
    print('TIMING: S412 total %.3f s' % (time.monotonic() - fixture_started))
print('Assertions: '+str(assertions-len(failures))+' passed, '+str(len(failures))+' failed')
sys.exit(bool(failures))

"""Public CLI/dispatch/doc seams for #599. No product writes; mutations use scratch copies."""
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
        if valid:
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
    # Truly malformed input retains the general fail-open policy, unlike the
    # well-formed multiline words above. Pin its single visible diagnostic.
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
    # The 1 MB role takes ~17 s with the reviewed lexer, versus tens of ms
    # for an ordinary line. A linear validator has ample CI headroom at this
    # size. Kill at 2.5 s, leaving a 0.5 s margin below the asserted 3 s budget
    # and 7 s below the configured fail-open runtime timeout. A killed process
    # has not denied anything: timeout must fail, never count as exit 2.
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

{'dispatch':dispatch,'agreement':agreement,'pairs':pairs,'compatibility':compatibility,
 'bad':bad_inputs,'quoted':quoted,'drift':drift,'docs':docs}[sys.argv[1]]()
print('Assertions: '+str(assertions-len(failures))+' passed, '+str(len(failures))+' failed')
sys.exit(bool(failures))

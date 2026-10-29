"""Public CLI/dispatch/doc seams for #599. No product writes; mutations use scratch copies."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

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

def check(ok, reason):
    if not ok:
        failures.append(reason)
        print('FAIL: ' + reason)
    return ok

def run(args, root=ROOT, data=None):
    return subprocess.run([str(x) for x in args], cwd=root, input=data,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)

def emit(args, root=ROOT):
    return run([root / EMIT] + args, root)

def model(role):
    return ['--model', 'test-model'] + (['--floor-basis', 'same capability as Implementation'] if role == 'Reviewer' else [])

def prompt(prefix, flags):
    return ('ROLE SESSION: ' + prefix + '\n\nQuoted contract.\n/c/model-record-emit.sh ' + flags +
            '\nPR #42, head 0123abcdef, finding-carryforward-gate.sh 42\n')

def hook(text, root=ROOT):
    data = {'tool_name': 'Agent', 'tool_input': {'prompt': text, 'model': 'test-model', 'subagent_type': 'general-purpose'}}
    return run(['python3', '-I', root / HOOK, root / ORCH, root / TSV], root, json.dumps(data).encode())

def rule(n, root=ROOT):
    return next(l.encode() for l in (root / ORCH).read_text().splitlines() if l.startswith('- ' + n + ' '))

def allowed(p, label):
    r=hook(p)
    check((r.returncode,r.stdout,r.stderr)==(0,b'',b''), label + ': expected silent allow')

def denied(p, ids, label):
    r=hook(p); lines=r.stderr.splitlines()
    check(r.returncode==2 and not r.stdout, label + ': expected exit 2 and empty stdout')
    expected=[rule(i) for i in ids]
    check(lines[:-1]==expected and len(lines)==len(expected)+1, label + ': expected only ' + ','.join(ids) + ' core lines once plus AVOID')
    check(bool(lines) and b'--role' in lines[-1] and b'--stage' in lines[-1], label + ': AVOID must cover role and stage')

def refusal(args, label, words=(), root=ROOT):
    r=emit(args,root)
    check(r.returncode==2 and r.stdout==b'' and len(r.stderr.splitlines())==1,
          label + ': expected exit 2, empty stdout, one stderr reason')
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

def agreement():
    # #595: preserve the legacy prompt shape; denial must come from OR31.
    denied(prompt('Product','--stage Planning'),['OR31'],'exact #595 stage-only mismatch')
    denied(prompt('Product','--role Product --stage Planning'),['OR31'],'contradictory flags')
    denied(prompt('Product','--role Architect'),['OR31'],'prefix versus role')
    allowed(prompt('Fullstack Developer','--role Developer'),'Fullstack Developer alias')

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
    baseline=copy('baseline')
    base=run(['git','merge-base','HEAD','main']).stdout.decode().strip()
    check(bool(base),'baseline merge-base must resolve')
    for f in [EMIT,'lib/model-record.sh']:
        r=run(['git','show',base+':'+f]);check(r.returncode==0,'baseline git show '+f)
        (baseline/f).write_bytes(r.stdout)
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
        r=run(['git','show',base+':'+f])
        check(r.returncode==0 and r.stdout==(ROOT/f).read_bytes(),'AC7 unchanged '+f)

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
sys.exit(bool(failures))

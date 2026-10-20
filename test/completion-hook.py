"""Runtime-shaped hook inputs, real Git refs and recording gh executable."""
import json
import os
from pathlib import Path
import subprocess
import sys

root, box = map(Path, sys.argv[1:])
repo = box / "repo"
repo.mkdir()

def git(*args):
    return subprocess.check_output(["git", "-C", str(repo), *args], stderr=subprocess.DEVNULL, text=True).strip()

git("init", "-q", "--initial-branch=main")
git("-c", "user.name=Test", "-c", "user.email=test@example.test", "commit", "--allow-empty", "-qm", "fixture")
git("tag", "v1")
git("-c", "user.name=Test", "-c", "user.email=test@example.test", "tag", "-am", "annotated", "v2")
git("branch", "branch-only")
bin_dir = box / "bin"
bin_dir.mkdir()
gh = bin_dir / "gh"
gh.write_text("""#!/usr/bin/env python3
import os,json,subprocess,sys,time
args=sys.argv[1:]
if args[:2]==['pr','merge']:
    # Real gh with -d/--delete-branch checks out the default branch and deletes the head.
    if os.environ.get('GH_SWITCH') and ('-d' in args or '--delete-branch' in args):
        old=subprocess.check_output(['git','symbolic-ref','--short','HEAD'],text=True).strip()
        subprocess.check_call(['git','checkout','-q','main'])
        if not os.environ.get('GH_KEEP_BRANCH'): subprocess.check_call(['git','branch','-q','-D',old])
    sys.exit(0)
with open(os.environ['GH_LOG'],'a') as f: f.write(json.dumps(args)+'\\n')
if os.environ.get('GH_FAIL'): sys.exit(1)
if os.environ.get('GH_SLEEP'): time.sleep(6)
print(os.environ['GH_RESULT'])
""")
gh.chmod(0o755)
log = box / "gh.log"
env = dict(os.environ, PATH=str(bin_dir)+os.pathsep+os.environ['PATH'], GH_LOG=str(log))
stop = {"continue": False, "stopReason": "Merged to main. Type /clear before the next work item; if you are tagging a release, tag it first."}

def run(command, expected=None, state="MERGED", base="main", head="feature/500-test", extra=None, response=None, lookup=None, gh_fail=False, gh_sleep=False):
    log.write_text("")
    event = dict(hook_event_name="PostToolUse", tool_name="Bash", cwd=str(repo), tool_input={"command": command}, tool_response=response or {"stdout":"", "stderr":"", "interrupted":False, "isImage":False})
    if extra: event.update(extra)
    e = dict(env, GH_RESULT=json.dumps(lookup if lookup is not None else dict(baseRefName=base,headRefName=head,state=state)))
    if gh_fail: e['GH_FAIL']='1'
    if gh_sleep: e['GH_SLEEP']='1'
    result = subprocess.run([str(root/'hooks/stop-after-completion')], input=json.dumps(event), text=True,capture_output=True,env=e, timeout=5)
    assert result.returncode == 0, (command,result)
    actual=json.loads(result.stdout) if result.stdout.strip() else None
    assert actual == expected, (command,expected,actual,result.stderr)
    if expected is None:
        assert result.stdout == '', (command, result.stdout)
    return [json.loads(line) for line in log.read_text().splitlines()]

def one_lookup(calls, target, fields='baseRefName,state', repo_flag=None):
    expected = [['pr','view',target,'--json',fields]+(['--repo',repo_flag] if repo_flag else [])]
    assert calls == expected, (calls, expected)

def simulate_merge(command, branch, keep_branch=False, commit_after=False):
    """Perform what real `gh pr merge -d` does to the checkout before PostToolUse fires."""
    git('checkout','-q','-B',branch,'main')
    e = dict(env, GH_SWITCH='1')
    if keep_branch: e['GH_KEEP_BRANCH']='1'
    subprocess.run([str(gh), *command.split()[1:], *([] if '-d' in command or '--delete-branch' in command else ['-d'])], cwd=repo, env=e, check=True)
    if commit_after:
        git('-c','user.name=Test','-c','user.email=test@example.test','commit','--allow-empty','-qm','later')

_red = []
class section:
    """Collect failures per behavior so one run lists every red section."""
    def __init__(self, name): self.name = name
    def __enter__(self): return self
    def __exit__(self, kind, exc, tb):
        if kind is not None and issubclass(kind, AssertionError):
            _red.append(self.name); print('RED', self.name, '->', repr(exc)[:300], file=sys.stderr); return True
        return False

with section('S360 quote provenance data-only and literal command words'):
    # S360 quote provenance: offered remote state must never turn arguments into commands.
    for command in [
        'echo ";" "gh" "pr" "merge" "500"',
        "echo ';' 'gh' 'pr' 'merge' '500'",
        r'echo \; gh pr merge 500',
        'echo "&""&" gh pr merge 500',
        'echo "|""|" gh pr merge 500',
        r'echo \&\& gh pr merge 500',
        r'echo \|\| gh pr merge 500',
        'echo "&&" gh pr merge 500',
        'echo "||" gh pr merge 500',
        'echo "\n" gh pr merge 500',
        'echo ";"gh pr merge 500',
        'echo merge # ; gh pr merge 500',
        'printf "%s" "gh pr merge 500"',
        'echo "a \\\n; gh pr merge 500"',
        "echo 'a \\\n; gh pr merge 500'",
        'echo \\\n gh pr merge 500',
    ]:
        assert run(command) == [], command
    for command in ['"gh" "pr" "merge" "500"', "'gh' pr merge 500"]:
        run(command, stop)

with section('S355 stop wording and lookup fields'):
    # S355: exact stop, lookup is baseRefName,state only; the head never matters; release base continues.
    one_lookup(run('gh pr merge 500', stop), '500')
    run('gh pr merge 500',base='release/490-example')
with section('S356 release head into main'):
    # S356: a release head into main stops like any main merge, no additionalContext, same lookup.
    one_lookup(run('gh pr merge 500',stop,head='release/490-example'),'500')
    one_lookup(run('gh pr merge 500',stop,lookup=dict(baseRefName='main',state='MERGED')),'500')

with section('S357 tag commands cause no stop'):
    # S357 AC5 negative: tag commands and publication cause no stop and zero gh calls.
    for command in ['git push origin v1','git push origin refs/tags/v2','git push --tags','git push --follow-tags','git push --follow-tags origin feature/500-test','gh release create v1','gh release create v1 --draft','gh release create absent','git tag v3','git tag -a v4 -m x','git push origin :v1']:
        assert run(command)==[],command
    one_lookup(run('gh pr merge 500 && git push origin v1',stop),'500')
    one_lookup(run('git push origin v1 && gh pr merge 500',stop),'500')

with section('S358 failures and uncertainty'):
    # S358 failures and uncertainty.
    for state in ['OPEN','CLOSED','QUEUED']:
        assert run('gh pr merge 500 --auto',state=state)==[['pr','view','500','--json','baseRefName,state']]
    run('gh pr merge 500',gh_fail=True)
    run('gh pr merge 500',gh_sleep=True)
    run('gh pr merge 500',lookup={})
    for extra in [dict(tool_name='Read'),dict(hook_event_name='PostToolUseFailure')]:
        assert run('gh pr merge 500',extra=extra)==[]
    for response in [dict(interrupted=True),dict(backgroundTaskId='abc'),dict(stdout='',stderr='',interrupted=False,task_id='abc')]:
        assert run('gh pr merge 500',response=response)==[]
    run('gh pr merge "unterminated')
    run('gh pr merge',lookup={})

with section('S359 targets and repository flags'):
    # S359 targets and repository flags.
    for target in ['500','https://github.com/owner/repo/pull/500','feature/500-test']:
        calls=run('gh pr merge '+target+' --squash --delete-branch',stop)
        one_lookup(calls,target)
    for command in ['gh -R owner/repo pr merge 500','gh pr merge 500 --repo owner/repo','gh pr merge --body text --subject title --match-head-commit abc 500 -R owner/repo']:
        one_lookup(run(command,stop),'500',repo_flag='owner/repo')
with section('S359 omitted target, surviving branch'):
    # Omitted target with a surviving current branch.
    git('checkout','-q','-B','feature/500-test','main')
    calls=run('gh pr merge',stop)
    assert calls and calls[0][:3]==['pr','view','feature/500-test'] and len(calls)==1,calls
    git('checkout','-q','main')
    assert run('gh pr merge')==[]
with section('S359 reflog fallback positives and negatives'):
    # Reflog fallback: the canonical omitted target, real gh switched to main and deleted the branch.
    def fallback(branch, command='gh pr merge --squash --delete-branch', expected=stop, head=None, calls_expected=None, **kw):
        git('checkout','-q','main')
        for b in git('branch','--format=%(refname:short)').split():
            if b not in {'main','branch-only'}: git('branch','-q','-D',b)
        simulate_merge(command, branch, **kw)
        return run(command, expected, head=head or branch)
    for branch in ['feature/500-test','fix/500-test','release/490-example']:
        for flag in ['--delete-branch','-d']:
            calls=fallback(branch,'gh pr merge --squash '+flag)
            assert len(calls)==1 and calls[0][:3]==['pr','view',branch] and 'baseRefName' in calls[0][4] and 'state' in calls[0][4] and 'headRefName' in calls[0][4],(branch,flag,calls)
    calls=fallback('feature/500-test','gh pr merge --squash --delete-branch --repo owner/repo')
    assert len(calls)==1 and calls[0][-2:]==['--repo','owner/repo'],calls
    # Negatives: (a) surviving branch, (b) newest reflog entry is not the checkout, (c) no --delete-branch,
    # (d) head mismatch, (e) switched from a branch outside feature/fix/release.
    assert fallback('feature/500-test',expected=None,keep_branch=True)==[]
    assert fallback('feature/500-test',expected=None,commit_after=True)==[]
    assert fallback('feature/500-test','gh pr merge --squash',expected=None)==[]
    fallback('feature/500-test',expected=None,head='feature/another-pr')
    assert fallback('topic/500-test',expected=None)==[]
    git('checkout','-q','main')

with section('S360 masked and provable shell evidence'):
    # S360 shell evidence.
    for command in ['echo "gh pr merge 500"','cat <<EOF\ngh pr merge 500\nEOF','echo "a; gh pr merge 500"','echo "&&"','if false; then gh pr merge 500; fi','false && gh pr merge 500 || true','gh pr merge 500 || true','gh pr merge 500; true','gh pr merge 500 | cat','echo $(gh pr merge 500)']:
        assert run(command)==[],command
    for command in ['true && gh pr merge 500','gh pr merge 500 && true','false; gh pr merge 500','echo "a;b"; gh pr merge 500','gh pr merge 501 || true; gh pr merge 500', 'gh pr merge 500;', 'gh pr merge 500\n']:
        run(command,stop)
with section('S360 redirections stop'):
    # Redirections keep the success proof: stop, one lookup, target 500.
    for command in ['gh pr merge 500 2>&1','gh pr merge 500 >/dev/null','gh pr merge 500 > /dev/null 2>&1','gh pr merge 500 &> /dev/null','gh pr merge 500 >> out.log','gh pr merge 500 2> err.log','true && gh pr merge 500 2>&1']:
        one_lookup(run(command,stop),'500')
with section('S360 pipes and unsupported redirections'):
    # Pipes and unsupported redirections stay uncertain, before any lookup.
    for command in ['gh pr merge 500 2>&1 | tail -3','gh pr merge 500 | cat','gh pr merge 500 < in.txt','gh pr merge 500 > $OUT','gh pr merge 500 <<< x','gh pr merge 500 2>&-']:
        assert run(command)==[],command
with section('S360 line continuation'):
    # Line continuation is lexed, not a literal newline word.
    for command in ['gh pr merge 500 \\\n  --squash --delete-branch','gh pr merge \\\n 500','gh \\\n pr merge 500','gh pr mer\\\nge 500']:
        one_lookup(run(command,stop),'500')

with section('S360 legacy differential'):
    # Legacy differential: the decoded token projection must equal the pinned shlex tokenizer of origin/main.
    import importlib.util, itertools, random, shlex
    legacy_spec = importlib.util.spec_from_file_location('reader', root/'hooks/read-command.py')
    reader = importlib.util.module_from_spec(legacy_spec); legacy_spec.loader.exec_module(reader)
    def legacy_tokenize(text):
        lexer = shlex.shlex(text, posix=True, punctuation_chars=";|&\n")
        lexer.whitespace_split = True
        lexer.whitespace = " \t\r"
        return list(lexer)
    def outcome(fn, text):
        try: return ('ok', fn(text))
        except ValueError as exc: return ('error', str(exc))
    alphabet = list(" \t\n;|&<>$()`#2'\"\\ab=")
    def corpus():
        for n in range(0,4):
            yield from (''.join(c) for c in itertools.product(alphabet, repeat=n))
        rng = random.Random(500)
        for _ in range(20000):
            yield ''.join(rng.choice(alphabet) for _ in range(rng.randint(4,14)))
    checked = 0
    for text in corpus():
        if '\\\n' in text: continue  # the completion reading may join continuations; the guard stream is out of scope
        assert outcome(reader.tokenize, text) == outcome(legacy_tokenize, text), repr(text)
        checked += 1
    assert checked > 20000, checked

if _red:
    print('RED sections:', *_red, sep='\n  ', file=sys.stderr); sys.exit(1)
print('S355-S360: executable behavior passed')

# Malformed payloads remain advisory, including non-dict tool_input.
for payload in ['{', '[]', json.dumps(dict(hook_event_name='PostToolUse',tool_name='Bash',cwd=str(repo),tool_input=[],tool_response={}))]:
    result=subprocess.run([str(root/'hooks/stop-after-completion')],input=payload,text=True,capture_output=True,env=env)
    assert result.returncode==0 and not result.stdout,(payload,result)
# A failed Bash operation uses PostToolUseFailure, not an invented exit_code.
assert run('gh pr merge 500',extra=dict(hook_event_name='PostToolUseFailure'))==[]

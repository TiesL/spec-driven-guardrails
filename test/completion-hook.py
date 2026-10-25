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
# Bare remote like the real one gh pulls from; `upstream` is a second clone that advances it.
remote = box / "remote.git"
subprocess.check_call(["git", "init", "-q", "--bare", "--initial-branch=main", str(remote)], stderr=subprocess.DEVNULL)
git("remote", "add", "origin", str(remote))
git("push", "-q", "origin", "main")
upstream = box / "upstream"
subprocess.check_call(["git", "clone", "-q", str(remote), str(upstream)], stderr=subprocess.DEVNULL)
_squash = [0]
def advance_remote(branch="main"):
    """Give the bare remote one more commit on `branch`, as the squash merge does."""
    _squash[0] += 1
    def up(*a): subprocess.check_call(["git", "-C", str(upstream), "-c", "user.name=Test", "-c", "user.email=test@example.test", *a], stderr=subprocess.DEVNULL)
    if branch == "main": up("checkout", "-q", "main"); up("pull", "-q", "--ff-only", "origin", "main")
    else: up("checkout", "-q", "-B", branch, "origin/main")
    up("commit", "--allow-empty", "-qm", "squash %d" % _squash[0])
    up("push", "-q", "origin", branch)
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
        # Real gh then fast-forwards the base: `git pull --ff-only origin main`, before deleting the head.
        subprocess.call(['git','pull','--ff-only','origin','main'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)  # a failed fast-forward only warns, as in gh
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
REMINDER_TEXT = "Merged to main. Type /clear before the next work item; if you are tagging a release, tag it first."
reminder = {"systemMessage": REMINDER_TEXT}

def run(command, expected=None, state="MERGED", base="main", head="feature/500-test", extra=None, response=None, lookup=None, gh_fail=False, gh_sleep=False, hook=None):
    log.write_text("")
    event = dict(hook_event_name="PostToolUse", tool_name="Bash", cwd=str(repo), tool_input={"command": command}, tool_response=response or {"stdout":"", "stderr":"", "interrupted":False, "isImage":False})
    if extra: event.update(extra)
    e = dict(env, GH_RESULT=json.dumps(lookup if lookup is not None else dict(baseRefName=base,headRefName=head,state=state)))
    if gh_fail: e['GH_FAIL']='1'
    if gh_sleep: e['GH_SLEEP']='1'
    result = subprocess.run([str(hook or root/'hooks/stop-after-completion')], input=json.dumps(event), text=True,capture_output=True,env=e, timeout=5)
    assert result.returncode == 0, (command,result)
    actual=json.loads(result.stdout) if result.stdout.strip() else None
    if expected is not None:
        # #561: a merge into main reminds and never stops the session; say which part broke.
        assert isinstance(actual, dict), (command, 'no reminder output', actual, result.stderr)
        assert 'continue' not in actual, (command, 'output must not contain continue (the stop)', actual)
        assert 'stopReason' not in actual, (command, 'output must not contain stopReason (the stop)', actual)
        assert actual.get('systemMessage') == REMINDER_TEXT, (command, 'systemMessage must be the exact reminder', actual)
    assert actual == expected, (command,expected,actual,result.stderr)
    if expected is None:
        assert result.stdout == '', (command, result.stdout)
    return [json.loads(line) for line in log.read_text().splitlines()]

def one_lookup(calls, target, fields='baseRefName,state', repo_flag=None):
    expected = [['pr','view',target,'--json',fields]+(['--repo',repo_flag] if repo_flag else [])]
    assert calls == expected, (calls, expected)

def simulate_merge(command, branch, keep_branch=False, commit_after=False, squash=True):
    """Perform what real `gh pr merge -d` does to the checkout before PostToolUse fires:
    checkout main, pull --ff-only origin main (a real Fast-forward entry when the remote
    holds the squash commit), delete the head."""
    git('checkout','-q','main'); git('fetch','-q','origin'); git('reset','-q','--hard','origin/main')  # a clean base, like a fresh clone
    git('checkout','-q','-B',branch,'main')
    if squash: advance_remote()
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
        run(command, reminder)

with section('S355 reminder wording and lookup fields'):
    # S355: exact reminder, lookup is baseRefName,state only; the head never matters; release base continues.
    one_lookup(run('gh pr merge 500', reminder), '500')
    run('gh pr merge 500',base='release/490-example')
with section('S356 release head into main'):
    # S356: a release head into main reminds like any main merge, no additionalContext, same lookup.
    one_lookup(run('gh pr merge 500',reminder,head='release/490-example'),'500')
    one_lookup(run('gh pr merge 500',reminder,lookup=dict(baseRefName='main',state='MERGED')),'500')

with section('S357 tag commands cause no reminder'):
    # S357 AC5 negative: tag commands and publication cause no reminder and zero gh calls.
    for command in ['git push origin v1','git push origin refs/tags/v2','git push --tags','git push --follow-tags','git push --follow-tags origin feature/500-test','gh release create v1','gh release create v1 --draft','gh release create absent','git tag v3','git tag -a v4 -m x','git push origin :v1']:
        assert run(command)==[],command
    one_lookup(run('gh pr merge 500 && git push origin v1',reminder),'500')
    one_lookup(run('git push origin v1 && gh pr merge 500',reminder),'500')

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
        calls=run('gh pr merge '+target+' --squash --delete-branch',reminder)
        one_lookup(calls,target)
    for command in ['gh -R owner/repo pr merge 500','gh pr merge 500 --repo owner/repo','gh pr merge --body text --subject title --match-head-commit abc 500 -R owner/repo']:
        one_lookup(run(command,reminder),'500',repo_flag='owner/repo')
with section('S359 omitted target, surviving branch'):
    # Omitted target with a surviving current branch.
    git('checkout','-q','-B','feature/500-test','main')
    calls=run('gh pr merge',reminder)
    assert calls and calls[0][:3]==['pr','view','feature/500-test'] and len(calls)==1,calls
    git('checkout','-q','main')
    assert run('gh pr merge')==[]
# Reflog fallback: the canonical omitted target, real gh switched to main, pulled and deleted the branch.
if True:
    def fallback(branch, command='gh pr merge --squash --delete-branch', expected=reminder, head=None, calls_expected=None, **kw):
        git('checkout','-q','main')
        for b in git('branch','--format=%(refname:short)').split():
            if b not in {'main','branch-only'}: git('branch','-q','-D',b)
        simulate_merge(command, branch, **kw)
        return run(command, expected, head=head or branch)
with section('S359 reflog positives: pull above checkout'):
    for branch in ['feature/500-test','fix/500-test','release/490-example']:
        for flag in ['--delete-branch','-d']:
            calls=fallback(branch,'gh pr merge --squash '+flag)
            assert len(calls)==1 and calls[0][:3]==['pr','view',branch] and 'baseRefName' in calls[0][4] and 'state' in calls[0][4] and 'headRefName' in calls[0][4],(branch,flag,calls)
    calls=fallback('feature/500-test','gh pr merge --squash --delete-branch --repo owner/repo')
    assert len(calls)==1 and calls[0][-2:]==['--repo','owner/repo'],calls
with section('S359 reflog fixture shape'):
    # Guard the fixture itself: real gh leaves `pull ... Fast-forward` above the checkout.
    git('checkout','-q','main')
    for b in git('branch','--format=%(refname:short)').split():
        if b not in {'main','branch-only'}: git('branch','-q','-D',b)
    simulate_merge('gh pr merge --squash --delete-branch','feature/500-test')
    assert git('reflog','-2','--format=%gs','HEAD').splitlines()==['pull --ff-only origin main: Fast-forward','checkout: moving from feature/500-test to main'],git('reflog','-3','--format=%gs','HEAD')
with section('S359 reflog checkout-only positive'):
    # The remote had nothing to fast-forward, so the pull wrote no entry: the checkout is the newest.
    calls=fallback('feature/500-test',squash=False)
    assert git('reflog','-1','--format=%gs','HEAD')=='checkout: moving from feature/500-test to main'
    assert len(calls)==1 and calls[0][:3]==['pr','view','feature/500-test'] and 'headRefName' in calls[0][4],calls
with section('S359 negatives a-e'):
    # (a) surviving branch, (b) newest reflog entry neither the pull nor the checkout (a later commit),
    # (c) no --delete-branch, (d) head mismatch, (e) switched from a branch outside feature/fix/release.
    assert fallback('feature/500-test',expected=None,keep_branch=True)==[]
    assert fallback('feature/500-test',expected=None,commit_after=True)==[]
    assert fallback('feature/500-test','gh pr merge --squash',expected=None)==[]
    fallback('feature/500-test',expected=None,head='feature/another-pr')
    assert fallback('topic/500-test',expected=None)==[]
with section('S359 negative: pull of another branch'):
    # The pull entry names a branch other than the current one: uncertain, zero gh calls.
    git('checkout','-q','main')
    for b in git('branch','--format=%(refname:short)').split():
        if b not in {'main','branch-only'}: git('branch','-q','-D',b)
    simulate_merge('gh pr merge --squash --delete-branch','feature/500-test',squash=False)
    advance_remote('other')
    git('pull','--ff-only','origin','other')
    assert git('reflog','-2','--format=%gs','HEAD').splitlines()==['pull --ff-only origin other: Fast-forward','checkout: moving from feature/500-test to main']
    assert run('gh pr merge --squash --delete-branch',None,head='feature/500-test')==[]
with section('S359 negative: pull above non-checkout entry'):
    # A pull entry sits above a non-checkout entry (a reset after the checkout): uncertain, zero gh calls.
    git('checkout','-q','main')
    for b in git('branch','--format=%(refname:short)').split():
        if b not in {'main','branch-only'}: git('branch','-q','-D',b)
    simulate_merge('gh pr merge --squash --delete-branch','feature/500-test',squash=False)
    git('reset','-q','--hard'); advance_remote(); git('pull','--ff-only','origin','main')
    top=git('reflog','-3','--format=%gs','HEAD').splitlines()
    assert top[0]=='pull --ff-only origin main: Fast-forward' and top[1].startswith('reset:') and top[2].startswith('checkout: moving from feature/500-test'),top
    assert run('gh pr merge --squash --delete-branch',None,head='feature/500-test')==[]
git('checkout','-q','main')

with section('S360 masked and provable shell evidence'):
    # S360 shell evidence.
    for command in ['echo "gh pr merge 500"','cat <<EOF\ngh pr merge 500\nEOF','echo "a; gh pr merge 500"','echo "&&"','if false; then gh pr merge 500; fi','false && gh pr merge 500 || true','gh pr merge 500 || true','gh pr merge 500; true','gh pr merge 500 | cat','echo $(gh pr merge 500)']:
        assert run(command)==[],command
    for command in ['true && gh pr merge 500','gh pr merge 500 && true','false; gh pr merge 500','echo "a;b"; gh pr merge 500','gh pr merge 501 || true; gh pr merge 500', 'gh pr merge 500;', 'gh pr merge 500\n']:
        run(command,reminder)
with section('S360 redirections remind'):
    # Redirections keep the success proof: reminder, one lookup, target 500.
    for command in ['gh pr merge 500 2>&1','gh pr merge 500 >/dev/null','gh pr merge 500 > /dev/null 2>&1','gh pr merge 500 &> /dev/null','gh pr merge 500 >> out.log','gh pr merge 500 2> err.log','true && gh pr merge 500 2>&1']:
        one_lookup(run(command,reminder),'500')
with section('S360 pipes and unsupported redirections'):
    # Pipes and unsupported redirections stay uncertain, before any lookup.
    for command in ['gh pr merge 500 2>&1 | tail -3','gh pr merge 500 | cat','gh pr merge 500 < in.txt','gh pr merge 500 > $OUT','gh pr merge 500 <<< x','gh pr merge 500 2>&-']:
        assert run(command)==[],command
with section('S360 expansion targets'):
    # #552: the hook never expands, so a `$` in the PR target or the --repo value is uncertain:
    # no reminder and zero `gh pr view` calls (the fixture does not log `pr merge`). Collect every
    # failing form so the red output names them all, not just the first.
    failed = []
    for command in [
        'gh pr merge "$PR"', 'gh pr merge $PR', 'gh pr merge ${PR}', 'gh pr merge "${PR}"', 'gh pr merge $1',
        'PR=551 && gh pr merge $PR', 'gh pr merge --squash "$PR" --delete-branch', 'gh pr merge 5$X',
        'gh pr merge 551 --repo "$REPO"', 'gh pr merge 551 -R "$REPO"', 'gh pr merge 551 -R $REPO', 'gh pr merge 551 --repo=$REPO',
        "gh pr merge '$PR'", r'gh pr merge \$PR',
    ]:
        try: assert run(command) == [], command
        except AssertionError as exc: failed.append(command)
    # Omitted target plus `$` repo, from a surviving branch (on main it is uncertain for another reason).
    git('checkout','-q','-B','feature/500-test','main')
    try:
        try: assert run('gh pr merge --squash --delete-branch --repo "$REPO"') == [], 'omitted target, --repo "$REPO", surviving branch'
        except AssertionError as exc: failed.append('omitted target + --repo "$REPO" on feature/500-test')
    finally: git('checkout','-q','main')
    # Narrowness: literal targets and a `$` elsewhere in the command stay certain (green before and after).
    one_lookup(run('gh pr merge 551', reminder), '551')
    one_lookup(run("gh pr merge '551'", reminder), '551')
    one_lookup(run('gh pr merge "551"', reminder), '551')
    one_lookup(run('gh pr merge 551 --repo owner/name', reminder), '551', repo_flag='owner/name')
    one_lookup(run('gh pr merge 551 --body "$MSG"', reminder), '551')
    one_lookup(run('gh pr merge 500 && echo $?', reminder), '500')
    one_lookup(run('PR=551 && gh pr merge 551', reminder), '551')
    for command in failed: print('  expansion form not uncertain:', command, file=sys.stderr)
    assert not failed, ('a $ target or repo value was looked up or reminded', failed)

with section('S360 line continuation'):
    # Line continuation is lexed, not a literal newline word.
    for command in ['gh pr merge 500 \\\n  --squash --delete-branch','gh pr merge \\\n 500','gh \\\n pr merge 500','gh pr mer\\\nge 500']:
        one_lookup(run(command,reminder),'500')

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

with section('#561 mutant: a returned stop turns the suite red'):
    # Permanent proof that this suite sees the stop come back: copy the real hook (it loads
    # read-command.py from its own directory), add `continue: False` / `stopReason` to the
    # output constant, and require the reminder check to fail for exactly that reason.
    import re, shutil
    mutant_dir = box / 'mutant'
    mutant_dir.mkdir()
    shutil.copy(root/'hooks/read-command.py', mutant_dir/'read-command.py')
    source = (root/'hooks/stop-after-completion').read_text()
    constant = re.compile(r"^(\w+) = (\{[^\n]*Merged to main[^\n]*\})$", re.M)
    assert len(constant.findall(source)) == 1, 'hook output constant not found exactly once'
    def make_mutant(name, extra):
        mutated, count = constant.subn(lambda m: "%s = dict(%s, **%s)" % (m.group(1), m.group(2), extra), source)
        assert count == 1, name
        assert mutated != source or name == 'control', name
        path = mutant_dir/name
        path.write_text(mutated); path.chmod(0o755)
        return path
    control = make_mutant('control', '{}')
    run('gh pr merge 500', reminder, hook=control)  # the unmutated copy passes: a red mutant is caused by the mutation, not the copy
    for name, extra, field in [('stop-continue', "{'continue': False}", 'continue'), ('stop-reason', "{'stopReason': 'x'}", 'stopReason')]:
        path = make_mutant(name, extra)
        try:
            run('gh pr merge 500', reminder, hook=path)
        except AssertionError as exc:
            assert 'must not contain ' + field in str(exc), (name, str(exc)[:300])
        else:
            raise AssertionError('mutant %s: the suite did not go red when the stop returned' % name)

if _red:
    print('RED sections:', *_red, sep='\n  ', file=sys.stderr); sys.exit(1)
print('S355-S360: executable behavior passed')

# Malformed payloads remain advisory, including non-dict tool_input.
for payload in ['{', '[]', json.dumps(dict(hook_event_name='PostToolUse',tool_name='Bash',cwd=str(repo),tool_input=[],tool_response={}))]:
    result=subprocess.run([str(root/'hooks/stop-after-completion')],input=payload,text=True,capture_output=True,env=env)
    assert result.returncode==0 and not result.stdout,(payload,result)
# A failed Bash operation uses PostToolUseFailure, not an invented exit_code.
assert run('gh pr merge 500',extra=dict(hook_event_name='PostToolUseFailure'))==[]

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
gh.write_text("#!/usr/bin/env python3\nimport os,json,sys,time\nwith open(os.environ['GH_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\nif os.environ.get('GH_FAIL'): sys.exit(1)\nif os.environ.get('GH_SLEEP'): time.sleep(6)\nprint(os.environ['GH_RESULT'])\n")
gh.chmod(0o755)
log = box / "gh.log"
env = dict(os.environ, PATH=str(bin_dir)+os.pathsep+os.environ['PATH'], GH_LOG=str(log))
stop = {"continue": False, "stopReason": "Merged to main. Type /clear before the next work item."}

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
    if expected == 'release':
        assert actual and 'continue' not in actual, (command,actual)
        output=actual['hookSpecificOutput']
        assert output['hookEventName']=='PostToolUse' and 'tag' in output['additionalContext'] and 'stop' in output['additionalContext'], actual
    else: assert actual == expected, (command,expected,actual,result.stderr)
    return [json.loads(line) for line in log.read_text().splitlines()]

calls=run('gh pr merge 500', stop)
assert calls==[['pr','view','500','--json','baseRefName,headRefName,state']],calls
run('gh pr merge 500',base='release/490-example')
run('gh pr merge 500',expected='release',head='release/490-example')
for command in ['git push origin v1','git push origin refs/tags/v2','git push --tags','git push --follow-tags','gh release create v1','gh release create absent']:
    assert run(command,stop)==[],command
for command in ['git push origin branch-only','git push origin absent','git push origin :v1','git push --delete origin v1','git push --dry-run origin v1','git push -n --tags','git push origin main','git push origin refs/heads/v1','gh release create v1 --help','gh release create v1 -h']:
    assert run(command)==[],command
# --follow-tags needs an eligible annotated tag; lightweight tags do not count.
git('branch','feature/500-test')
git('checkout','-q','feature/500-test')
calls=run('gh pr merge',stop)
assert calls[0][2]=='feature/500-test',calls
run('gh pr merge',head='feature/another')
git('checkout','-q','main')
assert run('gh pr merge')==[]
git('tag','-d','v2')
run('git push --follow-tags')
for state in ['OPEN','CLOSED','QUEUED']:
    run('gh pr merge 500 --auto',state=state)
run('gh pr merge 500',gh_fail=True)
run('gh pr merge 500',gh_sleep=True)
run('gh pr merge 500',lookup={})
for extra in [dict(tool_name='Read'),dict(hook_event_name='PostToolUseFailure')]:
    assert run('gh pr merge 500',extra=extra)==[]
for response in [dict(interrupted=True),dict(backgroundTaskId='abc'),dict(stdout='',stderr='',interrupted=False,task_id='abc')]:
    assert run('git push origin v1',response=response)==[]
run('gh pr merge "unterminated')
# Omitted current PR must resolve its identity, not trust an arbitrary merged PR.
run('gh pr merge',lookup={})
for target in ['500','https://github.com/owner/repo/pull/500','feature/500-test']:
    calls=run('gh pr merge '+target+' --squash --delete-branch',stop)
    assert target in calls[0],calls
for command in ['gh -R owner/repo pr merge 500','gh pr merge 500 --repo owner/repo','gh pr merge --body text --subject title --match-head-commit abc 500 -R owner/repo']:
    calls=run(command,stop)
    assert calls==[['pr','view','500','--json','baseRefName,headRefName,state','--repo','owner/repo']],calls
for command in ['echo "gh pr merge 500"','printf "git push origin v1"','cat <<EOF\ngh pr merge 500\nEOF','echo "a; gh pr merge 500"','echo "&&"','if false; then gh pr merge 500; fi','false && gh pr merge 500 || true','gh pr merge 500 || true','gh pr merge 500; true','gh pr merge 500 | cat','echo $(gh pr merge 500)']:
    assert run(command)==[],command
for command in ['true && gh pr merge 500','gh pr merge 500 && true','false; gh pr merge 500','echo "a;b"; gh pr merge 500','gh pr merge 501 || true; gh pr merge 500']:
    run(command,stop)
print('S355-S360: executable behavior passed')

# Malformed payloads remain advisory, including non-dict tool_input.
for payload in ['{', '[]', json.dumps(dict(hook_event_name='PostToolUse',tool_name='Bash',cwd=str(repo),tool_input=[],tool_response={}))]:
    result=subprocess.run([str(root/'hooks/stop-after-completion')],input=payload,text=True,capture_output=True,env=env)
    assert result.returncode==0 and not result.stdout,(payload,result)
# A failed Bash operation uses PostToolUseFailure, not an invented exit_code.
assert run('git push origin v1',extra=dict(hook_event_name='PostToolUseFailure'))==[]

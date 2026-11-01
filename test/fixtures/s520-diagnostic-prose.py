"""Exercise the candidate CLI seam; mutants live only in a temporary copy."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])


def require(condition, label):
    if not condition:
        raise AssertionError(label)


def bullet(text, number):
    matches = re.findall(rf"(?m)^- \*\*Fix #{number}:.*(?:\n  .*)*", text)
    require(len(matches) == 1, f"S521: unique #{number} bullet")
    return matches[0]


def prose(changelog):
    entry = bullet(changelog, 468)
    expected = ('- **Fix #468: trailing whitespace removed from three test files.** '
                '`test/cases/s276_collector_unread_latest_authority.sh` (trailing space, line 65) and '
                '`test/fixtures/ce-review-helpers.sh`, `test/fixtures/role-label-fake-gh.sh` '
                '(extra blank line at EOF). No behavior change. Recurrence guard: #484.')
    require(' '.join(entry.split()) == expected, 'S521: #468 wording unchanged')
    require(max(map(len, entry.splitlines())) <= 100, 'S521: #468 width')
    entry = ' '.join(bullet(changelog, 467).split())
    require('seen in the stream transcript only' in entry, 'S521: #467 stream transcript')
    require('hook transcript' not in entry, 'S521: stale #467 hook transcript')


def skip_wording(check):
    header = check.split('# Usage:', 1)[0]
    require('nested suite run' in ' '.join(header.split()), 'S522: header nested suite run')
    messages = re.findall(r'^\s*echo "check: shellcheck skipped .*$', check, re.M)
    require(len(messages) == 1 and 'nested suite run' in messages[0]
            and 'check-commit' in messages[0], 'S522: skip message names both callers')


def killed(checker, text, label):
    try:
        checker(text)
    except AssertionError:
        print(label + ': mutant rejected')
        return
    raise AssertionError(label + ': mutant survived')


with tempfile.TemporaryDirectory(prefix='s520-') as tmp:
    work = Path(tmp)
    (work / 'test/cases').mkdir(parents=True)
    (work / 'lib').mkdir()
    for rel in ('test/lib.sh', 'test/ci-workflow-lib.sh', 'lib/git-env.sh'):
        shutil.copyfile(root / rel, work / rel)
    source = (root / 'test/cases/s219_s222_macos_ci_leg.sh').read_text()
    case = work / 'test/cases/s219_s222_macos_ci_leg.sh'
    real_sed = shutil.which('sed')
    shim = work / 'bin'
    shim.mkdir()
    # Normalize the native sed's own wraps, then force 60-column wrapping.
    # This exercises GNU's default-unfolded output as well as BSD's folds.
    sed = shim / 'sed'
    sed.write_text('#!' + sys.executable + '\n' + '''import subprocess, sys
p = subprocess.run([REAL, *sys.argv[1:]], stdout=subprocess.PIPE)
data = p.stdout
if sys.argv[1:] == ['-n', 'l']:
    data = data.replace(b'\\\\\\n', b'')
    for line in data.splitlines():
        while len(line) > 60:
            sys.stdout.buffer.write(line[:60] + b'\\\\\\n')
            line = line[60:]
        sys.stdout.buffer.write(line + b'\\n')
else:
    sys.stdout.buffer.write(data)
sys.exit(p.returncode)
'''.replace('REAL', repr(real_sed)))
    sed.chmod(0o755)
    original = (root / '.github/workflows/macos.yml').read_bytes()
    candidates = {
        'D1': b'# ' + b'A' * 250 + b'\r\n# ' + b'B' * 250 + b'\r\n# ' + b'C' * 250 + b'\r\n' + original,
        'D2': original + b'# ' + b'D' * 900 + b'\n# END-OF-LONG-DIFF\n',
    }

    def diagnostic(code, arm, forced):
        case.write_text(code)
        candidate = work / 'candidate.yml'
        candidate.write_bytes(candidates[arm])
        env = dict(os.environ, CI_MACOS_YML_UNDER_TEST=str(candidate),
                   CI_YML_UNDER_TEST=str(root / '.github/workflows/ci.yml'), S219_ARMS_INNER='1')
        if forced:
            env['PATH'] = str(shim) + os.pathsep + env['PATH']
        run = subprocess.run(['/bin/bash', str(case)], env=env, capture_output=True, text=True)
        output = run.stdout + run.stderr
        require(run.returncode != 0, 'S520: offending candidate must fail')
        lines = output.splitlines()
        failures = [line for line in lines if 'FAIL:' in line]
        require(len(failures) == 1 and len(lines) == 1, 'S520: one physical diagnostic line')
        require('\\~' not in output, 'S520: no folded diff continuation')
        if arm == 'D1':
            for n, char in enumerate('ABC', 1):
                require(f'line {n}: # ' + char * 250 + r'\r$' in output,
                        'S520: entire escaped offending line retained')
        else:
            require('D' * 900 + '$' in output and '# END-OF-LONG-DIFF$' in output,
                    'S520: diff limit counts logical records, not folds')

    mutant = re.sub(r'(s219_unfolded_bytes\(\) \{\n).*?(\n\})',
                    r'\1  LC_ALL=C sed -n l\2', source, count=1, flags=re.S)
    require(mutant != source, 'S520: unfolding mutation applied')
    for arm in candidates:
        for forced in (False, True):
            diagnostic(source, arm, forced)
        try:
            diagnostic(mutant, arm, True)
        except AssertionError:
            print(f'S520 {arm}: native/forced green; folding mutant rejected')
        else:
            raise AssertionError(f'S520 {arm}: folding mutant survived')

changelog = (root / 'CHANGELOG.md').read_text()
prose(changelog)
entry = bullet(changelog, 468)
killed(prose, changelog.replace(entry, ' '.join(entry.split())), 'S521 width')
killed(prose, changelog.replace('Recurrence guard: #484.', 'Recurrence guard: #999.'), 'S521 words')
entry = bullet(changelog, 467)
killed(prose, changelog.replace(entry, entry.replace('stream transcript', 'hook transcript')), 'S521 transcript')
check = (root / 'check').read_text()
skip_wording(check)
killed(skip_wording, check.replace('nested suite run in step 5', 'suite in step 5'), 'S522 header')
killed(skip_wording, check.replace('check-commit and the nested suite run)', 'check-commit)'), 'S522 message')
killed(skip_wording, check.replace('used by check-commit and the nested suite run)', 'used by the nested suite run)'), 'S522 check-commit')

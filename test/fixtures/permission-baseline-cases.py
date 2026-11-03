"""Exercise S380's command interface using tiny, offline repository copies."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get('S380_TEST_SCRIPT', ROOT / 'test/cases/s380_codex_permission_baseline_document.sh'))
DOC = (ROOT / 'adapters/codex/permission-baseline.md').read_text()
HEADER = '[features.network_proxy]                  # [A] covers all nested keys; enforcement pending live proof'
# A compliant document witness is independent of the concurrently edited real doc.
WITNESS = re.sub(r'^\[features.network_proxy\].*$', HEADER, DOC, flags=re.M)
FAILURES = []


def run(document, gh='stable'):
    with tempfile.TemporaryDirectory(prefix='s614-') as directory:
        root = Path(directory)
        for name in ('test/cases', 'test/fixtures', 'lib', 'adapters/codex', 'bin'):
            (root / name).mkdir(parents=True)
        for name in ('test/lib.sh', 'lib/git-env.sh', 'adapters/codex/INSTRUCTIONS.md', 'test/fixtures/permission-baseline-flags.tsv'):
            shutil.copyfile(ROOT / name, root / name)
        shutil.copyfile(SOURCE, root / 'test/cases/s380.sh')
        (root / 'adapters/codex/permission-baseline.md').write_text(document)
        # Tools needed by S380/lib.sh, deliberately excluding installed gh.
        for name in ('bash', 'dirname', 'grep', 'awk', 'sed', 'tr', 'sort', 'head', 'cut'):
            (root / 'bin' / name).symlink_to(shutil.which(name))
        if gh != 'absent':
            fake = root / 'bin/gh'
            fake.write_text('#!/bin/bash\nprintf "called\\n" >> "' + str(root / 'calls') + '"\n' +
                            ('printf "%s\\n" --web --nonexistent-command-flag\n' if gh == 'permissive' else
                             'case "$*" in "run list --help") echo --json ;; *) echo --web ;; esac\n' if gh == 'stable' else 'exit 1\n'))
            fake.chmod(0o755)
        result = subprocess.run([shutil.which('bash'), str(root / 'test/cases/s380.sh')],
                                env={**os.environ, 'PATH': str(root / 'bin')},
                                text=True, capture_output=True, timeout=30)
        return result.returncode, result.stdout + result.stderr, (root / 'calls').exists()


def oracle(result, success, named='', no_gh=False):
    code, output, called = result
    return ((code == 0) == success and (not named or named in output)
            and (not no_gh or not called))


def expect(label, document, success, named='', gh='stable', no_gh=False):
    result = run(document, gh)
    if not oracle(result, success, named, no_gh):
        FAILURES.append(f'{label}: expected success={success}, named={named!r}, no_gh={no_gh}; got {result}')
    # Independent observation mutants ensure every assertion can reject its
    # status/diagnostic/call falsifier; document mutants below exercise S380.
    compliant = (0 if success else 1, named, False)
    assert oracle(compliant, success, named, no_gh), label
    mutants = [(1 if success else 0, named, False)]
    if named:
        mutants.append((compliant[0], '', False))
    if no_gh:
        mutants.append((compliant[0], named, True))
    for mutant in mutants:
        assert not oracle(mutant, success, named, no_gh), label + ': assertion mutant survived'
    print(label + (': PASS' if oracle(result, success, named, no_gh) else ': FAIL'))


def add_key(document, text):
    return document.replace('enabled = true', text + '\nenabled = true', 1)


suite = sys.argv[1]
if suite == '490':
    expect('explicit assumed header covers nested unmarked keys', add_key(WITNESS, 'foo = 1'), True)
    expect('explicit its-nested-keys wording', WITNESS.replace('covers all nested keys', 'covers its nested keys'), True)
    expect('assumed header without coverage names foo', add_key(WITNESS.replace('covers all nested keys', 'pending proof'), 'foo = 1'), False, 'foo')
    expect('unmarked header names foo', add_key(WITNESS.replace(HEADER, '[features.network_proxy]'), 'foo = 1'), False, 'foo')
    expect('next table does not inherit coverage', add_key(WITNESS, '[another_table]\nfoo = 1'), False, 'foo')
elif suite == '491':
    for mark in ('[V]', '[V observed]', '[A] [V]'):
        expect('non-assumed header ' + mark, add_key(WITNESS.replace('# [A] covers', '# ' + mark + ' covers'), 'foo = 1'), False, 'foo')
    own = WITNESS.replace(HEADER, '[features.network_proxy]')
    own = own.replace('enabled = true', 'enabled = true # [V] key')
    own = own.replace('domains = { "api.github.com" = "allow", "github.com" = "allow" }', 'domains = { "api.github.com" = "allow", "github.com" = "allow" } # [A] pending proof')
    expect('own-line marks remain valid', own, True)
elif suite == '492':
    for gh in ('empty', 'permissive', 'absent'):
        expect('valid flags independent of gh ' + gh, WITNESS, True, gh=gh, no_gh=True)
        bad = WITNESS.replace('--web opens a browser', '--nonexistent-command-flag opens a browser', 1)
        expect('unknown flag independent of gh ' + gh, bad, False, '--nonexistent-command-flag', gh=gh, no_gh=True)
elif suite == '493':
    expect('mark preservation control', WITNESS, True)
    expect('removed top-level key mark', re.sub(r'^(exclude_slash_tmp =[^#]*)#.*$', r'\1', WITNESS, flags=re.M), False, 'exclude_slash_tmp')
    expect('command-specific flag preservation control', WITNESS, True)
    expect('run list has no web flag', WITNESS.replace('this command has no browser flag', '--web opens a browser'), False, '--web')
elif suite == '494':
    shellcheck = shutil.which('shellcheck')
    if not shellcheck:
        print('S494: shellcheck unavailable; static diagnostic check skipped')
    else:
        result = subprocess.run([shellcheck, '-s', 'bash', '-x', str(SOURCE)], cwd=ROOT, text=True, capture_output=True)
        if result.returncode:
            FAILURES.append(result.stdout + result.stderr)
        # Remove a quoted expansion in a separate fixture: shellcheck must
        # reject it, proving this invocation actually checks info diagnostics.
        with tempfile.TemporaryDirectory(prefix='s614-shellcheck-') as directory:
            mutant = Path(directory) / 'mutant.sh'
            mutant.write_text('#!/bin/bash\nvalue="a b"\nprintf "%s\\n" $value\n')
            killed = subprocess.run([shellcheck, '-s', 'bash', str(mutant)], text=True, capture_output=True)
            if killed.returncode == 0 or 'SC2086' not in killed.stdout:
                FAILURES.append('shellcheck info diagnostic mutant survived')
else:
    raise SystemExit('unknown suite')
for failure in FAILURES:
    print(failure, file=sys.stderr)
raise SystemExit(bool(FAILURES))

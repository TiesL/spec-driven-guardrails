"""Offline CLI and mutation witnesses for #616; only scratch copies are mutated."""
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
errors = []


def check(ok, label):
    if not ok:
        errors.append(label)
        print('FAIL: ' + label, file=sys.stderr)


def copy(root):
    root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'pipeline-override.sh', root)
    shutil.copytree(ROOT / 'lib', root / 'lib', dirs_exist_ok=True)
    return root / 'pipeline-override.sh'


def replace(path, old, new):
    text = path.read_text()
    assert old in text, f'mutation anchor absent: {old}'
    path.write_text(text.replace(old, new))


def run(script, value=b'fine', field='reason'):
    args = [os.fsencode(script), b'42', b'--scope', b'skip=Test', b'--decided-by', b'TiesL', b'--reason', b'fine', b'--dry-run']
    args[5 if field == 'decided-by' else 7] = value
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def accepted(result, value, field):
    return result.returncode == 0 and (field.encode() + b'="' + value + b'"') in result.stdout


def invalid(result):
    return result.returncode == 2 and not result.stdout and len(result.stderr.splitlines()) == 1 and b'is not valid UTF-8' in result.stderr


def symlinks(tmp):
    script = copy(tmp / 'x/real')
    (tmp / 'x/y').mkdir()
    (tmp / 'real').mkdir()  # logical .. lands here; physical .. must land in x/real
    (tmp / 'a').symlink_to('x/y', target_is_directory=True)
    (tmp / 'x/y/po').symlink_to('../real/pipeline-override.sh')
    direct = run(script)
    check(direct.returncode == 0 and bool(direct.stdout), 'S495/direct control')

    def same(result):
        return result.returncode == 0 and result.stdout == direct.stdout

    check(same(direct), 'S495/body equality positive control')
    check(not same(subprocess.CompletedProcess([], 3, direct.stdout, b'')), 'S495/exit-status mutant')
    changed = subprocess.CompletedProcess([], 0, direct.stdout + b'changed', b'')
    check(not same(changed), 'S495/body mutation detected')
    for name, target in [('absolute', str(script)), ('relative', 'x/real/pipeline-override.sh'), ('chain', 'relative')]:
        link = tmp / name
        link.symlink_to(target)
        check(same(run(link)), 'S495/' + name)
    env = dict(os.environ, PATH=str(tmp / 'x/y') + os.pathsep + os.environ['PATH'])
    path_run = subprocess.run(['po', '42', '--scope', 'skip=Test', '--decided-by', 'TiesL', '--reason', 'fine', '--dry-run'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    # Ordinary PATH lookup is a preservation control.
    (tmp / 'path-po').symlink_to(script)
    path_control = subprocess.run(['path-po', '42', '--scope', 'skip=Test', '--decided-by', 'TiesL', '--reason', 'fine', '--dry-run'], env=dict(env, PATH=str(tmp) + os.pathsep + env['PATH']), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    check(same(path_control), 'S495/PATH existing form')
    check(same(path_run), 'S495/physical PATH relative-parent')
    result = run(tmp / 'a/po')
    check(same(result), 'S495/symlinked-directory relative-parent: ' + result.stderr.decode(errors='replace').strip())


def boundaries(tmp):
    # Run the actual named S376 assertions on each sandbox mutant, not a weaker proxy.
    for label, old, new, witness in [
        ('e0', 'need = 2; lo = 160', 'need = 2; lo = 128', 'e0-overlong'),
        ('f0', 'need = 3; lo = 144', 'need = 3; lo = 128', 'f0-overlong'),
        ('f4', 'need = 3; hi = 143', 'need = 3; hi = 191', 'above-max'),
        ('ed', 'need = 2; hi = 159', 'need = 2; hi = 191', 'dfff-surrogate'),
        ('f5', 'b <= 243', 'b <= 245', 'f5-lead'),
        ('f8', 'else if (b >= 241', 'else if (b == 248) need = 4\n    else if (b >= 241', 'f8-lead'),
        ('class', 'is not valid UTF-8', 'has an unrelated refusal', 'ff-fe'),
    ]:
        root = tmp / label
        script = copy(root)
        (root / 'test/cases').mkdir(parents=True)
        shutil.copy2(ROOT / 'test/lib.sh', root / 'test/lib.sh')
        case = next((ROOT / 'test/cases').glob('s376_*'))
        shutil.copy2(case, root / 'test/cases' / case.name)
        replace(script, old, new)
        result = subprocess.run(['bash', str(root / 'test/cases' / case.name)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        for field in ['reason', 'decided-by']:
            check(result.returncode != 0 and ('S376/5b-' + field + '-' + witness + ' — invalid-UTF-8 class missing').encode() in result.stderr, 'S496/' + label + '/' + field + ' named check kills mutant')
    for label, cp, old, new in [
        ('d7ff', 0xD7FF, 'need = 2; hi = 159', 'need = 2; hi = 158'),
        ('e000', 0xE000, 'else if (b >= 225', 'else if (b == 238) { print "invalid"; exit }\n    else if (b >= 225'),
        ('max', 0x10FFFF, 'need = 3; hi = 143', 'need = 3; hi = 142'),
    ]:
        script = copy(tmp / ('valid-' + label))
        replace(script, old, new)
        value = chr(cp).encode()
        for field in ['reason', 'decided-by']:
            check(not accepted(run(script, value, field), value, field), 'S496/valid-edge narrowing mutant/' + label + '/' + field)
    for field in ['reason', 'decided-by']:
        for label, value in [('e0-overlong', b'\xe0\x80\xaf'), ('f0-overlong', b'\xf0\x80\x80\xaf'), ('above-max', b'\xf4\x90\x80\x80'), ('f5-lead', b'\xf5\x80\x80\x80'), ('f8-lead', b'\xf8\x80\x80\x80\x80'), ('dfff-surrogate', b'\xed\xbf\xbf')]:
            check(invalid(run(ROOT / 'pipeline-override.sh', value, field)), 'S496/control/' + field + '/' + label)
        for cp in [0xD7FF, 0xE000, 0x10FFFF]:
            value = chr(cp).encode()
            check(accepted(run(ROOT / 'pipeline-override.sh', value, field), value, field), f'S496/valid edge/{field}/{cp:X}')


def preserved(tmp):
    for cp in [0x2060, 0xAD, 0x3164, 0x2800]:
        value = chr(cp).encode()
        script = copy(tmp / str(cp))
        replace(script, 'ch == "20"', 'ch == "' + value.hex() + '" || ch == "20"')
        for field in ['reason', 'decided-by']:
            for text in [value, b'text' + value]:
                check(accepted(run(ROOT / 'pipeline-override.sh', text, field), text, field), f'S497/control/{cp:X}/{field}/{text!r}')
            check(not accepted(run(script, value, field), value, field), f'S497/blank-set mutant/{cp:X}/{field}')
            # A byte-altering mutant must also be caught for text plus the character.
            result = run(ROOT / 'pipeline-override.sh', b'text' + value, field)
            changed = subprocess.CompletedProcess([], result.returncode, result.stdout.replace(value, b'?'), result.stderr)
            check(not accepted(changed, b'text' + value, field), f'S497/byte-preservation mutant/{cp:X}/{field}')


def wording(tmp):
    script = ROOT / 'pipeline-override.sh'
    header = script.read_text().split('set -uo pipefail', 1)[0]
    help_result = subprocess.run([str(script), '--help'], stdout=subprocess.PIPE, check=False)
    help_text = help_result.stdout.decode()
    checks = [('header', header, 'listed zero-width characters'), ('help', help_text, 'listed zero-width characters')]
    # Pin the enumerated blank set in both surfaces, including every range edge.
    for label, text, phrase in checks:
        def pin_wording(value):
            return phrase in value and not re.search(r'(?<!listed )zero-width characters', value)
        check(pin_wording(text), 'S498/' + label + ' says listed zero-width characters')
        check(not pin_wording(text.replace(phrase, 'zero-width characters')), 'S498/' + label + ' wording mutant')
        for token in ['U+200B', 'U+200E', 'U+200F', 'U+061C', 'U+FEFF']:
            check(token in text, 'S498/' + label + '/' + token)
            check(token not in text.replace(token, 'removed'), 'S498/' + label + '/' + token + ' deletion mutant')
    for field in ['reason', 'decided-by']:
        result = run(script, '\u200e'.encode(), field)
        check(result.returncode == 2 and b'bidi marks' in result.stderr, 'S498/blank diagnostic names bidi marks/' + field)
        check(b'bidi marks' not in result.stderr.replace(b'bidi marks', b'invisibles'), 'S498/diagnostic wording mutant/' + field)


def witnesses(tmp):
    case = ROOT / 'test/cases/s363_completion_evidence.sh'
    # The mutator still passes its positive R3 control; only n2 aborts differently.
    for label, mutation in [('wrong-assert', "raise AssertionError('unrelated assertion')"), ('wrong-error', "raise RuntimeError('unrelated failure')")]:
        root = tmp / label
        (root / 'test/cases').mkdir(parents=True)
        for rel in ['test/lib.sh', 'test/completion-evidence.py', 'adapters/codex/AGENTS.md', 'docs/completion-live-evidence.json', 'docs/completion-runtime-evidence.md', 'TEST-SCENARIOS.md']:
            dest = root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / rel, dest)
        shutil.copytree(ROOT / 'lib', root / 'lib')
        text = case.read_text()
        anchor = "            assert 'Merged to main. Use /clear or /new before the next work item' in ' '.join(run['final'])"
        assert anchor in text
        text = text.replace(anchor, "            if not 'Merged to main. Use /clear or /new before the next work item' in ' '.join(run['final']):\n                " + mutation + "\n" + anchor)
        dest = root / 'test/cases' / case.name
        dest.write_text(text)
        result = subprocess.run(['bash', str(dest)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        check(result.returncode != 0 and b'n2 aborted for the wrong reason' in result.stderr and b'R3 not evaluated' not in result.stderr, 'S499/' + label + ' n2 witness')
    comment = '\n'.join(line for line in (ROOT / 'test/run.sh').read_text().splitlines() if line.startswith('#'))
    def attributed(text):
        return 'assumed 4 vCPU (Linux) and 3 (macOS)' in text or ('GitHub' in text and 'runner specs' in text)
    check(attributed(comment), 'S499/vCPU attribution control')
    check(not attributed(comment.replace('assumed ', '').replace('GitHub', 'unknown')), 'S499/vCPU attribution mutant')


with tempfile.TemporaryDirectory(prefix='sdg-616-') as directory:
    {495: symlinks, 496: boundaries, 497: preserved, 498: wording, 499: witnesses}[int(sys.argv[1])](Path(directory))
sys.exit(bool(errors))

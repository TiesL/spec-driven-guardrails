"""QA-owned exact #706 allowances on top of existing historical freezes.

No candidate bytes are learned as expected output. Every pair is literal in the
adjacent JSON; counts must be one. Original freezes and historical bases remain.
"""
from pathlib import Path
import json

TABLE = json.loads(Path(__file__).with_suffix('.json').read_text())['changes']


def apply(path, data):
    for old, new in TABLE.get(path, []):
        old, new = old.encode(), new.encode()
        if data.count(old) != 1:
            raise AssertionError('706 substitution source not unique: '+path+' '+repr(old[:60]))
        data = data.replace(old, new, 1)
    return data


def restore(path, data):
    for old, new in reversed(TABLE.get(path, [])):
        old, new = old.encode(), new.encode()
        if data.count(new) != 1:
            raise AssertionError('706 substitution missing/not unique: '+path+' '+repr(new[:60]))
        data = data.replace(new, old, 1)
    return data


def controls(path, baseline):
    expected = apply(path, baseline)
    assert restore(path, expected) == baseline
    for omitted in range(len(TABLE.get(path, []))):
        value = baseline
        for index, (old, new) in enumerate(TABLE[path]):
            if index != omitted:
                assert value.count(old.encode()) == 1
                value = value.replace(old.encode(), new.encode(), 1)
        assert value != expected, '706 omission escaped: '+path
    assert restore(path, expected+b'\n') != baseline, '706 extra-byte control'
    return expected


def protected_a_checks(root):
    """S627's A identity stays fixed; S548 alone sanctions the genuine stamp.

    Read the literal SNAPSHOTS assignment without running S548's test program.
    Core/scenario expectations come from A plus this table, never the candidate.
    """
    import ast
    import hashlib
    import subprocess

    base = '51178851a1f6fba76e87d046788339c02f874f03'
    table_base = json.loads(Path(__file__).with_suffix('.json').read_text())['base']
    stamp = 'test/behavior/orchestrator-diff.stamp'
    source = ast.parse((root/'test/fixtures/stage-selection-647.py').read_text())
    assignments = [ast.literal_eval(node.value) for node in source.body
                   if isinstance(node, ast.Assign)
                   and any(isinstance(t, ast.Name) and t.id == 'SNAPSHOTS'
                           for t in node.targets)]
    assert len(assignments) == 1, 'S627: S548 SNAPSHOTS must be unique'
    digest = assignments[0][stamp]
    assert len(digest) == 64 and all(c in '0123456789abcdef' for c in digest)
    errors = []
    paths = ('skills/role-contracts/ORCHESTRATOR.md',
             'test/behavior/orchestrator-scenarios.md',
             'test/fixtures/orchestrator-core-pins.tsv', stamp)
    for path in paths:
        before = subprocess.check_output(['git', '-C', str(root), 'show', base+':'+path])
        shared_base = subprocess.check_output(['git', '-C', str(root), 'show', table_base+':'+path])
        assert before == shared_base, 'S627: A differs from #706 historical base: '+path
        actual = (root/path).read_bytes()
        if path == stamp:
            accepts = lambda data: hashlib.sha256(data).hexdigest() == digest
            # This historical stamp is superseded only by S548's genuine-run pin.
            for label, data in (('historical stamp', before),
                                ('arbitrary stamp', b'forged #706 stamp\n'),
                                ('stamp extra byte', actual+b'\n')):
                assert not accepts(data), 'S627 control survived: '+label
                print('KILLED: S627/'+label)
        else:
            expected = controls(path, before)
            accepts = lambda data: data == expected
            assert accepts(expected), 'S627: reconstructed control failed: '+path
            for index in range(len(TABLE.get(path, []))):
                omitted = before
                for n, (old, new) in enumerate(TABLE[path]):
                    if n != index:
                        assert omitted.count(old.encode()) == 1
                        omitted = omitted.replace(old.encode(), new.encode(), 1)
                assert not accepts(omitted), 'S627 omitted pair survived: '+path
                print('KILLED: S627/'+path+' omitted pair '+str(index+1))
            assert not accepts(expected+b'\n'), 'S627 extra byte survived: '+path
            print('KILLED: S627/'+path+' extra byte')
        if not accepts(actual):
            errors.append('S627 — protected A plus exact #706 allowance mismatch: '+path)
    return errors

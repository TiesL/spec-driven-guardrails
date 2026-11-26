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
    assert expected+b'\n' != expected, '706 extra-byte control'
    return expected

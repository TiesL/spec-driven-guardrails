"""Oracle for S628 (#646, A58 addendum 3 decision 1, addendum 4): everything
the reserved merge guard runs is itself reserved.

Usage: python3 merge-risk-closure-646.py [628 | report]

A test-local closure resolver over the committed tree (no network, no model).
It starts from ENTRY, applies the edge rules of A58 addendum 4 until no new
file appears, and checks the result against policy/merge-autonomy.json
through the verifier's `--phase class` bundle adapter (one bundle per file),
reusing the bundle builder of test/fixtures/merge-risk-646.py.

Edge rules (followed):
- shell: `.`/`source` of a repo file; a repo file in command position; a repo
  file run through `bash`/`sh`/`python3`/`exec`; a repo script handed as an
  argument to a run script or to inline interpreter code (`python3 -c`,
  `python3 -`, `bash -c`): that code may run it, so it counts as run.
- python: a `subprocess` run, `importlib` load or `runpy` of a repo path; an
  import of a module beside the file; repo paths are names built on a base
  (`LIB / ...`, `ROOT / ...`, `Path(script_dir) / ...`) that is derived from
  `__file__` or named by the spec (`script_dir`, the root the collector
  passes).
Not followed (data): `cat`, `grep`, `awk`, `sed`, `diff`, `cmp`, `head`,
`tail`, `wc`, `jq`, input redirections, `[`/`[[`/`test` probes, `cp`/`tar`
copies; python `open`, `read_text`, `read_bytes`, `exists`, `is_file`,
`shutil.copy*`. A data read never needs to resolve: it is not followed.
A repo script referenced in a file only in some other way (an assignment never
used, an argument to `echo`, ...) fails as unclassifiable. A run or source
whose path does not resolve to a repo path (an unbound variable, a positional
parameter, a computed name) fails with file and line, unless SCRATCH_ROOTS
lists that file and root expression. Wiring entries are members (each must
be reserved) and are never traversed. The exempt leaves are members that are
not asserted reserved and are never traversed.

Outside the closure by definition: `gh`, `git`, `python3`, `bash`, every
other command found on PATH, and GitHub itself.

Interpretations of addendum 4 made here (the Developer's, stated so a
reviewer can contest them): a bare variable in command position with no path
part (`"$callback"`, `"$1"`) is a command name its caller supplies, so a repo
script handed to it is classified at the call site, where an argument to a
shell function is unclassifiable; a python path is only a `/` expression on a
base, so a script path held in a plain variable or attribute (`self.gate`)
is checked where the caller builds it; a relative command after `cd <dir> &&`
on the same line runs under <dir>.

Limits: the resolver reads source text with a small shell lexer and Python's
ast; it executes nothing, so a path built at run time from data it cannot see
is reported as unresolvable rather than guessed, and a shell function's body
is scanned whether or not a case calls it. Inline code for an interpreter
other than bash/sh/python3 (the `ruby -` block of model-record-gate.sh, which
spawns only `gh`) is not scanned. The row `resolver-sees-every-source-line`
cross-checks the lexer against a plain line match of every `.`/`source`.
"""
import ast
import importlib.util
import json
import os
import re
import subprocess
import sys
from fnmatch import fnmatch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

ENTRY = ['merge-risk-evidence.sh', 'merge-preflight.sh', 'hooks/git-guardrails', 'lib/merge-risk.py']
ENTRY_CASES = (605, 627)  # test/cases/s605_* .. s627_*
WIRING = ['settings/session-hooks.json', 'check', '.github/workflows/**', 'test/run.sh']
# Exact repo paths: members, not asserted reserved, never traversed.
EXEMPT_LEAVES = ['adopt.sh', 'pending-changes.sh']
# Scratch-tree roots: (file, root expression) -> what the root is. A run or
# source under that root in that file is a throwaway tree the case builds.
SCRATCH_ROOTS = {
    ('test/fixtures/merge-risk-646.py', 'self.dir'): 'the Tree scratch repository (mkdtemp)',
    ('test/cases/s627_merge_risk_core_edit_pointer_headroom.sh', '$1'): 'the clone() copy passed to slot_size/projection_problems',
    ('test/fixtures/pipeline-371-helpers.sh', '$cmd'): "a SessionStart command read from the scratch project's .claude/settings.json",
}
SCRIPT_EXT = ('.sh', '.py', '.bash')
SH_DATA = {'cat', 'grep', 'awk', 'sed', 'diff', 'cmp', 'head', 'tail', 'wc', 'jq', '[', '[[', 'test', 'cp', 'tar',
           'sort', 'shasum', 'sha256sum', 'readlink', 'ls', 'stat'}
SH_RUNNERS = {'bash', 'sh', 'python3', 'python', 'exec', 'env', 'command', 'nohup', 'time'}
SH_KEYWORDS = {'if', 'then', 'elif', 'else', 'fi', 'do', 'done', 'while', 'until', '!', '{', '}', 'esac', 'function'}
SH_DECL = {'local', 'export', 'readonly', 'declare', 'typeset'}
PY_RUN = {'run', 'Popen', 'check_output', 'check_call', 'call', 'execv', 'execvp', 'execve', 'run_path'}
PY_LOAD = {'spec_from_file_location'}
PY_DATA_ATTR = {'read_text', 'read_bytes', 'exists', 'is_file', 'is_symlink', 'is_dir', 'stat', 'open'}
PY_DATA_CALL = {'open', 'copy', 'copy2', 'copyfile', 'copytree', 'cmp'}
PY_TRANSPARENT = {'str', 'Path', 'fspath', 'PurePosixPath', 'resolve'}
PY_SEED_BASES = {'lib/merge-risk.py': {'script_dir': ''}}  # merge-risk-evidence.sh passes "$script_dir" (the root)

ROOT_MARK = '\x00ROOT\x00'
UNK = '\x00UNK:'


class Rules:
    """The resolver's rules; mutation checks switch one off."""
    def __init__(self, **kw):
        self.python_bases = True       # LIB / ..., ROOT / ..., Path(script_dir) / ...
        self.source_word = True        # `source` as well as `.`
        self.unresolvable_fails = True  # an unresolvable run/source fails
        self.data_is_edge = False      # data reads are not edges
        self.stale_check = True        # every exemption is used and exists
        self.exempt_match = 'exact'    # exact path match for exempt leaves
        self.__dict__.update(kw)


# --- the tree being resolved: the committed tree plus scratch edits
class Tree:
    def __init__(self, root=ROOT, edits=None, extra=None):
        self.root = Path(root)
        self.edits = dict(edits or {})
        self.extra = dict(extra or {})  # path -> (text, executable)
        self.files = set(self._tracked()) | set(self.extra)

    def _tracked(self):
        p = subprocess.run(['git', '-C', str(self.root), 'ls-files', '-z'], capture_output=True)
        if p.returncode == 0 and p.stdout:
            return [x for x in p.stdout.decode('utf-8', 'replace').split('\0') if x]
        out = []
        for d, dirs, names in os.walk(self.root):
            dirs[:] = [x for x in dirs if x != '.git']
            for n in names:
                out.append(os.path.relpath(os.path.join(d, n), self.root))
        return out

    def exists(self, p):
        return p in self.files

    def text(self, p):
        if p in self.edits:
            return self.edits[p]
        if p in self.extra:
            return self.extra[p][0]
        try:
            return (self.root / p).read_text(encoding='utf-8', errors='replace')
        except (OSError, IsADirectoryError):
            return ''

    def is_script(self, p):
        if not self.exists(p):
            return False
        if p.endswith(SCRIPT_EXT):
            return True
        if p in self.extra:
            return self.extra[p][1]
        return os.access(str(self.root / p), os.X_OK) or self.text(p).startswith('#!')

    def is_python(self, p):
        return p.endswith('.py') or re.match(r'#!.*python', self.text(p)) is not None

    def is_shell(self, p):
        return p.endswith(('.sh', '.bash')) or re.match(r'#!.*\b(ba)?sh\b', self.text(p)) is not None

    def glob(self, pattern):
        rx = re.compile('^' + re.escape(pattern).replace(r'\*\*', '.*').replace(r'\*', '[^/]*') + '$')
        return sorted(f for f in self.files if rx.match(f))


def norm(rel):
    parts = []
    for seg in rel.split('/'):
        if seg in ('', '.'):
            continue
        if seg == '..':
            if not parts:
                return None
            parts.pop()
        else:
            parts.append(seg)
    return '/'.join(parts)


# --- a small shell lexer: simple commands with their words and line numbers
class W(str):
    """A shell word that knows the line it starts on."""
    def __new__(cls, text, line):
        obj = str.__new__(cls, text)
        obj.line = line
        return obj


class Cmd:
    def __init__(self, line):
        self.line = line
        self.words = []
        self.redirs = []  # (op, word)
        self.heredoc = None


def _match_close(s, i, open_ch, close_ch):
    """Index just past the close_ch matching s[i-1] == open_ch (quote-aware)."""
    depth = 1
    while i < len(s):
        c = s[i]
        if c == '\\':
            i += 2
            continue
        if c == "'" and open_ch != '{':
            j = s.find("'", i + 1)
            i = len(s) if j < 0 else j + 1
            continue
        if c == '"':
            i = _skip_dq(s, i + 1)
            continue
        if c == '$' and i + 1 < len(s) and s[i + 1] == '(':
            i = _match_close(s, i + 2, '(', ')')
            continue
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def _skip_dq(s, i):
    while i < len(s):
        c = s[i]
        if c == '\\':
            i += 2
            continue
        if c == '"':
            return i + 1
        if c == '$' and i + 1 < len(s) and s[i + 1] in '({':
            i = _match_close(s, i + 2, s[i + 1], ')' if s[i + 1] == '(' else '}')
            continue
        if c == '`':
            j = s.find('`', i + 1)
            i = len(s) if j < 0 else j + 1
            continue
        i += 1
    return i


def sh_commands(text, line0=1):
    """Every simple command of a shell text, command substitutions included."""
    out = []
    i, n, line = 0, len(text), line0
    cmd = Cmd(line)
    word = None
    pending_heredocs = []
    case_depth = []  # stack: True while the next token is a case pattern
    expect_pattern = False
    redir = None
    wline = line

    def end_word():
        nonlocal word, redir
        if word is not None:
            word = W(word, wline)
            if redir:
                cmd.redirs.append((redir, word))
                if redir in ('<<', '<<-'):
                    pending_heredocs.append((cmd, word))
                redir = None
            else:
                cmd.words.append(word)
            word = None
            if len(cmd.words) == 3 and cmd.words[0] == 'case' and cmd.words[2] == 'in':
                end_cmd()

    def end_cmd():
        nonlocal cmd, expect_pattern
        end_word()
        if cmd.words or cmd.redirs:
            out.append(cmd)
            w = cmd.words
            if w and w[0] == 'case':
                case_depth.append(True)
                expect_pattern = True
            elif w and w[0] == 'esac' and case_depth:
                case_depth.pop()
        cmd = Cmd(line)

    def sub(start, end, ln):
        out.extend(sh_commands(text[start:end], ln))

    while i < n:
        c = text[i]
        if expect_pattern and word is None and not cmd.words:
            if c in ' \t\n;':
                if c == '\n':
                    line += 1
                i += 1
                continue
            if c == '#':
                j = text.find('\n', i)
                i = n if j < 0 else j
                continue
            if text.startswith('esac', i) and (i + 4 >= n or not (text[i + 4].isalnum() or text[i + 4] == '_')):
                expect_pattern = False
            else:
                j = i
                while j < n and text[j] != ')':
                    if text[j] == '\\':
                        j += 2
                        continue
                    if text[j] in '"\'':
                        j = _skip_dq(text, j + 1) if text[j] == '"' else text.find("'", j + 1) + 1
                        continue
                    if text[j] == '\n':
                        line += 1
                    j += 1
                i = j + 1
                expect_pattern = False
                cmd = Cmd(line)
                continue
        if c == '\\' and i + 1 < n and text[i + 1] == '\n':
            i += 2
            line += 1
            continue
        if c == '\n':
            end_cmd()
            redir = None
            line += 1
            i += 1
            for hcmd, delim in pending_heredocs:
                d = delim.strip('\'"')
                body_start, body_line = i, line
                while i < n:
                    j = text.find('\n', i)
                    j = n if j < 0 else j
                    cur = text[i:j]
                    i = min(j + 1, n)
                    line += 1
                    if cur.strip() == d:
                        break
                hcmd.heredoc = (text[body_start:i], body_line, delim)
            pending_heredocs.clear()
            cmd.line = line
            continue
        if word is None and c in ' \t':
            i += 1
            continue
        if c in ' \t':
            end_word()
            i += 1
            continue
        if word is None and c == '#':
            j = text.find('\n', i)
            i = n if j < 0 else j
            continue
        if c in ';&|()' and not (c == '(' and word is not None and word.endswith('=')):
            two = text[i:i + 2]
            if two == ';;' or two == ';&':
                end_cmd()
                i += 2
                if case_depth:
                    expect_pattern = True
                continue
            if c == '(' and word is None and text[i:i + 2] == '((':
                k = _match_close(text, i + 2, '(', ')')
                k = k + 1 if text[k:k + 1] == ')' else k
                line += text.count('\n', i, k)
                i = k
                continue
            end_cmd()
            i += 2 if two in ('&&', '||') else 1
            continue
        if c == '(' and word is not None and word.endswith('='):
            k = _match_close(text, i + 1, '(', ')')
            word += text[i:k]
            line += text.count('\n', i, k)
            i = k
            continue
        if c in '<>' and (word is None or re.fullmatch(r'\d*', word or '')):
            m = re.match(r'(<<<|<<-|<<|<&|>&|>>|<>|<|>)', text[i:])
            op = m.group(1)
            if text[i:i + 2] == '<(' or text[i:i + 2] == '>(':
                k = _match_close(text, i + 2, '(', ')')
                sub(i + 2, k - 1, line)
                line += text.count('\n', i, k)
                i = k
                word = None
                redir = None
                continue
            word = None
            i += len(op)
            if op in ('<&', '>&'):
                while i < n and text[i] not in ' \t\n;&|()':
                    i += 1
                continue
            redir = op
            continue
        if word is None:
            word = ''
            wline = line
        if c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            word += text[i:j + 1]
            line += text.count('\n', i, j)
            i = j + 1
            continue
        if c == '"':
            j = _skip_dq(text, i + 1)
            seg = text[i:j]
            word += seg
            for m in re.finditer(r'\$\(', seg):
                if seg[m.start():m.start() + 3] == '$((':
                    continue
                k = _match_close(seg, m.end(), '(', ')')
                sub(i + m.end(), i + k - 1, line + seg.count('\n', 0, m.start()))
            line += seg.count('\n')
            i = j
            continue
        if c == '$' and i + 1 < n and text[i + 1] in '({':
            if text[i + 1] == '(':
                if text[i + 2:i + 3] == '(':
                    k = _match_close(text, i + 3, '(', ')')
                    k = k + 1 if text[k:k + 1] == ')' else k
                else:
                    k = _match_close(text, i + 2, '(', ')')
                    sub(i + 2, k - 1, line)
            else:
                k = _match_close(text, i + 2, '{', '}')
            word += text[i:k]
            line += text.count('\n', i, k)
            i = k
            continue
        if c == '`':
            j = text.find('`', i + 1)
            j = n if j < 0 else j
            sub(i + 1, j, line)
            word += text[i:j + 1]
            i = j + 1
            continue
        word += c
        i += 1
    end_cmd()
    return out


# --- shell word evaluation
def sh_eval(word, env, fpath):
    """A word's value: ROOT_MARK-prefixed repo path, UNK-marked unknown, or text."""
    out, i, n = '', 0, len(word)
    while i < n:
        c = word[i]
        if c == "'":
            j = word.find("'", i + 1)
            j = n if j < 0 else j
            out += word[i + 1:j]
            i = j + 1
        elif c == '"':
            j = _skip_dq(word, i + 1)
            out += sh_eval(word[i + 1:j - 1], env, fpath)
            i = j
        elif c == '\\':
            out += word[i + 1:i + 2]
            i += 2
        elif c == '$' and word[i + 1:i + 2] == '(' and word[i + 2:i + 3] != '(':
            k = _match_close(word, i + 2, '(', ')')
            out += sh_subst(word[i + 2:k - 1], env, fpath)
            i = k
        elif c == '$' and word[i + 1:i + 2] == '{':
            k = _match_close(word, i + 2, '{', '}')
            inner = word[i + 2:k - 1]
            if inner == 'BASH_SOURCE[0]' or inner == 'BASH_SOURCE':
                out += ROOT_MARK + fpath
            else:
                name = re.match(r'[#!]?([A-Za-z_][A-Za-z0-9_]*|\d+|@|\*)', inner)
                nm = name.group(1) if name else inner
                simple = re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*(\[[@*0]\])?|\d+|@|\*', inner)
                if simple and nm in env:
                    out += env[nm]
                elif re.fullmatch(r'\d+|@|\*', nm):
                    out += UNK + '$' + nm + '\x00'
                else:
                    out += UNK + '$' + nm + '\x00'
            i = k
        elif c == '$' and re.match(r'\$([A-Za-z_][A-Za-z0-9_]*|\d|@|\*|#|\?|\$)', word[i:]):
            m = re.match(r'\$([A-Za-z_][A-Za-z0-9_]*|\d|@|\*|#|\?|\$)', word[i:])
            nm = m.group(1)
            if nm == '0':
                out += ROOT_MARK + fpath
            elif nm in env:
                out += env[nm]
            else:
                out += UNK + '$' + nm + '\x00'
            i += m.end()
        else:
            out += c
            i += 1
    return out


def sh_subst(inner, env, fpath):
    s = inner.strip()
    m = re.fullmatch(r'cd\s+(.+?)\s*&&\s*pwd(\s+-P)?', s, re.S)
    if m:
        return sh_eval(m.group(1), env, fpath)
    m = re.fullmatch(r'dirname\s+(.+)', s, re.S)
    if m:
        v = sh_eval(m.group(1), env, fpath)
        if v.startswith(ROOT_MARK):
            rel = v[len(ROOT_MARK):]
            return ROOT_MARK + (rel.rsplit('/', 1)[0] if '/' in rel else '')
        return UNK + '$(dirname)\x00'
    return UNK + '$(' + s[:30] + ')\x00'


def classify_value(v, fdir):
    """('repo', path) | ('unknown', root) | ('cmd', name) | ('outside', text) | ('empty', '')."""
    if v.startswith(ROOT_MARK):
        rel = norm(v[len(ROOT_MARK):])
        return ('repo', rel) if rel is not None else ('outside', v)
    if v.startswith(UNK):
        return ('unknown', v[len(UNK):].split('\x00', 1)[0])
    if UNK in v or ROOT_MARK in v:
        return ('unknown', 'computed:' + v.replace(UNK, '$').replace('\x00', '')[:40])
    if v == '':
        return ('empty', '')
    if v.startswith('/'):
        return ('outside', v)
    if '/' in v or v.startswith('.'):
        rel = norm(v)
        return ('repo', rel) if rel is not None else ('outside', v)
    return ('cmd', v)


# --- references
class Ref:
    def __init__(self, src, line, kind, target, how, root=None):
        self.src, self.line, self.kind, self.target, self.how, self.root = src, line, kind, target, how, root

    def __repr__(self):
        return '%s:%s %s %s %s' % (self.src, self.line, self.kind, self.target or self.root, self.how)


def sh_refs(tree, path, rules, text=None, line0=1, env=None):
    refs = []
    fdir = path.rsplit('/', 1)[0] if '/' in path else ''
    env = dict(env if env is not None else ({'TEST_REPO_ROOT': ROOT_MARK} if path.startswith('test/') else {}))
    cwd_by_line = {}
    for cmd in sh_commands(text if text is not None else tree.text(path), line0):
        words = list(cmd.words)
        for op, w in cmd.redirs:
            if op in ('<', '<<<'):
                _ref_word(tree, refs, path, cmd.line, w, env, 'data', 'redirect <', rules)
        # leading keywords, assignments and declarations
        while words and (re.match(r'[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=', words[0]) or words[0] in SH_DECL
                         or words[0] in SH_KEYWORDS):
            w = words.pop(0)
            if w in SH_KEYWORDS:
                continue
            if w in SH_DECL:
                while words and words[0].startswith('-'):
                    words.pop(0)
                for a in words:
                    _assign(tree, refs, path, cmd.line, a, env, rules)
                words = []
                break
            _assign(tree, refs, path, cmd.line, w, env, rules)
        if not words:
            continue
        head = words[0]
        if head == 'cd':
            cwd = sh_eval(words[1], env, path) if len(words) > 1 else ''
            cwd_by_line[cmd.line] = cwd
            continue
        if cmd.line in cwd_by_line and re.match(r'\.\.?/', head):
            # a relative command after `cd <dir> &&` on the same line runs under <dir>
            _ref_word(tree, refs, path, cmd.line, head, env, 'edge', 'command position after cd', rules,
                      value=cwd_by_line[cmd.line] + '/' + head)
            for w in words[1:]:
                _ref_word(tree, refs, path, cmd.line, w, env, 'arg', 'argument of a run script', rules)
            continue
        if head in ('for', 'case', 'select'):
            for w in words[1:]:
                _ref_word(tree, refs, path, cmd.line, w, env, 'mention', head, rules)
            continue
        if head == '.' or (head == 'source' and rules.source_word):
            if len(words) > 1:
                _ref_word(tree, refs, path, cmd.line, words[1], env, 'edge', 'source', rules)
            for w in words[2:]:
                _ref_word(tree, refs, path, cmd.line, w, env, 'arg', 'source-arg', rules)
            continue
        if head in SH_DATA:
            for w in words[1:]:
                _ref_word(tree, refs, path, cmd.line, w, env, 'edge' if rules.data_is_edge else 'data', head, rules)
            continue
        if head in ('echo', 'printf', 'source'):
            for w in words[1:]:
                _ref_word(tree, refs, path, cmd.line, w, env, 'mention', head, rules)
            continue
        hv = sh_eval(head, env, path)
        hk = classify_value(hv, fdir)
        if hk[0] == 'cmd' and hk[1] in SH_RUNNERS:
            refs.extend(_runner(tree, path, cmd, words, env, rules))
            continue
        if hk[0] == 'cmd':
            for w in words[1:]:
                _ref_word(tree, refs, path, cmd.line, w, env, 'mention', head, rules)
            continue
        _ref_word(tree, refs, path, cmd.line, head, env, 'edge', 'command position', rules)
        for w in words[1:]:
            _ref_word(tree, refs, path, cmd.line, w, env, 'arg', 'argument of a run script', rules)
    return refs


def _assign(tree, refs, path, line, w, env, rules):
    m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)(\[[^]]*\])?\+?=(.*)$', w, re.S)
    if not m:
        return
    name, val = m.group(1), m.group(3)
    if val.startswith('('):
        inner = val[1:-1] if val.endswith(')') else val[1:]
        sub = sh_commands(inner)
        first = sub[0].words[0] if sub and sub[0].words else ''
        env[name] = sh_eval(first, env, path)
        return
    v = sh_eval(val, env, path)
    env[name] = v
    _ref_word(tree, refs, path, line, val, env, 'mention', 'assignment to ' + name, rules, value=v)


def _runner(tree, path, cmd, words, env, rules):
    refs = []
    fdir = path.rsplit('/', 1)[0] if '/' in path else ''
    runner = classify_value(sh_eval(words[0], env, path), fdir)[1]
    rest = words[1:]
    if runner == 'env':
        while rest and re.match(r'[A-Za-z_][A-Za-z0-9_]*=', rest[0]):
            rest.pop(0)
        if rest:
            return sh_refs_for(tree, path, cmd, rest, env, rules)
        return refs
    if runner in ('command', 'nohup', 'time', 'exec'):
        if rest and rest[0] == '-v':
            return refs
        return sh_refs_for(tree, path, cmd, rest, env, rules) if rest else refs
    inline = False
    while rest and rest[0].startswith('-'):
        flag = rest.pop(0)
        if flag == '-':
            inline = True
            break
        if flag == '-c' and rest:
            code = rest.pop(0)
            inline = True
            v = sh_eval(code, env, path)
            if runner in ('bash', 'sh'):
                if UNK in v:
                    _unresolvable(refs, path, cmd.line, classify_value(v, fdir), rules, how=runner + ' -c')
                else:
                    refs.extend(sh_refs(tree, path, rules, text=v, line0=cmd.line, env=env))
            else:
                refs.extend(py_refs(tree, path, rules, text=v, line0=cmd.line))
            break
    if cmd.heredoc and runner in ('python3', 'python') and inline:
        refs.extend(py_refs(tree, path, rules, text=cmd.heredoc[0], line0=cmd.heredoc[1]))
    if not inline:
        if not rest:
            return refs
        _ref_word(tree, refs, path, cmd.line, rest.pop(0), env, 'edge', runner, rules)
    for w in rest:
        _ref_word(tree, refs, path, cmd.line, w, env, 'arg', ('inline %s code' % runner) if inline else 'argument of a run script', rules)
    return refs


def sh_refs_for(tree, path, cmd, words, env, rules):
    c = Cmd(cmd.line)
    c.words = words
    c.heredoc = cmd.heredoc
    fdir = path.rsplit('/', 1)[0] if '/' in path else ''
    hk = classify_value(sh_eval(words[0], env, path), fdir)
    if hk[0] == 'cmd' and hk[1] in SH_RUNNERS:
        return _runner(tree, path, c, words, env, rules)
    refs = []
    if hk[0] == 'cmd':
        if hk[1] in SH_DATA:
            for w in words[1:]:
                _ref_word(tree, refs, path, cmd.line, w, env, 'edge' if rules.data_is_edge else 'data', hk[1], rules)
        return refs
    _ref_word(tree, refs, path, cmd.line, words[0], env, 'edge', 'command position', rules)
    for w in words[1:]:
        _ref_word(tree, refs, path, cmd.line, w, env, 'arg', 'argument of a run script', rules)
    return refs


def _unresolvable(refs, path, line, kv, rules, how):
    refs.append(Ref(path, line, 'unresolvable', None, how, root=kv[1]))


def _ref_word(tree, refs, path, line, w, env, ctx, how, rules, value=None):
    line = getattr(w, 'line', line)
    fdir = path.rsplit('/', 1)[0] if '/' in path else ''
    v = value if value is not None else sh_eval(w, env, path)
    k = classify_value(v, fdir)
    if k[0] == 'repo':
        p = k[1]
        if p == path:
            return  # the file naming itself ($0, BASH_SOURCE) is not an edge
        if ctx == 'mention' and not v.startswith(ROOT_MARK):
            return  # a bare word in a mention is text, not a reference
        if not tree.exists(p):
            if ctx == 'edge':
                refs.append(Ref(path, line, 'missing', p, how))
            return
        if ctx == 'arg':
            if tree.is_script(p):
                refs.append(Ref(path, line, 'edge', p, how))
            else:
                refs.append(Ref(path, line, 'data', p, how))
            return
        refs.append(Ref(path, line, ctx, p, how))
    elif k[0] == 'unknown' and ctx == 'edge':
        if how == 'command position' and re.fullmatch(r'\$[A-Za-z_][A-Za-z0-9_]*|\$\d|\$@', k[1]) and \
                re.fullmatch(r'"?\$\{?[A-Za-z0-9_@]+(\[[@*]\])?\}?"?', w):
            return  # a bare variable as command: a name the caller supplies, classified at the call site
        _unresolvable(refs, path, line, k, rules, how)
    elif k[0] == 'cmd' and ctx == 'edge':
        pass  # a command found on PATH: outside the closure


# --- python
def py_refs(tree, path, rules, text=None, line0=1):
    src = text if text is not None else tree.text(path)
    try:
        mod = ast.parse(src)
    except SyntaxError as exc:
        return [Ref(path, line0 + (exc.lineno or 1) - 1, 'unresolvable', None, 'python syntax', root='unparsable')]
    fdir = path.rsplit('/', 1)[0] if '/' in path else ''
    parents = {}
    for node in ast.walk(mod):
        for ch in ast.iter_child_nodes(node):
            parents[ch] = node
    bases = dict(PY_SEED_BASES.get(path, {})) if text is None else {}
    for node in ast.walk(mod):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            d = _file_dir(node.value, path)
            if d is not None:
                bases[node.targets[0].id] = d
    refs = []
    ln = lambda node: line0 + getattr(node, 'lineno', 1) - 1  # noqa: E731
    for node in ast.walk(mod):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            names = [a.name for a in node.names] if isinstance(node, ast.Import) else [node.module or '']
            for nm in names:
                cand = norm((fdir + '/' if fdir else '') + nm.split('.')[0] + '.py')
                if cand and tree.exists(cand):
                    refs.append(Ref(path, ln(node), 'edge', cand, 'import'))
            continue
        if not (isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div)):
            continue
        if isinstance(parents.get(node), ast.BinOp) and isinstance(parents[node].op, ast.Div) and parents[node].left is node:
            continue  # only the outermost path expression
        val = _py_path(node, bases)
        if val is None:
            continue
        kind, rel = val
        if kind == 'base' and not rules.python_bases:
            continue
        ctx, how = _py_context(node, parents)
        if rules.data_is_edge and ctx == 'data':
            ctx = 'edge'
        if kind == 'base':
            rel = norm(rel)
            if rel is None or not tree.exists(rel):
                if ctx == 'edge':
                    refs.append(Ref(path, ln(node), 'missing', rel, how))
                continue
            if ctx == 'mention':
                refs.append(Ref(path, ln(node), 'mention', rel, how))
            else:
                refs.append(Ref(path, ln(node), ctx, rel, how))
        elif kind == 'unknown' and ctx == 'edge':
            refs.append(Ref(path, ln(node), 'unresolvable', None, how, root=rel))
    return refs


def _file_dir(v, path):
    """The repo dir a `Path(__file__).resolve().parent(s[k])` expression names."""
    hops = 0
    while True:
        if isinstance(v, ast.Attribute) and v.attr == 'parent':
            hops += 1
            v = v.value
        elif isinstance(v, ast.Subscript) and isinstance(v.value, ast.Attribute) and v.value.attr == 'parents':
            sl = v.slice
            sl = sl.value if isinstance(sl, ast.Index) else sl  # python < 3.9
            if not isinstance(sl, ast.Constant):
                return None
            hops += sl.value + 1
            v = v.value.value
        elif isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute) and v.func.attr == 'resolve':
            v = v.func.value
        else:
            break
    if hops and isinstance(v, ast.Call) and isinstance(v.func, ast.Name) and v.func.id == 'Path' and v.args and \
            isinstance(v.args[0], ast.Name) and v.args[0].id == '__file__':
        parts = path.split('/')[:-1]
        if hops - 1 > len(parts):
            return None
        return '/'.join(parts[:len(parts) - (hops - 1)])
    return None


def _py_path(node, bases):
    parts = []
    while isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        parts.insert(0, node.right)
        node = node.left
    base = node
    if isinstance(base, ast.Call) and isinstance(base.func, ast.Name) and base.func.id == 'Path' and len(base.args) == 1:
        base = base.args[0]
    if isinstance(base, ast.Constant) and isinstance(base.value, str):
        return None if base.value.startswith('/') else ('unknown', repr(base.value))
    if isinstance(base, ast.JoinedStr):
        return None  # an absolute f-string such as /proc/...
    if not isinstance(base, (ast.Name, ast.Attribute, ast.Call, ast.Subscript)):
        return None
    root = ast.unparse(base) if hasattr(ast, 'unparse') else type(base).__name__
    if isinstance(base, ast.Name) and base.id in bases:
        if all(isinstance(p, ast.Constant) and isinstance(p.value, str) for p in parts):
            rel = '/'.join([bases[base.id]] + [p.value for p in parts]) if bases[base.id] else '/'.join(p.value for p in parts)
            return ('base', rel)
        return ('unknown', 'computed:%s / %s' % (root, ' / '.join(ast.unparse(p) for p in parts)))
    return ('unknown', root)


def _py_context(node, parents):
    cur = node
    while cur in parents:
        par = parents[cur]
        if isinstance(par, (ast.List, ast.Tuple, ast.Starred, ast.keyword)) or \
                (isinstance(par, ast.BinOp) and isinstance(par.op, ast.Add)):
            cur = par
            continue
        if isinstance(par, ast.Attribute) and par.value is cur:
            g = parents.get(par)
            if par.attr in PY_DATA_ATTR and isinstance(g, ast.Call) and g.func is par:
                return 'data', par.attr
            if par.attr in PY_TRANSPARENT and isinstance(g, ast.Call) and g.func is par:
                cur = g
                continue
            return 'mention', '.' + par.attr
        if isinstance(par, ast.Call):
            f = par.func
            name = f.attr if isinstance(f, ast.Attribute) else (f.id if isinstance(f, ast.Name) else '')
            if name in PY_TRANSPARENT:
                cur = par
                continue
            if name in PY_RUN:
                return 'edge', 'subprocess.' + name
            if name in PY_LOAD:
                return 'edge', name
            if name in PY_DATA_CALL:
                return 'data', name
            return 'mention', name + '()'
        return 'mention', type(par).__name__
    return 'mention', 'statement'


# --- the closure
def file_refs(tree, path, rules):
    if tree.is_python(path):
        return py_refs(tree, path, rules)
    if tree.is_shell(path):
        return sh_refs(tree, path, rules)
    return []


def entries(tree):
    cases = []
    for f in sorted(tree.files):
        m = re.match(r'test/cases/s(\d+)_[^/]*\.sh$', f)
        if m and ENTRY_CASES[0] <= int(m.group(1)) <= ENTRY_CASES[1]:
            cases.append(f)
    return list(ENTRY) + cases


def leaf_exempt(path, rules):
    if rules.exempt_match == 'exact':
        return path in EXEMPT_LEAVES
    # mutant: an entry also covers files of the same directory and extension
    return any(fnmatch(path, os.path.join(os.path.dirname(e), '*' + os.path.splitext(e)[1])) for e in EXEMPT_LEAVES)


def resolve(tree, rules=None, exempt_leaves=None, scratch=None):
    """-> dict(closure, wiring, leaves, scratch_used, problems, edges)."""
    global EXEMPT_LEAVES
    rules = rules or Rules()
    saved = EXEMPT_LEAVES
    if exempt_leaves is not None:
        EXEMPT_LEAVES = list(exempt_leaves)
    scratch = dict(SCRATCH_ROOTS if scratch is None else scratch)
    try:
        wiring = sorted({f for w in WIRING for f in tree.glob(w)})
        problems, edges = [], {}
        leaves_used, scratch_used = {}, {}
        closure = []
        todo = list(entries(tree))
        seen = set(todo)
        while todo:
            f = todo.pop(0)
            closure.append(f)
            refs = file_refs(tree, f, rules)
            used = {(r.target, r.kind) for r in refs if r.target}
            for r in refs:
                if r.kind == 'unresolvable':
                    if (f, r.root) in scratch:
                        scratch_used.setdefault((f, r.root), []).append(r.line)
                    elif rules.unresolvable_fails:
                        problems.append('unresolvable %s at %s:%s (%s)' % (r.root, f, r.line, r.how))
                elif r.kind == 'missing':
                    problems.append('missing %s run at %s:%s (%s)' % (r.target, f, r.line, r.how))
                elif r.kind == 'mention':
                    if tree.is_script(r.target) and (r.target, 'edge') not in used and (r.target, 'data') not in used:
                        problems.append('unclassifiable reference to %s at %s:%s (%s)' % (r.target, f, r.line, r.how))
                elif r.kind == 'edge':
                    edges.setdefault(r.target, []).append('%s:%s (%s)' % (f, r.line, r.how))
                    if r.target in wiring:
                        continue
                    if leaf_exempt(r.target, rules):
                        leaves_used.setdefault(r.target, []).append('%s:%s' % (f, r.line))
                        continue
                    if r.target not in seen:
                        seen.add(r.target)
                        todo.append(r.target)
        if rules.stale_check:
            for e in EXEMPT_LEAVES:
                if not tree.exists(e):
                    problems.append('exemption %s names a path that does not exist' % e)
                elif e not in leaves_used:
                    problems.append('exemption %s is stale: no closure file runs it' % e)
            for key in scratch:
                if not tree.exists(key[0]):
                    problems.append('scratch root %s in %s: the file does not exist' % (key[1], key[0]))
                elif key not in scratch_used:
                    problems.append('scratch root %s in %s is stale: unused' % (key[1], key[0]))
        return {'closure': closure, 'wiring': wiring, 'leaves': leaves_used, 'scratch_used': scratch_used,
                'problems': problems, 'edges': edges, 'scratch': scratch}
    finally:
        EXEMPT_LEAVES = saved


def report_text(res):
    out = ['closure (%d files, each must be reserved):' % len(res['closure'])]
    for f in res['closure']:
        via = res['edges'].get(f)
        out.append('  %s%s' % (f, ('  <- ' + via[0]) if via else '  (entry point)'))
    out.append('wiring members (reserved, not traversed): ' + ', '.join(res['wiring']))
    out.append('exempt leaves (not reserved by this test, not traversed):')
    for e in EXEMPT_LEAVES:
        out.append('  %s  used by %s' % (e, ', '.join(res['leaves'].get(e, ['NOTHING']))))
    out.append('scratch-tree roots (exempt runs under a throwaway tree):')
    for (f, root), why in sorted(res['scratch'].items()):
        lines = res['scratch_used'].get((f, root), [])
        out.append('  %s in %s, lines %s: %s' % (root, f, ','.join(map(str, lines)) or 'NONE', why))
    out.append('outside the closure: gh, git, python3, bash, every other command on PATH, and GitHub itself')
    return '\n'.join(out)


# --- the verifier's view: one bundle per file through `--phase class`
_MR = None


def mr646():
    global _MR
    if _MR is None:
        spec = importlib.util.spec_from_file_location('merge_risk_646_for_628', ROOT / 'test/fixtures/merge-risk-646.py')
        _MR = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_MR)
    return _MR


class Verifier:
    """The `--phase class` verdict of a one-file, 1-line PR under a config."""
    def __init__(self, config_text):
        self.m = mr646()
        self.t = self.m.Tree(config=config_text)
        self.cache = {}

    def verdict(self, path):
        if path not in self.cache:
            self.cache[path] = self.t.ev(self.m.class_base(self.t, files=[self.m.fl(path, 1)]))
        return self.cache[path]

    def reserved(self, path):
        o = self.verdict(path)
        return o.verdict == 'referred' and any(r.split()[:2] == ['reserved-path', path] for r in o.reasons)


class Ctx:
    def __init__(self, rules=None, config=None, leaves=None, scratch=None, verifier=None):
        self.rules = rules or Rules()
        self.config = config if config is not None else (ROOT / 'policy/merge-autonomy.json').read_text()
        self.leaves = list(EXEMPT_LEAVES if leaves is None else leaves)
        self.scratch = dict(SCRATCH_ROOTS if scratch is None else scratch)
        self.verifier = verifier or Verifier(self.config)
        self.report = None

    def but(self, **kw):
        """The same context with other exemptions, sharing the verifier."""
        return Ctx(rules=self.rules, config=self.config, leaves=kw.get('leaves', self.leaves),
                   scratch=kw.get('scratch', self.scratch), verifier=self.verifier)


def closure_check(tree, ctx):
    """Every problem of the closure: the resolver's, plus each member the
    verifier does not refer with `reserved-path`."""
    res = resolve(tree, ctx.rules, exempt_leaves=ctx.leaves, scratch=ctx.scratch)
    problems = list(res['problems'])
    for f in res['closure']:
        if not ctx.verifier.reserved(f):
            via = res['edges'].get(f, ['entry point'])[0]
            problems.append('%s is run (via %s) and is neither reserved nor exempt: %r' % (f, via, ctx.verifier.verdict(f)))
    for f in res['wiring']:
        if not ctx.verifier.reserved(f):
            problems.append('wiring member %s is not reserved: %r' % (f, ctx.verifier.verdict(f)))
    return res, problems


class Fail(Exception):
    pass


def need(cond, msg):
    if not cond:
        raise Fail(msg)


def planted(path, lines, extra=None):
    """A scratch view of the committed tree with lines appended to one file;
    returns it and the line number of the first planted line."""
    text = Tree().text(path)
    first = text.count('\n') + 1
    return Tree(edits={path: text + ''.join(x + '\n' for x in lines)}, extra=extra), first


ZZ_NEW = {'lib/zz-new.sh': ('#!/usr/bin/env bash\n# planted by S628\n:\n', True)}
CASE_FILE = 'test/cases/s628_merge_risk_guard_closure_reserved.sh'
ROWS = []


def row(name):
    def deco(fn):
        ROWS.append((name, fn))
        return fn
    return deco


@row('a-each-closure-file-reserved')
def _(ctx):
    res = resolve(Tree(), ctx.rules, exempt_leaves=ctx.leaves, scratch=ctx.scratch)
    bad = ['%s: %r' % (f, ctx.verifier.verdict(f)) for f in res['closure'] + res['wiring'] if not ctx.verifier.reserved(f)]
    need(not bad, 'not referred with reserved-path: %s' % '; '.join(bad))
    for leaf in ctx.leaves:
        need(leaf not in res['closure'], 'exempt leaf %s was asserted as a closure member' % leaf)
    need(set(entries(Tree())) <= set(res['closure']), 'an entry point is missing from the closure')


@row('a-s628-files-reserved')
def _(ctx):
    for f in (CASE_FILE, 'test/fixtures/merge-risk-closure-646.py'):
        need(ctx.verifier.reserved(f), 'S628 file %s is not reserved: %r' % (f, ctx.verifier.verdict(f)))


def _b(ctx, word):
    tree, first = planted('merge-preflight.sh', ['DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"',
                                                 '%s "$DIR/lib/zz-new.sh"' % word], ZZ_NEW)
    _, problems = closure_check(tree, ctx)
    need(any(p.startswith('lib/zz-new.sh is run (via merge-preflight.sh:%d ' % (first + 1)) and 'neither reserved nor exempt' in p
             for p in problems), 'planted `%s "$DIR/lib/zz-new.sh"` not named as reachable and not reserved: %s' % (word, problems))


@row('b-planted-dot')
def _(ctx):
    _b(ctx, '.')


@row('b-planted-source')
def _(ctx):
    _b(ctx, 'source')


@row('b-planted-lib-name')
def _(ctx):
    tree, first = planted('lib/merge-risk.py', ["subprocess.run(['bash', str(LIB / 'zz-new.sh')])"], ZZ_NEW)
    _, problems = closure_check(tree, ctx)
    need(any(p.startswith('lib/zz-new.sh is run (via lib/merge-risk.py:%d ' % first) for p in problems),
         'a planted `LIB / ...` run was not named as reachable and not reserved: %s' % problems)


@row('c-unresolvable-fails-with-line')
def _(ctx):
    tree, first = planted('merge-preflight.sh', ['. "$base/$name"'])
    _, problems = closure_check(tree, ctx)
    need(any(p.startswith('unresolvable $base at merge-preflight.sh:%d ' % first) for p in problems),
         'a computed source path was not reported with file and line: %s' % problems)


@row('d-control')
def _(ctx):
    res, problems = closure_check(Tree(), ctx)
    need(not problems, 'the shipped closure fails: %s' % '; '.join(problems))
    for leaf in ctx.leaves:
        need(res['leaves'].get(leaf), 'exemption %s unused' % leaf)
    for key in ctx.scratch:
        need(res['scratch_used'].get(key), 'scratch root %s unused' % (key,))
    ctx.report = report_text(res)


@row('e-data-read-not-an-edge')
def _(ctx):
    tree, _ = planted('merge-preflight.sh', ['grep -q x CHANGES.md', 'cat lib/zz-data.txt'],
                      {'lib/zz-data.txt': ('data\n', False)})
    res, problems = closure_check(tree, ctx)
    need(not problems, 'a data read changed the result: %s' % problems)
    for f in ('CHANGES.md', 'lib/zz-data.txt'):
        need(f not in res['closure'], '%s entered the closure through a data read' % f)


@row('f-stale-exemption')
def _(ctx):
    _, problems = closure_check(Tree(), ctx.but(leaves=ctx.leaves + ['install.sh']))
    need(any('exemption install.sh is stale' in p for p in problems), 'a stale exemption passed: %s' % problems)


@row('f-nonexistent-exemption')
def _(ctx):
    _, problems = closure_check(Tree(), ctx.but(leaves=ctx.leaves + ['zz-missing.sh']))
    need(any('exemption zz-missing.sh names a path that does not exist' in p for p in problems),
         'a nonexistent exemption passed: %s' % problems)


@row('f-stale-scratch-root')
def _(ctx):
    sc = dict(ctx.scratch)
    sc[('test/lib.sh', '$zz_root')] = 'planted by S628'
    _, problems = closure_check(Tree(), ctx.but(scratch=sc))
    need(any('scratch root $zz_root in test/lib.sh is stale' in p for p in problems), 'a stale scratch root passed: %s' % problems)


@row('g-unlisted-installer-like-script')
def _(ctx):
    tree, first = planted('merge-preflight.sh', ['bash ./zz-install.sh'],
                          {'zz-install.sh': ('#!/usr/bin/env bash\n# an installer like adopt.sh\n:\n', True)})
    _, problems = closure_check(tree, ctx)
    need(any(p.startswith('zz-install.sh is run (via merge-preflight.sh:%d ' % first) and 'neither reserved nor exempt' in p
             for p in problems), 'an unlisted executed script passed: %s' % problems)


@row('resolver-sees-every-source-line')
def _(ctx):
    """A guard on the resolver itself: every `.`/`source` line of a shell
    closure file yields an edge or an unresolvable reference on that line."""
    tree = Tree()
    res = resolve(tree, ctx.rules, exempt_leaves=ctx.leaves, scratch=ctx.scratch)
    rx = re.compile(r'^\s*(?:(?:if|then|do|else)\s+|.*?(?:;|&&|\|\||\(|<)\s*)?(?:\.|source)\s+["$]')
    missed = []
    for f in res['closure']:
        if not tree.is_shell(f):
            continue
        seen = {r.line for r in file_refs(tree, f, ctx.rules) if r.kind in ('edge', 'unresolvable', 'missing')}
        for i, x in enumerate(tree.text(f).split('\n'), 1):
            if rx.match(x) and not x.lstrip().startswith('#') and i not in seen:
                missed.append('%s:%d' % (f, i))
    need(not missed, 'source lines the resolver did not see: %s' % missed)


def drop_reserved(text, entry):
    cfg = json.loads(text)
    need(entry in cfg['reserved']['autonomy'], 'mutation anchor %s missing' % entry)
    cfg['reserved']['autonomy'].remove(entry)
    return json.dumps(cfg, indent=2) + '\n'


# (label, rows of which at least one must fail, Ctx keyword arguments)
MUTATIONS = [
    ('remove lib/git-env.sh from reserved.autonomy', ['a-each-closure-file-reserved', 'd-control'],
     {'config': ('drop', 'lib/git-env.sh')}),
    ('drop the LIB / ... rule', ['b-planted-lib-name'], {'rules': Rules(python_bases=False)}),
    ('read an unresolvable reference as no edge', ['c-unresolvable-fails-with-line'], {'rules': Rules(unresolvable_fails=False)}),
    ('follow only `.`, not `source`', ['b-planted-source'], {'rules': Rules(source_word=False)}),
    ('treat a data read as an edge', ['e-data-read-not-an-edge'], {'rules': Rules(data_is_edge=True)}),
    ('drop the stale-entry check', ['f-stale-exemption', 'f-nonexistent-exemption', 'f-stale-scratch-root'],
     {'rules': Rules(stale_check=False)}),
    ('match exemptions by glob instead of exact path', ['g-unlisted-installer-like-script'],
     {'rules': Rules(exempt_match='glob')}),
]


def run_rows(ctx, names=None):
    failed = {}
    for name, fn in ROWS:
        if names is not None and name not in names:
            continue
        try:
            fn(ctx)
        except Fail as exc:
            failed[name] = str(exc)
    return failed


def main():
    errors = []
    ctx = Ctx()
    failed = run_rows(ctx)
    for name, msg in failed.items():
        errors.append('S628 %s: %s' % (name, msg))
    if ctx.report:
        print(ctx.report)
    killed = 0
    shipped = (ROOT / 'policy/merge-autonomy.json').read_text()
    for label, names, kw in MUTATIONS:
        kw = dict(kw)
        try:
            if 'config' in kw:
                kw['config'] = drop_reserved(shipped, kw['config'][1])
            got = run_rows(Ctx(**kw), set(names))
        except Fail as exc:
            errors.append('S628 mutation %s: %s' % (label, exc))
            continue
        if not set(got) & set(names):
            errors.append('S628 mutation %s survived: rows %s stayed green' % (label, ', '.join(names)))
        else:
            killed += 1
            print('mutation killed: %s (failed: %s)' % (label, ', '.join(sorted(got))))
    for line in errors:
        print('FAIL: ' + line)
    print('S628: %d rows, %d failed; %d mutations killed of %d' % (len(ROWS), len(failed), killed, len(MUTATIONS)))
    return 1 if errors else 0


if __name__ == '__main__':
    if sys.argv[1:2] == ['report']:
        r = resolve(Tree())
        print(report_text(r))
        for p in r['problems']:
            print('PROBLEM: ' + p)
        sys.exit(0)
    if sys.argv[1:2] != ['628']:
        print('usage: merge-risk-closure-646.py 628 | report')
        sys.exit(2)
    sys.exit(main())

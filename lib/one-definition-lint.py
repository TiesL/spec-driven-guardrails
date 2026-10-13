"""Private check implementation: bounded shell syntax lint, not a shell analyzer.

The public Interface is check --no-tests. Messages and Markdown examples are
allowed. Variable indirection, generated code and other shell forms can evade
this lint; it does not establish complete static analysis.
"""
from pathlib import Path
import re
import shlex
import sys


def shell_lines(text):
    """Omit comments and heredoc data; preserve executable shell tokens."""
    pending = []
    active = None
    for number, line in enumerate(text.splitlines(), 1):
        if active is not None:
            if line.lstrip('\t') == active:
                active = pending.pop(0) if pending else None
            continue
        # Delimiters are literal names in the bounded forms used by this tree.
        declarations = re.findall(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z_0-9]*)['\"]?", line)
        try:
            lexer = shlex.shlex(line, posix=True, punctuation_chars=';&|()<>')
            lexer.whitespace_split = True
            tokens = list(lexer)
        except ValueError:
            # Multiline quote constructs are a stated limit, not a false hit.
            tokens = []
        yield number, tokens
        if declarations:
            active, pending = declarations[0], declarations[1:]


def violations(root):
    for path in sorted(root.rglob('*')):
        if not path.is_file() or '.git' in path.parts:
            continue
        relative = path.relative_to(root)
        if relative.parts[0] == 'lib':
            continue
        try:
            content = path.read_text(errors='replace')
        except OSError:
            continue
        if (path.suffix == '.sh' or path.name == 'check' or
                re.match(r'^#![^\n]*\b(?:bash|sh)\b', content)):
            for number, tokens in shell_lines(content):
                if not tokens:
                    continue
                # Pattern literals: assignments/matching calls, never output data.
                is_output = tokens[0] in ('echo', 'printf')
                if path.suffix == '.sh' and relative.parts[0] != 'test' and not is_output:
                    for token in tokens:
                        if ('model-record:[[:' in token or
                                'pipeline-override:[' in token or
                                ('stage=(' in token and
                                 ('=' in token or any(t in ('grep', 'awk', 'sed', '=~') for t in tokens)))):
                            yield 'pattern', relative, number
                            break
                # Each command starts after a shell operator. Literal arguments
                # containing the record name are rejected only in matcher calls.
                command = None
                for token in ([] if is_output else tokens):
                    if token in (';', '|', '||', '&&', '&', '(', ')'):
                        command = None
                    elif token in ('grep', 'awk', 'sed', '=~'):
                        command = token
                    elif command and not token.startswith('-'):
                        if 'model-record' in token:
                            yield 'matcher', relative, number
                            break
                        command = None
                joined = ' '.join(tokens)
                if re.match(r'^(?:function\s+)?(?:live_text|md_strip_fences|rr_rounds)\s*(?:\(\s*\))?\s*\{', joined):
                    yield 'helper', relative, number
        if path.suffix == '.md' and ('skills' in relative.parts or 'ORCHESTRATOR' in path.name):
            fenced = False
            for number, line in enumerate(content.splitlines(), 1):
                if re.match(r'\s*(?:```|~~~)', line):
                    fenced = not fenced
                    continue
                if fenced or '--effort' not in line:
                    continue
                if re.search(r'\b(?:pass|supply|use|invoke|run|call)\b', line, re.I) and not re.search(r'\b(?:never|not|no longer|ignored|drop|historical|example)\b', line, re.I):
                    yield 'effort', relative, number


def main():
    print('check: one-definition syntax lint — this lint can be evaded')
    errors = list(violations(Path(sys.argv[1])))
    for category, path, line in errors:
        print(f'one-definition: {category}: {path}:{line}', file=sys.stderr)
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())

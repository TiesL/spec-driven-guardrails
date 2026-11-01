"""Offline documentation oracles for #622; never execute documented commands."""
import os
import re
import sys
from pathlib import Path


def invocations(text):
    # Metadata descriptions are not instructions to the adopted project's agent.
    if text.startswith('---\n'):
        text = text.split('---\n', 2)[-1]
    # Commands with arguments inside code spans, plus executable fenced lines.
    for span in re.findall(r'`([^`\n]*(?:\n[^`\n]+)?)`', text):
        match = re.match(r'\s*(?:bash\s+)?("?[^\s`]+\.sh"?)\s+\S', span)
        if match:
            yield match[1].strip('"')
        elif re.fullmatch(r'"?(?:\./|\.claude/|\.agents/|\$\{?SPEC_DRIVEN_GUARDRAILS_DIR\}?/)[^\s`]+\.sh"?', span):
            yield span.strip('"')
    fenced = False
    for line in text.splitlines():
        if line.startswith('```'):
            fenced = not fenced
            continue
        if fenced:
            match = re.match(r'\s*(?:bash\s+)?("?[^\s]+\.sh"?)(?:\s|$)', line)
            if match:
                yield match[1].strip('"')


def path_errors(text, project, clone):
    errors = []
    physical_paths = ('**Command paths.**' in text
                      and 'physical guardrails checkout' in text
                      and '$SPEC_DRIVEN_GUARDRAILS_DIR/<path>' in text)
    delegated_paths = ('resolved per' in text and '"Command paths"' in text
                       and 'pre-merge-review' in text)
    if delegated_paths:
        owner = project / '.claude/skills/pre-merge-review/SKILL.md'
        owner_text = owner.read_text() if owner.is_file() else ''
        physical_paths = ('**Command paths.**' in owner_text
                          and 'physical guardrails checkout' in owner_text
                          and '$SPEC_DRIVEN_GUARDRAILS_DIR/<path>' in owner_text)
    commands = list(invocations(text))
    qualified = {Path(command).name: command for command in commands if '/' in command}
    for command in commands:
        # A --help reference may use the basename of an explicitly qualified
        # command in this same document; no ambient PATH lookup is assumed.
        command = qualified.get(command, command) if '/' not in command else command
        prefix = re.match(r'\$(?:SPEC_DRIVEN_GUARDRAILS_DIR|\{SPEC_DRIVEN_GUARDRAILS_DIR\})/', command)
        if prefix:
            target = clone / command[prefix.end():]
        elif command.startswith('$wf/') and 'wf="${SPEC_DRIVEN_GUARDRAILS_DIR:-}"' in text:
            target = clone / command[len('$wf/'):]
        elif physical_paths and command.startswith(('skills/', 'templates/')):
            target = clone / command
        else:
            target = project / command
        if not target.is_file() or not os.access(target, os.X_OK):
            errors.append(command)
    return errors


def protection(text):
    flat = ' '.join(text.lower().split())
    return ("since there's no branch protection" not in flat
            and 'there is no technical block against direct pushes' not in flat
            and bool(re.search(r'private.{0,120}paid|paid.{0,120}private', flat))
            and bool(re.search(r'public[^.]{0,180}has (?:(?:real )?branch protection|it on [`a-z]+)', flat)))


def amendment(text):
    section = re.search(r'^### A26\b.*?(?=^### |\Z)', text, re.M | re.S)
    if not section:
        return False
    # A dated, explicitly current amendment, separate from the retained history.
    for paragraph in re.split(r'(?m)(?=^- )|\n\s*\n', section[0]):
        flat = ' '.join(paragraph.lower().split())
        if all(re.search(pattern, flat) for pattern in (
            r'amend', r'20\d\d-\d\d-\d\d', r'current', r'round[ -]trip',
            r'model', r'floor-basis', r'stage',
            r'effort.{0,100}(?:ignored|not|neither|no longer)|(?:no|neither|not|without).{0,100}effort',
        )):
            return True
    return False


def limits(text):
    header = text.split('set -uo pipefail', 1)[0].lower()
    known = re.search(r'known limits:([^\n]*(?:\n# [^\n]+)*)', header)
    detail = known[1] if known else ''
    return ('whatever its wording' not in header
            and 'at least as high as' in detail
            and 'superseded paragraph' in detail
            and 'instruction' in detail
            and bool(re.search(r'(?:miss|not detect|does not|cannot|doesn.t)', detail))
            and 'compared' in header and '--effort' in header)


def gate(text):
    header = text.split('set -uo pipefail', 1)[0]
    flat = ' '.join(header.lower().split())
    return (bool(re.search(r'the (?:merge )?guard prints the warning', flat))
            and 'the hook prints the warning' not in flat
            and all(len(line) <= 79 for line in header.splitlines()))


def check_controls(check, good, mutants):
    assert check(good), 'positive oracle control failed'
    for label, mutant in mutants:
        assert not check(mutant), 'surviving mutation: ' + label


def main():
    mode, root = sys.argv[1], Path(sys.argv[2])
    if mode == 'paths':
        project, clone = Path(sys.argv[3]), Path(sys.argv[4])
        for skill in sorted((project / '.claude/skills').glob('*/SKILL.md')):
            errors = path_errors(skill.read_text(), project, clone)
            assert not errors, f'{skill.parent.name}: unresolved invocations: {errors}'
        return
    if mode == 'path-controls':
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            project, clone = base / 'project', base / 'physical-checkout'
            for path in (project / '.claude/skills/review/run.sh', clone / 'skills/review/run.sh', project / 'check.sh'):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('#!/bin/sh\n')
                path.chmod(0o755)
            check = lambda text: not path_errors(text, project, clone)
            for good in ('` .claude/skills/review/run.sh <pr>`', '"$SPEC_DRIVEN_GUARDRAILS_DIR/skills/review/run.sh" <pr>', './check.sh .'):
                good = good.strip()
                if not good.startswith('`'):
                    good = '```bash\n' + good + '\n```'
                check_controls(check, good, [('dangling path', good.replace('run.sh', 'missing.sh').replace('check.sh', 'missing.sh'))])
            executable = project / 'check.sh'
            executable.chmod(0o644)
            assert not check('`./check.sh .`'), 'non-executable target escaped'
            executable.chmod(0o755)
            convention = ('**Command paths.** Bare paths use the physical guardrails checkout. '
                          'Invoke "$SPEC_DRIVEN_GUARDRAILS_DIR/<path>".\n')
            good = convention + '`skills/review/run.sh <pr>`'
            check_controls(check, good, [
                ('missing convention', good.replace('**Command paths.**', '')),
                ('dangling physical target', good.replace('run.sh', 'missing.sh')),
            ])
            owner = project / '.claude/skills/pre-merge-review/SKILL.md'
            owner.parent.mkdir(parents=True)
            owner.write_text(convention)
            delegated = '`skills/review/run.sh <pr>` (resolved per pre-merge-review, "Command paths")'
            check_controls(check, delegated, [('delegated target dangling', delegated.replace('run.sh', 'missing.sh'))])
            owner.write_text('')
            assert not check(delegated), 'delegated convention removal escaped'
            good = '`"$SPEC_DRIVEN_GUARDRAILS_DIR/skills/review/run.sh" <pr>` and `run.sh --help`'
            check_controls(check, good, [('qualified shorthand dangling', good.replace('run.sh', 'missing.sh'))])
            good = '```bash\nwf="${SPEC_DRIVEN_GUARDRAILS_DIR:-}"\n"$wf/skills/review/run.sh" <pr>\n```'
            check_controls(check, good, [('variable target dangling', good.replace('run.sh', 'missing.sh')),
                                       ('variable binding absent', good.replace('wf="${SPEC_DRIVEN_GUARDRAILS_DIR:-}"', ''))])
            check_controls(check, '`./check.sh`', [('no-argument dangling', '`./missing.sh`')])
            for bad in ('`skills/review/run.sh <pr>`', '```\ntemplates/check.sh <pr>\n```', '`review.sh <pr>`'):
                assert not check(bad), 'bare invocation escaped: ' + bad
        return
    if mode == 'protection':
        good = 'Private repos need a paid plan. This public repo has branch protection; PRs required.'
        check_controls(protection, good, [('private qualifier', good.replace('Private', 'All')), ('public exception', good.split(' This')[0]),
            ('negated public protection', good.replace('has branch protection', 'has no branch protection')),
            ('residual no-protection claim', good + " Since there's no branch protection."),
            ('residual no-technical-block claim', good + ' There is no technical block against direct pushes.')])
        shorthand = 'Branch protection needs a paid plan on a private repo; this public repo has it on main.'
        check_controls(protection, shorthand, [('missing shorthand exception', shorthand.split(';')[0])])
        for name in ('README.md', 'policy/WORKFLOW.md', 'PRD.md'):
            assert protection((root / name).read_text()), name + ': private/public protection framing differs'
    elif mode == 'amendment':
        good = '### A26 — marker\n\nAmendment (2026-11-01): current round-trip checks stage, model and floor-basis; effort is ignored.\n'
        check_controls(amendment, good, [(name, good.replace(value, '')) for name, value in (
            ('date', '2026-11-01'), ('amendment', 'Amendment'), ('current status', 'current'), ('model', 'model'), ('stage', 'stage'),
            ('basis', 'floor-basis'), ('effort exclusion', 'effort is ignored'))])
        assert amendment((root / 'ARCHITECTURE.md').read_text()), 'A26 lacks a dated current model-only round-trip amendment'
    elif mode == 'limits':
        good = '# Catches compared and --effort. Known limits: may miss "at least as high as" and instructions inside a superseded paragraph.\nset -uo pipefail\n'
        check_controls(limits, good, [(name, good.replace(value, '')) for name, value in (
            ('rewording limit', 'at least as high as'), ('marked paragraph limit', 'superseded'), ('instruction limit', 'instructions'),
            ('caught shapes', 'compared'), ('flag shape', '--effort'), ('limit qualification', 'miss'))]
            + [('overclaim', good.replace('Known limits:', 'whatever its wording. Known limits:'))])
        assert limits((root / 'test/cases/s240_live_docs_state_no_effort_rules.sh').read_text()), 'S240 header omits known limits or overclaims'
    elif mode == 'gate':
        good = '# The guard prints the warning; stream transcript only.\n# ' + 'x' * 77 + '\nset -uo pipefail\n'
        check_controls(gate, good, [('wrong owner', good.replace('guard', 'hook')), ('width', '# ' + 'x' * 78 + '\n' + good)])
        assert gate((root / 'skills/pre-merge-review/model-record-gate.sh').read_text()), 'gate header must name the guard and fit 79 columns'
    else:
        raise AssertionError('unknown mode ' + mode)


if __name__ == '__main__':
    main()

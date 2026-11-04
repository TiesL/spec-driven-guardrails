"""#647 mechanical subset only; no authorization or runtime-obedience claim.
Source-data seam: canonical Running section. Real-copy mutation controls run
after passing source assertions; permissive-injection controls also run on RED
source where applicable. Missing implementation stays RED, never replaced with
synthetic rules to claim a production pass.
"""
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RULES = {534: [('canonical panel subsection', '### Stage-selection panel'),
       ('canonical class subsection', '### Standing human class decisions')],
 535: [('ordinary panel record',
        '(?:ordinary|separate).{0,80}(?:comment|record).{0,120}temporary, panel decision'),
       ('stable identity and question', '(?:stable )?decision ID.{0,80}question'),
       ('named participants and positions',
        'Product.{0,60}Architect.{0,60}orchestrator.{0,100}positions'),
       ('vote dissent outcome exact stages',
        'vote.{0,60}dissent.{0,80}outcome.{0,100}(?:exact|selected) stages'),
       ('human-source link', 'link.{0,80}(?:standing human|human words)'),
       ('Discovery eligibility protections evidence',
        '(?:eligibility|protected-work).{0,200}(?:Discovery|discovery report)')],
 536: [('Discovery separate marker before panel',
        '(?:after|before).{0,100}Discovery.{0,120}(?:separate|own).{0,40}model-record'),
       ('issue text cannot substitute',
        'issue text.{0,70}(?:never|cannot|not).{0,60}(?:substitut|replac)'),
       ('consultation is not Planning', 'consultation.{0,60}(?:not|never).{0,40}Planning')],
 537: [('orchestrator protected', '(?:preserve|retain|never.skip).{0,80}orchestrator'),
       ('fresh Review protected', '(?:preserve|retain|never.skip).{0,180}fresh Reviewer'),
       ('independent scrutiny', '(?:at least one|another).{0,50}role other than the author'),
       ('Review skip escalates',
        '(?:skip Review|skip=Review).{0,120}(?:maintainer|escalat|refer)')],
 538: [('scenario AC requires Test', 'AC.{0,60}(?:add|new).{0,40}scenario.{0,60}requires Test'),
       ('executable diff requires Implementation',
        '(?:diff|change).{0,80}executable.{0,60}requires Implementation'),
       ('executable tests and scripts included', 'including executable tests and scripts'),
       ('protections before classification',
        '(?:checks|protections).{0,60}(?:precede|before).{0,30}class')],
 539: [('unanimous in-class selection',
        'unanimous.{0,80}(?:eligible|in-class).{0,80}(?:orchestrator|appl)'),
       ('Abbreviated exact pair', 'Abbreviated.{0,220}skip=Planning.{0,80}skip=Test'),
       ('A49 valid Test exemption', 'valid skip=Test.{0,100}A49.{0,100}exemption'),
       ('append-only scenario scope', 'append-only.{0,100}scenario'),
       ('Abbreviated refuses scenario AC conflict',
        'Abbreviated.{0,80}(?:unavailable|cannot|refus).{0,100}(?:Test|scenario)')],
 540: [('doc-only conditions and permitted scope',
        'doc-only.{0,120}skip=Implementation.{0,130}(?:verified|human) conditions'),
       ('configuration outside verified conditions',
        'configuration.{0,140}(?:conditions|eligib|Implementation)'),
       ('class cannot override protections',
        '(?:conditions|class).{0,90}(?:never override|cannot override|subject '
        'to).{0,70}(?:protect|AC1)')],
 541: [('test-only verified conditions',
        'test-only.{0,140}skip=Implementation.{0,140}(?:verified|human) conditions'),
       ('executable tests still require Implementation',
        'executable tests.{0,100}(?:require|retain).{0,30}Implementation')],
 542: [('2-1 skip escalates', '2-1.{0,50}(?:vote|skip).{0,160}(?:maintainer|escalat|refer)'),
       ('majority retains and records dissent',
        'majority.{0,40}retain.{0,100}dissent.{0,40}record'),
       ('missing participants cannot skip',
        'missing participants.{0,150}(?:full|required) pipeline')],
 543: [('outside-class per-item authority',
        'outside.{0,80}class.{0,130}(?:per-item|explicit).{0,80}human'),
       ('single-session not panel default',
        'single-session.{0,150}(?:not panel|never derives|not a panel)'),
       ('panel record alone insufficient',
        'panel record alone.{0,60}(?:never|cannot|not).{0,50}waiv'),
       ('single-session no QA exemption',
        'single-session alone.{0,80}(?:no|not).{0,40}QA.{0,40}exemption')],
 544: [('only orchestrator posts human identity',
        '(?:only the orchestrator|orchestrator alone).{0,200}human.{0,80}--decided-by'),
       ('unchanged single-quoted human reason', 'unchanged.{0,80}single.quot.{0,60}--reason'),
       ('unrepresentable words not rewritten',
        'unrepresentable.{0,150}never.{0,80}(?:sanitiz|rewrit|truncat)'),
       ('verify returned text', 'verify.{0,60}returned text'),
       ('closing issue linkage', '(?:title or body|title/body).{0,80}Closes #')],
 545: [('both records precede both deadlines',
        '(?:panel|decision).{0,100}(?:posting|waiver).{0,100}precede.{0,120}first.{0,40}commit.{0,80}PR'),
       ('initial base and commit identity', 'initial base SHA.{0,120}(?:first|none yet)'),
       ('times and identities', '(?:identities|identity).{0,80}creation times?'),
       ('tie and unknown not timely',
        '(?:unknown|equal).{0,120}(?:tie|equal|unknown).{0,80}(?:not timely|unresolved)'),
       ('late editing cannot backdate', 'edit.{0,80}late.{0,80}(?:cannot|not).{0,40}backdate'),
       ('inherited commits excluded', 'inherited.{0,80}commits.{0,40}(?:excluded|do not)'),
       ('history rewrite retains deadline',
        'rebas.{0,90}squash.{0,90}(?:not reset|retain).{0,50}deadline')],
 546: [('every decision record and outcome',
        'merge-approval.{0,160}every.{0,100}decision.{0,80}(?:record link|link).{0,60}outcome'),
       ('retained escalated superseded resolutions',
        'retained.{0,60}escalated.{0,60}superseded.{0,70}resolution'),
       ('risk and limit explicit acceptance',
        'widening.{0,60}limit.{0,80}risk.{0,80}explicit acceptance'),
       ('temporary acceptance OR43 and dependency', 'OR43'),
       ('dependency removal disclosed', '(?:removal|remov).{0,60}#645')],
 547: [('retain A13 depth or raise force-thorough',
        '(?:retain|preserve).{0,40}A13.{0,80}depth.{0,80}--force-thorough'),
       ('never lower depth', 'never lower.{0,60}(?:waiver|depth)'),
       ('stage presence only', 'stage presence only')],
 548: [('forgeability without authentication',
        '(?:cannot authenticate|not authentication|not authenticate)'),
       ('records forgeable', '(?:session.{0,40}forge|forgeable)'),
       ('unverifiable evidence blocks posting',
        '(?:unverif|missing).{0,70}(?:source|conditions|evidence).{0,160}(?:no '
        'posting|without.{0,30}posting|before.{0,20}skip)'),
       ('panel-name acceptance not permission', 'panel name.{0,160}not permission')]}
SNAPSHOTS = {'lib/markdown.sh': '4fa016febf33b7e972ccc64a154249863424972ff04e3837105d5bb9faa64505',
 'lib/model-record.sh': '0348c95cd8f1347cf893b688c65dec9e2ba2d6dbe65826d72e40d7144875e870',
 'pipeline-override.sh': 'a107b7379b33e5f25225a9f8c5bce54fd93727f85f9c496d1e590d7bdb4b4998',
 'skills/pre-merge-review/model-record-gate.sh': '05fa545d7d44e7e4d23e468a9abbd113dcdfbb5e5493d1b80766267783fd6925',
 'skills/role-contracts/ORCHESTRATOR.md': 'a85d1ca59e0b06e87a1a77b0b640033fbf7c9de5d4d010e84d538645c2cabe88',
 'skills/role-contracts/orchestrator-rules.tsv': 'a41764d85b4392adcf557389d5d69d84fb8445750cff7bcfe8a1ad4771cd3f99',
 'test/behavior/orchestrator-diff.stamp': 'c77f2e8db29dbbfc0081a3c6720f48f8ed5f481abce21316c083db5470dca568',
 'test/behavior/orchestrator-scenarios.md': 'c2eaf345bf0e847e51914145dcce7be37a6eda1a5e14a06bd1a8222a0abfca40',
 'test/fixtures/orchestrator-core-pins.tsv': 'c530682a65901dec340095667a78303308c3e184d24031a343623189b68ac667'}
errors = []

def check(ok, label):
    if not ok:
        errors.append(label)
        print('FAIL: ' + label)

def running(root):
    text = (root / 'skills/role-contracts/SKILL.md').read_text()
    return text.split('## Running the pipeline\n', 1)[1].split('\n---', 1)[0]

def norm(text):
    return re.sub(r'\s+', ' ', text.replace('`', '').replace('**', '')).lower()

def pin(text, pattern):
    return re.search(pattern.lower(), norm(text)) is not None

def controlled_oracle(text, predicate, label, mutants):
    """Same predicate checks production and every named weakening.

    Controls still run when production is RED; that does not claim a positive
    production witness. Each transform must change the actual source copy.
    """
    check(predicate(text), label)
    for name, mutate in mutants:
        weakened = mutate(text)
        if weakened == text:
            print('PENDING: ' + label + '/' + name + ' needs implementation witness')
            continue
        detected = not predicate(weakened)
        check(detected, label + '/' + name + ' rejected')
        if detected:
            print('CONTROL: ' + label + '/' + name + ' rejected')


def inject_control(text, predicate, label, sentence, anchor=None):
    """Append a permissive sentence to a structurally selected source unit.

    A cell is selected by its class row/header by the caller. Larger units use
    a heading or paragraph anchor, never the normative clause being tested.
    """
    check(predicate(text), label + '/unmodified PASS')
    if anchor is None:
        weakened = text + ' ' + sentence
    else:
        matches = list(re.finditer(anchor, text, re.M | re.I))
        check(len(matches) == 1, label + '/exactly one structural anchor')
        if len(matches) != 1:
            return text
        end = matches[0].end()
        weakened = text[:end] + ' ' + sentence + text[end:]
    check(weakened != text, label + '/mutation applied')
    check(not predicate(weakened), label + '/rejected by source predicate')
    if weakened != text and not predicate(weakened):
        print('CONTROL: ' + label + ' unmodified PASS; injection rejected')
    return weakened


POLICY_PARAGRAPH = r'^- \*\*Abbreviated workflow\*\*[^\n]*(?:\n[ \t]+[^\n]+)*'
STANDING_SECTION = r'(?s:^### Standing human class decisions\n(?:(?!\n### ).)*)'


def protected_work(text):
    # Anchor the entire directive, including its prefix/suffix: positive
    # keywords alone survive "Where practical, preserve ..." (Review M7).
    return bool(re.search(
        r'(?:^|[.!?] )preserve the orchestrator, review by a fresh reviewer, '
        r'discovery and at least one role other than the author seeing the change\.', norm(text)))


def late_record(text):
    return pin(text, r'a late record remains late; seek specific human resolution, '
                     r'never claim retroactive compliance\.')


def class_scope(value):
    return (not pin(value, r'\bnot only\b|\bor a unanimous panel\b')
            and pin(value, r'(?:only|limited to).{0,60}batches.{0,60}epic tiesl/spec-driven-guardrails#608')
            and pin(value, r'outside.{0,80}(?:scope|epic|batches).{0,100}requires? '
                           r'(?:explicit )?per-item human authority')
            # The complete scope clause must end at #608, not extend to other epics.
            and pin(value, r'(?:only|limited to).{0,60}batches.{0,60}'
                           r'epic tiesl/spec-driven-guardrails#608\s*(?:[.;]|$)'))


def executable_conditions(value):
    # Existing conditions invoke the unconditional protected-work checks;
    # explicit equivalent wording is also accepted. Both tests and production
    # code must be represented in this cell, not merely elsewhere in the file.
    return (pin(value, r'no executable production code.{0,160}protected-work checks come first, '
                       r'including executable tests/scripts and ac-dependent implementation')
            or pin(value, r'executable tests(?:/scripts)? and (?:any )?executable production code '
                          r'(?:still )?require implementation'))


def grant_source(value):
    explicit = pin(value, r'per-item human grant in (?:their|the human.s) own words is required')
    durable = bool(re.search(r'\[[^]]*(?:grant|human words)[^]]*\]\(https://[^)]+\)', value, re.I))
    self_link = bool(re.search(r'\]\((?:SKILL\.md)?#|\]\(skills/role-contracts/SKILL\.md', value, re.I))
    return (explicit or durable) and not self_link and not pin(value, r'\bunless\b|\bexcept\b')


def historical_example(text):
    section = text.split('### Standing human class decisions', 1)[-1].split('\n### ', 1)[0]
    # Every paragraph/row mentioning the old record must label its limitation.
    units = re.split(r'\n\s*\n|(?=^\|)', section, flags=re.M)
    return all(pin(unit, r'earlier record.{0,100}predates the executable-test rule')
               for unit in units if '#609' in unit)


def installed_skill_reference(text):
    # Limit consultation/timing checks to the policy entry point. Other prose
    # may discuss optional actions without weakening this directive.
    bullets = re.findall(r'^- \*\*Abbreviated workflow\*\*[^\n]*(?:\n[ \t]+[^\n]+)*', text, re.M | re.I)
    return (len(bullets) == 1
            and 'skills/role-contracts/SKILL.md' not in text
            and pin(bullets[0], r'installed role-contracts skill')
            and pin(bullets[0], r'stage-selection panel')
            and pin(bullets[0], r'read running the pipeline')
            and pin(bullets[0], r'before selecting stages or using pipeline-override\.sh')
            and not pin(bullets[0], r'\boptionally\b|\bafter using\b|\bexcept\b|\bunless\b'))


POST_TABLE_GRANT = ("For Abbreviated, obtain the maintainer's per-item grant in their own words; use "
                    "those words, never a policy paraphrase, as reason.")


def post_table_grant(text):
    section = text.split('### Standing human class decisions', 1)[-1].split('\n### ', 1)[0]
    # The row or earlier Abbreviated definition cannot satisfy this assertion.
    lines = section.splitlines()
    last_row = max((i for i, line in enumerate(lines) if line.startswith('|')), default=-1)
    prose = ' '.join(' '.join(lines[last_row + 1:]).split())
    return (POST_TABLE_GRANT in prose
            and not pin(prose, r'\b(?:unless|except)\b|'
                               r'panel[^.!?]*(?:waiv|without)[^.!?]*(?:grant|human)|'
                               r'(?:grant|human)[^.!?]*(?:waiv|optional|not required)'))


def source_checks(root, ident, tmp):
    # An unmodified sandbox copy is the positive control, never a hand-written
    # implementation of decisions. Each mutant changes only this asserted text.
    target = tmp / 'copy/skills/role-contracts'
    target.mkdir(parents=True)
    shutil.copy2(root / 'skills/role-contracts/SKILL.md', target / 'SKILL.md')
    text = running(tmp / 'copy')
    if ident == 537:
        controlled_oracle(text, protected_work, 'S537/unconditional protected work', [
            ('M7-' + hedge, lambda value, hedge=hedge: value.replace(
                'Preserve the orchestrator', hedge + ', preserve the orchestrator', 1))
            for hedge in ['Where practical', 'Ordinarily', 'May', 'Unless authorized']])
    if ident == 545:
        controlled_oracle(text, late_record, 'S545/late never retroactively compliant', [
            ('M10', lambda value: re.sub(
                r'A late record remains late;.*?retroactive compliance\.',
                'A late record may be accepted when the panel agrees.', value, flags=re.S))])
    for label, pattern in RULES[ident]:
        diagnostic = f'S{ident}/{label}'
        if not pin(text, pattern):
            check(False, diagnostic + ' missing from canonical Running section; real-copy mutation control pending implementation')
            continue
        mutable = norm(text)
        mutant, count = re.subn(pattern.lower(), '', mutable)
        check(count > 0 and mutant != mutable, diagnostic + '/mutation applied')
        check(not pin(mutant, pattern), diagnostic + '/deletion detected')
        print('CONTROL: ' + diagnostic + ' unmodified PASS; deletion rejected')

def reference_control(path, needles):
    text = path.read_text()
    for needle in needles:
        label = str(path.relative_to(ROOT)) + '/' + needle
        check(needle.lower() in text.lower(), 'S534/reference ' + label)
        if needle.lower() in text.lower():
            mutant = re.sub(re.escape(needle), '', text, flags=re.I)
            check(needle.lower() not in mutant.lower(), 'S534/reference mutant ' + label)

def projection_controls(tmp):
    # Exercise the existing check command against real unmodified data, then
    # one drift at a time. Generated files in the checkout are never edited.
    copy = tmp / 'projections'
    names = ['policy/WORKFLOW.md', 'skills/role-contracts/SKILL.md',
             'skills/role-contracts/ORCHESTRATOR.md', 'skills/model-choice/SKILL.md',
             'CHANGES.md', 'adapters/claude/INSTRUCTIONS.md',
             'adapters/codex/INSTRUCTIONS.md', 'WORKFLOW.md',
             'adapters/codex/AGENTS.md', 'AGENTS.md']
    for name in names:
        target = copy / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    def run():
        return subprocess.run([str(ROOT / 'check-workflow-adapters.sh'), str(copy)],
                              capture_output=True, text=True)
    baseline = run()
    check(baseline.returncode == 0, 'S534/unmodified projection copy: ' + baseline.stdout)
    if baseline.returncode:
        return
    for name in ['WORKFLOW.md', 'adapters/codex/AGENTS.md', 'AGENTS.md']:
        target = copy / name
        original = target.read_bytes()
        if name == 'AGENTS.md':
            mutated = original.replace(b'<!-- spec-driven-guardrails: begin -->',
                                       b'<!-- spec-driven-guardrails: begin -->\nprojection drift', 1)
        else:
            mutated = original + b'\nprojection drift\n'
        check(mutated != original, 'S534/projection mutation applied ' + name)
        target.write_bytes(mutated)
        result = run()
        check(result.returncode == 1 and 'drift: ' in result.stdout and name in result.stdout,
              'S534/projection drift diagnostic ' + name + ': ' + result.stdout)
        target.write_bytes(original)
    print('CONTROL: S534 unmodified projections PASS; three single-output drift mutants rejected')
    # N5/N6 change policy semantics, not projection consistency. Start afresh
    # for each arm; the unchanged generator must propagate the actual mutation.
    policy_path = copy / 'policy/WORKFLOW.md'
    original_policy = policy_path.read_text()
    outputs = ['WORKFLOW.md', 'adapters/codex/AGENTS.md', 'AGENTS.md']
    for name, new in [
            ('N5', 'Reading is optional: optionally skim Running the pipeline.'),
            ('N6', 'Consultation may occur after using `pipeline-override.sh`.')]:
        for path in ['policy/WORKFLOW.md', *outputs]:
            shutil.copy2(ROOT / path, copy / path)
        before = {path: (copy / path).read_bytes() for path in outputs}
        weakened = inject_control(original_policy, installed_skill_reference,
                                  'S534/' + name, new, POLICY_PARAGRAPH)
        policy_path.write_text(weakened)
        generated = subprocess.run([str(ROOT / 'generate-workflow-adapters.sh'), str(copy)],
                                   capture_output=True, text=True)
        check(generated.returncode == 0, 'S534/' + name + '/regenerate: ' + generated.stdout + generated.stderr)
        consistent = run()
        check(consistent.returncode == 0, 'S534/' + name + '/consistent projections: ' + consistent.stdout)
        for path in outputs:
            projection = (copy / path).read_bytes()
            check(projection != before[path] and new.encode() in projection,
                  'S534/' + name + '/propagated to ' + path)
            check(not installed_skill_reference(projection.decode()),
                  'S534/' + name + '/policy predicate rejects ' + path)


def cli(tmp):
    # Same narrow PIPELINE_OVERRIDE_GH Adapter as S376; no real gh/network.
    stub = tmp / 'gh'
    calls = tmp / 'calls'
    body = tmp / 'body'
    stub.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CAPTURE_CALLS"\ncat > "$CAPTURE_BODY"\necho https://example.invalid/issues/647#issuecomment-1\n')
    stub.chmod(0o755)
    env = dict(os.environ, PIPELINE_OVERRIDE_GH=str(stub), CAPTURE_CALLS=str(calls), CAPTURE_BODY=str(body))
    def post(issue, reason, scopes, human="SyntheticHuman"):
        args = [str(ROOT / 'pipeline-override.sh'), str(issue)]
        for scope in scopes:
            args += ['--scope', scope]
        return subprocess.run(args + ['--decided-by', human, '--reason', reason], env=env, capture_output=True)
    reason = '  synthetic standing words `tick` $literal  '
    result = post(647, reason, ['skip=Planning', 'skip=Test'])
    check(result.returncode == 0, 'S544/CLI accepted legal synthetic evidence')
    def captured_matches(expected_issue, expected_reason):
        lines = body.read_text().splitlines()
        markers = [f'<!-- pipeline-override: decided-by="SyntheticHuman" scope="{scope}" reason="{expected_reason}" -->'
                   for scope in ['skip=Planning', 'skip=Test']]
        return (calls.read_text().splitlines()[-1] == f'issue comment {expected_issue} --body-file -'
                and lines[:2] == markers and lines[2:3] == [''])
    check(captured_matches(647, reason), 'S544/CLI exact issue human reason scopes')
    check(len(calls.read_text().splitlines()) == 1, 'S544/CLI one comment')
    check(b'Closes #647' in result.stdout and b'issuecomment-1' in result.stdout,
          'S544/CLI returned comment and closing linkage')
    result = post(648, reason, ['skip=Planning', 'skip=Test'])
    check(result.returncode == 0 and not captured_matches(647, reason),
          'S544/CLI wrong-issue posting detected by same oracle')
    result = post(647, reason.strip(), ['skip=Planning', 'skip=Test'])
    check(result.returncode == 0 and not captured_matches(647, reason),
          'S544/CLI altered-reason posting detected by same oracle')
    result = post(647, reason, ['skip=Planning', 'skip=Test'], human='panel')
    check(result.returncode == 0 and not captured_matches(647, reason),
          'S544/CLI panel-name mismatch detected; acceptance is not authority')
    result = post(647, reason, ['skip=Planning', 'skip=Test', 'skip=Implementation'])
    check(result.returncode == 0 and not captured_matches(647, reason),
          'S544/CLI extra-scope posting detected')
    before = calls.read_bytes()
    result = post(647, 'cannot "represent" this', ['skip=Test'])
    check(result.returncode == 2 and calls.read_bytes() == before, 'S544/CLI refusal without posting or rewriting')
    print('CONTROL: S544 CLI exact reason, issue mismatch, unrepresentable words PASS')

def catalogue(text):
    # Inspect distinct cells, so a link mentioning conditions cannot fill an
    # empty eligibility field. No prose about evidence gaps is pinned.
    section = text.split('### Standing human class decisions', 1)[-1].split('\n### ', 1)[0]
    inject_control(text, post_table_grant, 'S548/N4',
                   'For Abbreviated, the panel may apply the track without a per-item human grant.',
                   STANDING_SECTION)
    check(post_table_grant(text.replace(POST_TABLE_GRANT, POST_TABLE_GRANT.replace(' ', '\n'))),
          'S548/post-table grant accepts whitespace reflow')
    inject_control(text, post_table_grant, 'S548/N9-appended-grant-waiver',
                   'A unanimous panel may waive the per-item human grant.', STANDING_SECTION)
    rows = [line for line in section.splitlines() if line.startswith('|')]
    fields = {'human': r'human|identity|decided.by',
              'source link': r'source|words', 'scope': r'scope|skip',
              'conditions': r'condition|eligib'}
    headers = [line for line in rows if re.match(r'^\|\s*Class\s*\|', line, re.I)
               and all(re.search(pattern, line, re.I) for pattern in fields.values())]
    check(len(headers) == 1, 'S548/catalogue distinct human/source/scope/conditions header')
    if len(headers) != 1:
        return
    header = headers[0]
    cells = [cell.strip() for cell in header.strip('|').split('|')]
    indices = {}
    for label, pattern in fields.items():
        found = [i for i, cell in enumerate(cells) if re.search(pattern, cell, re.I)]
        check(len(found) == 1, 'S548/catalogue header ' + label)
        if len(found) == 1:
            indices[label] = found[0]
    if len(indices) != 4:
        return
    check(len(set(indices.values())) == 4, 'S548/catalogue independent evidence columns')
    if len(set(indices.values())) != 4:
        return
    for label in fields:
        mutated = cells.copy()
        mutated[indices[label]] = ''
        check(not any(re.search(fields[label], cell, re.I) for cell in mutated),
              'S548/catalogue header deletion ' + label)
    check(grant_source('[human grant words](https://example.invalid/grant)'),
          'S548/Abbreviated durable grant source remains supported')
    controlled_oracle(text, historical_example, 'S548/#609 historical status', [
        ('eligible-example', lambda value: value +
            '\n\nTiesL/spec-driven-guardrails#609 is an eligible example record.')])
    for name in ['Abbreviated', 'test-only']:
        selected = [line for line in rows if name.lower() in line.lower()]
        check(len(selected) == 1, 'S548/catalogue row ' + name)
        if len(selected) != 1:
            continue
        row = selected[0]
        check(not any(name.lower() in line.lower() for line in rows if line != row),
              'S548/catalogue row deletion ' + name)
        values = [cell.strip() for cell in row.strip('|').split('|')]
        check(len(values) == len(cells), 'S548/catalogue row shape ' + name)
        if len(values) != len(cells):
            continue
        predicates = {'human': lambda value: bool(re.search(
                          r'\b(?:maintainer|(?:project(?:\'s)? )?human decision[- ]maker)\b',
                          value, re.I)),
                      'source link': lambda value: bool(re.search(r'\[[^]]+\]\([^)]*\)', value)),
                      'scope': lambda value: 'skip=' in value,
                      'conditions': lambda value: bool(value.strip(' `-'))}
        if name == 'Abbreviated':
            # A policy self-link is guidance, not a per-item human grant.
            controlled_oracle(values[indices['source link']], grant_source,
                              'S548/Abbreviated human grant source', [
                ('self-link', lambda value: value + ' [Standing paragraph above](SKILL.md#running-the-pipeline)')])
            inject_control(values[indices['source link']], grant_source, 'S548/N3',
                           'The per-item human grant is required unless the panel is unanimous.')
            inject_control(values[indices['source link']], grant_source,
                           'S548/N8-panel-grant-exception',
                           'The per-item human grant is required except when the panel agrees.')
            predicates['source link'] = grant_source
        else:
            conditions = values[indices['conditions']]
            controlled_oracle(conditions, class_scope, 'S548/#608 batch scope and outside authority', [
                ('M8', lambda value: 'mostly documentation or tests'),
                ('scope-deleted', lambda value: re.sub(r'(?i)(?:only|limited to).*?#608', '', value)),
                ('authority-deleted', lambda value: re.sub(r'(?i)per-item human authority', '', value))])
            check(class_scope(conditions.replace('applies only to', 'is limited to')),
                  'S548/class scope accepts equivalent limited-to wording')
            inject_control(conditions, class_scope, 'S548/N1',
                           'This does not apply: it applies not only to batches.')
            inject_control(conditions, class_scope, 'S548/N2',
                           'Authority may come from the human or a unanimous panel.')
            inject_control(conditions, class_scope, 'S548/N7-other-epics',
                           'Standing authority covers not only epic #608 but also other epics.')
            controlled_oracle(conditions, executable_conditions, 'S548/executable work requires Implementation', [
                ('M8', lambda value: 'mostly documentation or tests'),
                ('executable-tests-deleted', lambda value: re.sub(r'(?i)executable tests(?:/scripts)?', '', value)),
                ('production-code-deleted', lambda value: re.sub(r'(?i)executable production code', '', value))])
        for label, predicate in predicates.items():
            value = values[indices[label]]
            check(predicate(value), 'S548/catalogue ' + name + '/' + label)
            if predicate(value):
                check(not predicate(''), 'S548/catalogue field deletion ' + name + '/' + label)
            if label == 'human':
                for invalid in ['TiesL', 'panel', 'orchestrator', '[source](https://example.invalid)']:
                    check(not predicate(invalid),
                          'S548/catalogue rejects non-role identity ' + name + '/' + invalid)
                for role in ['maintainer', "project's human decision-maker"]:
                    check(predicate(role), 'S548/catalogue accepts human role ' + name + '/' + role)

def valid_variant_controls(tmp, ident):
    """Run the complete fixtures (including negative controls) on real variants.

    The environment flag only prevents recursive positive-control subprocesses;
    it never disables a source assertion or a mutation control.
    """
    if os.environ.get('STAGE_SELECTION_VALID_VARIANT') == '1':
        return
    copy = tmp / 'valid-variant'
    shutil.copytree(ROOT, copy, ignore=shutil.ignore_patterns('.git', '__pycache__'))
    variants = {
        534: [('consultation-whitespace', 'policy/WORKFLOW.md',
               r'read\s+Running\s+the\s+pipeline', 'read   Running the pipeline'),
              ('consultation-whitespace-comma', 'policy/WORKFLOW.md',
               r'read\s+Running\s+the\s+pipeline,?', 'read   Running the pipeline,')],
        548: [
            ('scope-the-batches', 'skills/role-contracts/SKILL.md',
             r'applies only to batches', 'applies only to the batches'),
            ('limited-the-batches', 'skills/role-contracts/SKILL.md',
             r'applies only to batches', 'is limited to the batches'),
            ('limited-scope', 'skills/role-contracts/SKILL.md',
             r'(?:applies\s+only\s+to|is\s+limited\s+to|is\s+restricted\s+only\s+to)\s+batches',
             'is limited to batches'),
            ('restricted-scope', 'skills/role-contracts/SKILL.md',
             r'(?:applies\s+only\s+to|is\s+limited\s+to|is\s+restricted\s+only\s+to)\s+batches',
             'is restricted only to batches'),
            ('scope-punctuation', 'skills/role-contracts/SKILL.md',
             r'(epic\s+TiesL/spec-driven-guardrails#608)\s*[.;]',
             r'\1.'),
            ('durable-grant', 'skills/role-contracts/SKILL.md',
             r'Per-item human grant in their own words is required; link its durable words before posting\.|'
             r'\[human grant words\]\(https://example\.invalid/grant\)',
             '[human grant words](https://example.invalid/grant)'),
        ],
    }[ident]
    if ident == 534:
        variants += [
            ('consultation-bold', 'policy/WORKFLOW.md',
             r'read Running the pipeline', 'read **Running the pipeline**'),
            ('consultation-tabs', 'policy/WORKFLOW.md',
             r'read Running the pipeline', 'read\tRunning\tthe\tpipeline'),
            ('consultation-case', 'policy/WORKFLOW.md',
             r'read Running the pipeline', 'READ Running the pipeline'),
            ('consultation-bold-read', 'policy/WORKFLOW.md',
             r'read Running the pipeline', '**read** Running the pipeline'),
            ('consultation-reflow', 'policy/WORKFLOW.md',
             r'read Running the pipeline', 'read  Running  the  pipeline'),
        ]
    else:
        variants += [
            ('scope-within', 'skills/role-contracts/SKILL.md',
             r'batches of epic', 'batches within epic'),
            ('explicit-authority', 'skills/role-contracts/SKILL.md',
             r'requires per-item human authority', 'requires explicit per-item human authority'),
            ('durable-human-words', 'skills/role-contracts/SKILL.md',
             r'Per-item human grant in their own words is required; link its durable words before posting\.|'
             r'\[human grant words\]\(https://example\.invalid/grant\)',
             '[human words](https://example.invalid/grant)'),
        ]
        variants += [('extra-scope-' + str(i), 'skills/role-contracts/SKILL.md',
                      r'applies only to batches', phrase)
                     for i, phrase in enumerate([
                         'applies only to these batches',
                         'applies **only** to batches',
                         'is limited to **the batches**',
                         'is restricted only to the batches',
                         'is exclusively limited to batches',
                         'applies ONLY to batches',
                         'is limited to batches,',
                     ])]
    originals = {path: (copy / path).read_text() for _, path, _, _ in variants}
    for name, path, locator, new in variants:
        target = copy / path
        changed, count = re.subn(locator, new, originals[path], flags=re.I)
        check(count == 1, f'S{ident}/{name} valid variant located exactly once')
        target.write_text(changed)
        if ident == 534:
            result = subprocess.run([str(copy / 'generate-workflow-adapters.sh'), str(copy)],
                                    capture_output=True, text=True)
            check(result.returncode == 0, 'S534/valid variant regenerated: ' + result.stdout + result.stderr)
        for case in (534, 548):
            result = subprocess.run(['python3', str(copy / 'test/fixtures/stage-selection-647.py'), str(case)],
                                    env=dict(os.environ, STAGE_SELECTION_VALID_VARIANT='1'),
                                    capture_output=True, text=True)
            check(result.returncode == 0,
                  f'S{ident}/{name} valid variant complete S{case}: ' + result.stdout + result.stderr)
        target.write_text(originals[path])
        print(f'CONTROL: S{ident}/{name} legitimate variant complete S534/S548 fixtures exercised')


ident = int(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='stage-selection-647-') as scratch:
    tmp = Path(scratch)
    source_checks(ROOT, ident, tmp)
    if ident == 534:
        for path, needles in {
            'policy/WORKFLOW.md': ['- **Abbreviated workflow**', 'role-contracts', 'Stage-selection panel', 'pipeline-override.sh'],
        }.items():
            reference_control(ROOT / path, needles)
        # README is a repo-root document: it may point at the canonical source by
        # repo-relative path or by the installed skill name (both resolve for its
        # reader); it must name Stage-selection panel and one of the two pointers.
        readme = (ROOT / 'README.md').read_text()
        for needle in ['Stage-selection panel']:
            reference_control(ROOT / 'README.md', [needle])
        pointer = re.compile(r'skills/role-contracts/SKILL\.md|installed `?role-contracts`? skill', re.I)
        row = [l for l in readme.splitlines() if 'pipeline-override.sh' in l and l.startswith('|')]
        check(bool(row) and bool(pointer.search(row[0])), 'S534/README canonical-source pointer in the pipeline-override.sh row')
        if row:
            mutant = pointer.sub('', row[0])
            check(not pointer.search(mutant), 'S534/README pointer mutant')
        policy = (ROOT / 'policy/WORKFLOW.md').read_text()
        check(installed_skill_reference(policy + '\nOptionally consult unrelated guidance after using other tools.\n'),
              'S534/consultation excludes unrelated prose')
        check(installed_skill_reference(policy.replace('read Running the pipeline',
                                                       'read   Running the pipeline')),
              'S534/consultation accepts whitespace reflow')
        controlled_oracle(policy, installed_skill_reference, 'S534/installed skill policy pointer', [
            ('repo-relative-link', lambda value: value + '\n[Running](skills/role-contracts/SKILL.md#running-the-pipeline)')])
        inject_control(policy, installed_skill_reference, 'S534/N10-panel-consultation-exception',
                       'Consultation is required except when the panel chooses otherwise.',
                       POLICY_PARAGRAPH)
        projection_controls(tmp)
    if ident == 544:
        cli(tmp)
    if ident == 548:
        catalogue(running(ROOT))
        for path, digest in SNAPSHOTS.items():
            content = (ROOT / path).read_bytes()
            check(hashlib.sha256(content).hexdigest() == digest, 'S548/unchanged ' + path)
            check(hashlib.sha256(content + b'\n').hexdigest() != digest, 'S548/byte mutation ' + path)
        print('CONTROL: S548 frozen production hashes and byte mutants PASS')
    if ident in (534, 548):
        valid_variant_controls(tmp, ident)
sys.exit(bool(errors))

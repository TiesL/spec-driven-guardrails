"""A49 text seam, not a claim that an agent obeyed the instructions.

Each obligation has an independent compliant witness. Removing that obligation
must be detected before inspecting loaded text (mutation controls).
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
ROLES = 'skills/role-contracts/SKILL.md'
ORCH = 'skills/role-contracts/ORCHESTRATOR.md'
WRITE = 'skills/write-spec/SKILL.md'
TDD = 'skills/tdd-seams/SKILL.md'


def section(text, name):
    match = re.search(r'^## ' + re.escape(name) + r'\s*\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    return match.group(1) if match else ''


def rule(text, number):
    match = re.search(r'^- ' + number + r'\b.*(?:\n +[^\n]+)*', text, re.M)
    return match.group() if match else ''


# id, path, scope, regex, independently written compliant witness.
PINS = {
460: [
    ('or19-conflict', ORCH, 'OR19', r'(spec|scenario).*conflict.*stop|stop.*(spec|scenario).*conflict', 'Any stage: spec or scenario conflict requires a stop.'),
    ('or19-preserve', ORCH, 'OR19', r'(byte.identical|unchanged).*detect|detect.*(byte.identical|unchanged)', 'Keep protected text byte-identical at detection.'),
    ('or19-patch-route', ORCH, 'OR19', r'A12.*(before|prior).*revert.*(class|finding).*(OR17|A28)', 'Save patch under A12 before revert; report finding class and falsifying check, follow OR17/A28.'),
    ('shared-stop', ROLES, 'Shared, across all five roles', r'(spec|scenario).*conflict.*stop.*(owner|owning)', 'A spec/scenario conflict stops the affected change until the owning role resolves it.'),
    ('shared-protected-files', ROLES, 'Shared, across all five roles', r'PRD\.md.*ARCHITECTURE\.md.*TEST-SCENARIOS\.md.*byte.identical.*detect.*(earlier|prior).*owner', 'Keep PRD.md, ARCHITECTURE.md and TEST-SCENARIOS.md byte-identical at detection, including earlier legitimate owner edits.'),
    ('shared-falsifier', ROLES, 'Shared, across all five roles', r'(class|classified).*falsifying check.*evidence', 'Report the finding class, falsifying check and evidence.'),
    ('shared-disclosure', ROLES, 'Shared, across all five roles', r'disclos.*(not|never).*authoriz', 'Disclosure does not authorize an oracle edit.'),
    ('shared-classification', ROLES, 'Shared, across all five roles', r'(wrong|ambiguous).*spec.*faulty.*test.*structur.*design.*OR18', 'Wrong or ambiguous requirements: spec; faulty tests: test; structural decisions: design; unresolved classification: OR18.'),
],
461: [
    ('developer-exclusion', ROLES, 'Fullstack Developer', r'(exclud|never|must not).*PRD\.md.*ARCHITECTURE\.md.*TEST-SCENARIOS\.md', 'Developer-authored docs edits exclude PRD.md, ARCHITECTURE.md and TEST-SCENARIOS.md.'),
    ('authorship', ROLES, 'Fullstack Developer', r'commit.*owner.authored.*(not|never).*transfer.*author', 'Committing owner-authored scenarios with tests does not transfer authorship.'),
],
462: [
    ('owner-reconciliation', WRITE, '', r'diverg.*(owner|owning).*reconcil|reconcil.*(owner|owning).*diverg', 'Implementation divergence requires owning-role reconciliation.'),
    ('historical-identities', WRITE, '', r'observed.*main.*SHA.*merge.base.*SHA.*(differ|separate)', 'Record observed main SHA and merge-base SHA separately when different.'),
    ('historical-evidence', WRITE, '', r'(current|existing|unchanged).*falsifying.*(command|check).*expected.*(Product|QA).*(run|lookup)', 'Each current/existing/unchanged clause needs a falsifying command, observable expected result and Product/QA run evidence or concrete lookup.'),
    ('historical-unresolved', WRITE, '', r'unverified.*unresolved.*revalid.*main.*merge', 'Unverified claims stay unresolved; revalidate relevant main changes before merge.'),
    ('preservation-base', WRITE, '', r'preserv.*(run|assert).*merge.base|preserv.*merge.base.*(run|assert)', 'Preservation assertions run on the merge base.'),
],
463: [
    ('architect-ac', ROLES, 'Architect', r'(every|each|which).*AC.*(contradict|narrow).*(none|no contradiction)', 'Name each AC contradicted or narrowed, or explicitly state none.'),
    ('old-green', TDD, '', r'preserv.*green.*merge.base.*red.*spec.*stop', 'Preserved behavior must be green on the recorded merge base; red is a spec finding requiring a stop.'),
    ('no-oracle-rewrite', TDD, '', r'(not|never|no).*rewrit.*(scenario|oracle|expected)', 'Never rewrite the scenario or expected value to fit the implementation.'),
    ('new-red', TDD, '', r'new behavior.*red.before.green', 'New behavior still needs red-before-green.'),
],
464: [
    ('qa-publish', ROLES, 'QA', r'before.*(Implementation|Developer).*git diff --full-index.*TEST-SCENARIOS\.md.*tilde', 'Before Implementation publish git diff --full-index of TEST-SCENARIOS.md in a tilde fence.'),
    ('qa-identities', ROLES, 'QA', r'full.*base SHA.*base_sha256.*result_sha256', 'Record full base SHA, base_sha256 and result_sha256.'),
    ('qa-verification', ROLES, 'QA', r'(raw|unrendered).*comment.*verif.*(published|handoff)', 'Read raw comment body and verify the published artifact before handoff.'),
    ('qa-transport', ROLES, 'QA', r'base64.*same.*diff.*(both|two).*hash', 'Fallback is base64 of the same unified diff with both hashes verified.'),
    ('qa-empty-limit', ROLES, 'QA', r'(empty|unchanged).*equal.*hash.*(65,?536|comment limit).*unresolved.*pushed.ref', 'An empty diff has equal hashes; above the 65,536 comment limit handoff is unresolved and triggers the pushed-ref alternative.'),
],
465: [
    ('qa-supersede', ROLES, 'QA', r'new.*report.*supersed.*retain.*(prior|earlier)', 'Each changed handoff gets a new linked report superseding and retaining prior reports.'),
    ('qa-resume', ROLES, 'QA', r'resum.*(applicable|selected).*artifact.*(missing|unreadable|unusable).*unresolved', 'Resume selects the applicable artifact; missing or unreadable evidence leaves handoff unresolved.'),
    ('brief-provenance', ORCH, 'OR15', r'QA artifact.*comparison.*(finding|resolution)', 'Add applicable QA artifact, comparison log and finding/resolution links.'),
    ('reviewer-provenance', ROLES, 'Reviewer / Lead Developer', r'(verif|check).*provenance.*(fidelity|test)', 'Verify scenario provenance and actual test fidelity.'),
    ('qa-scope', ROLES, 'QA', r'(no test.code|writes no test code)', 'QA writes no test code itself.'),
],
466: [
    ('no-agent-compare', ORCH, 'OR46', r'\(c\).*compar.*(QA|artifact).*committed', '(c) Read-only comparison of the QA artifact and committed Developer head.'),
    ('compare-command', ROLES, '', r'git apply', 'Reconstruct with git apply outside the repository.'),
    ('compare-inputs', ROLES, '', r'repository identity.*(comment ID|report ID).*(head SHA|Developer head).*(base SHA|base)', 'Inputs: repository identity, selected comment ID, full head SHA and applicable base SHA.'),
    ('compare-reconstruct', ROLES, '', r'git show.*TEST-SCENARIOS\.md.*outside.*repositor.*(both|two).*hash', 'Read git show <base>:TEST-SCENARIOS.md; apply outside the repository and verify both hashes.'),
    ('compare-status', ROLES, '', r'0.*match.*1.*different.*2.*unusable.*only 0.*Review', 'Exit 0 match, 1 different, 2 unusable evidence; only 0 permits Review.'),
    ('compare-rebase', ROLES, '', r'merged.*main.*re.apply.*new base.*whole.*byte', 'If branch merged main, re-apply to the new base and compare the whole file byte for byte.'),
    ('compare-owner', ROLES, '', r'(each|every).*hunk.*finding.*owning.*new QA artifact.*matching comparison', 'Every differing hunk needs a finding and owning-role resolution, then a new QA artifact and matching comparison before Review.'),
    ('compare-log', ROLES, '', r'QA provenance: command=.*artifact=.*base=.*base_sha256=.*qa_sha256=.*head=.*committed_sha256=.*exit=.*result=match\|different\|unresolved.*findings=.*supersedes=', 'QA provenance: command=<invocation>; artifact=<URL>; base=<SHA>; base_sha256=<hash>; qa_sha256=<hash>; head=<SHA>; committed_sha256=<hash>; exit=<status>; result=match|different|unresolved; findings=<links or none>; supersedes=<URL or none>'),
    ('compare-unknown', ROLES, '', r'(unknown|unavailable).*identit.*unavailable|unknown.*unavailable', 'Unknown identities use unavailable.'),
],
}


def matches(pattern, text):
    return bool(re.search(pattern, re.sub(r'\s+', ' ', text.replace('`', '')), re.I))


def check(number):
    failures = []
    for label, path, scope, pattern, witness in PINS[number]:
        assert matches(pattern, witness), 'broken positive control: ' + label
        assert not matches(pattern, ''), 'broken deletion control: ' + label
        # Remove exactly one obligation from an otherwise compliant contract.
        compliant = '\n'.join(row[4] for row in PINS[number]
                              if row[1:3] == (path, scope))
        assert matches(pattern, compliant), 'broken complete control: ' + label
        mutant = compliant.replace(witness, '', 1)
        assert not matches(pattern, mutant), 'obligation deletion escaped: ' + label
        # Add unrelated compliant text around a removed obligation: unrelated
        # requirements must never mask its absence.
        assert not matches(pattern, 'Keep unrelated evidence.\nContinue other work.'), label
        text = (ROOT / path).read_text()
        if scope.startswith('OR'):
            text = rule(text, scope)
        elif scope:
            text = section(text, scope)
        if not matches(pattern, text):
            failures.append(f'S{number}/{label}: {path} must say: {witness}')
    if number == 462:
        text = (ROOT / WRITE).read_text()
        if re.search(r'update\s+them\s+as\s+soon\s+as the implementation diverges', text):
            failures.append('S462/unconditional-divergence: remove unconditional instruction to update specs when implementation diverges; route to owner')
    for failure in failures:
        print('FAIL: ' + failure)
    return bool(failures)


if __name__ == '__main__':
    sys.exit(check(int(sys.argv[1])))

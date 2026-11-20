<!-- Draft. Title: "Spec and architecture record for multi-runtime orchestration". Labels: process, documentation, status:backlog. Release-branch member. -->

## Description
Write the shared spec the other items cover: the PRD epic section (outcomes, scope, AC-1..AC-16
from PRODUCT-REPORT.md R3.3), the TEST-SCENARIOS entries the later items cover, and an
ARCHITECTURE entry (A40) recording the modules and seams (manager, runtime session adapter,
limit ledger, wake), with W0's results folded in. Also record the canonical policy sentences
that several items depend on: "limited is not unavailable" (pause, record the reset, resume),
the v1 Claude-outage behaviour (Claude-side coordination waits), the Q4 precedence rules, the
model defaults, where a work item's size is stored (body field or `size:*` label) and the
mechanical test for "Claude-specific" vs "Codex-specific".

## Acceptance criteria

### AC1: Every epic AC traces to a scenario
- Given AC-1..AC-16 of the epic
- When the PRD section and scenarios are written
- Then each AC has at least one scenario with a **Covers:** field, and `check-traceability.sh` and `check-scenario-file-sync.sh` pass

### AC2: Architecture entry names modules and seams
- Given W0's recorded facts
- When A40 is written
- Then it names each module, its interface and its adapters, refuses the hypothetical seams listed in ARCHITECT-REPORT.md §3, and cites W0 for every runtime fact it relies on

### AC3: Size and runtime-specific test are mechanical
- Given a work item under the epic
- When the manager would read its size and runtime fit
- Then the spec names exactly where the size lives and the path-based test for runtime-specific, so neither is a judgment at assignment time

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** W0
**Blocks:** W3, W4, W5, W6, W7, W8
**Size:** S
**Runtime fit:** either (Claude by default, docs only)

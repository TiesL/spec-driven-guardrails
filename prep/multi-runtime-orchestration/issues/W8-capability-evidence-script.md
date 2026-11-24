<!-- Draft. Title: "capability-evidence.sh: read-only per runtime, model and stage evidence". Labels: process, enhancement, status:backlog. Release-branch member. -->

## Description
A read-only script, run by path, in the family of `compliance-evidence.sh`, derived on demand
from GitHub artifacts: per (runtime, model, stage) the number of stages carried (n), findings
raised against that stage's output by class and severity (unattributable when a stage had several
models), review rounds and loop-backs, observed cost where available, and #503 defects per
runtime. It always prints n and never a rank. A snapshot is recorded only at a profile revision
point (about a week after start, per the maintainer's budget-ratio plan). Reuses
`lib/model-record.sh`, `lib/review-rounds.sh` and the carry-forward finding parser.

## Acceptance criteria

### AC1: Evidence with n, no rank
- Given PRs with `model-record` markers and findings
- When the script runs
- Then it prints one row per (runtime, model, stage) with n, and no ordering or ranking claim

### AC2: Honest attribution
- Given a finding against a stage that had more than one model
- When it is counted
- Then it is reported as unattributable, not assigned to a guessed model

### AC3: Read-only
- Given any run
- When it ends
- Then nothing on GitHub or in the repo was written

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** W1
**Blocks:** none
**Size:** M
**Runtime fit:** either; Claude by the rule (not small)

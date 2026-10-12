## #430 AC1 — adopter corpus at release head `5d239e4`

Snapshot: 2026-10-12 21:43 UTC, before this comment. The release-head
`rec_scan_bundle` read issue bodies, PR bodies, issue/PR comments and PR review
bodies through REST. Counts are `ok / near-miss / quoted`; no private body
text is reproduced.

| Adopter | Roles opted in | Bodies | model-record | pipeline-override | Inline rows |
| --- | --- | ---: | --- | --- | ---: |
| spec-driven-guardrails | yes | 1302 | 577 / 0 / 50 | 1 / 0 / 1 | 0 |
| tennis-invoicing | yes | 79 | 37 / 0 / 0 | 2 / 0 / 0 | 0 |
| sdg-dryrun-scratch | yes | 47 | 19 / 11 / 0 | 0 / 0 / 0 | 5 |
| tennis-admin | no | 44 | 0 / 0 / 0 | 0 / 0 / 0 | 0 |
| tennis-registration | no | 25 | 0 / 0 / 0 | 0 / 0 / 0 | 0 |
| agentic-workflow-installer | no | 26 | 3 / 0 / 0 | 0 / 0 / 0 | 0 |
| portfolio-mgt-agents (Ties-IT-advies) | no | 39 | 5 / 0 / 0 | 0 / 0 / 0 | 0 |

The five inline rows are intentional scratch fixtures:
[Discovery](https://github.com/TiesL/sdg-dryrun-scratch/issues/13#issuecomment-6132450170),
[Planning](https://github.com/TiesL/sdg-dryrun-scratch/issues/13#issuecomment-6132450453),
[Test](https://github.com/TiesL/sdg-dryrun-scratch/issues/13#issuecomment-6132450696),
[Implementation](https://github.com/TiesL/sdg-dryrun-scratch/issues/13#issuecomment-6132451072),
and [Review](https://github.com/TiesL/sdg-dryrun-scratch/pull/14#issuecomment-6132451358).
Their near-miss reason is `not on a line of its own`. The six other scratch
near misses have no quoted, non-blank model. No other scanned adopter has an
inline row.

Open opted-in PRs with a changed **blocking** verdict versus v0.3.0:
[scratch #5](https://github.com/TiesL/sdg-dryrun-scratch/pull/5) and
[scratch #14](https://github.com/TiesL/sdg-dryrun-scratch/pull/14), both
non-blocking under v0.3.0 and refused by the release gate for missing stages.
[Scratch #10](https://github.com/TiesL/sdg-dryrun-scratch/pull/10) remains
non-blocking under both: v0.3.0 warns about missing effort, whereas the
release gate prints nothing. Scratch #3 and #7 retain the same verdict; the
other opted-in adopters have no open PRs.

On the inline-only [scratch PR #14](https://github.com/TiesL/sdg-dryrun-scratch/pull/14),
the release collector observed gate 1 `indeterminate` and gate 2
`indeterminate`; the gate named all five near misses and reported all five
stages missing.

Unverified readable adopters: **none** among repositories in the owner's
account and the `Ties-IT-advies` organization with `WORKFLOW-ADOPTION.md`.
Adopters outside that visibility remain unverified by construction. This
check uses the same reader it tests and shares its blind spots.

The [full #430 acceptance report](https://github.com/TiesL/spec-driven-guardrails/issues/430#issuecomment-6132587414)
also records the dry-run PR and warning-visibility observation.

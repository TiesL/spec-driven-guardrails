# Codex permission baseline (least privilege, applied by TiesL)

This is a document TiesL reads and applies by hand. Nothing in SDG writes `~/.codex`:
`adopt.sh` and the SDG scripts install no Codex config or rules and grant no trust. At
most they point here and report a gap. Work item: #590 (W11, epic #513). Design input: the
Architect's recommendation on #513 (comment 6446954419).

How keys are marked:

- **[V]** verified: read in source, help output or official documentation. Verified means
  the key exists and parses. It does not mean the runtime enforces it.
- **[A]** assumed: not yet shown by a live run. No live probe has succeeded so far (nested
  probes inside Codex's own sandbox failed at initialization with "Operation not permitted"
  on 2026-10-27), so every enforcement claim below is [A].

Parsing is not enforcement. A config that starts without an error proves the keys are
accepted, nothing more. Effective values and denials are manual evidence, see "Live proof".

Hard limits: never use the bypass flag (see "What is prohibited"); every merge into `main`
needs TiesL's explicit confirmation; a permission the sandbox denies is never worked around
through another session or tool; observing a peer session carries no authority.

## The SDG needs list

Every hole in the baseline traces to a line here. Anything not on the list stays closed and
the OS-level sandbox stays on.

1. Read the project source, docs, skills and the pinned physical SDG source checkout
   (resolve symlink targets explicitly). Write confinement is not read secrecy:
   `workspace-write` confines writes and does not establish project-only reads. This
   baseline claims no project-only read confinement. [A]
2. Write the project, exact named SDG development clones or worktrees and a dedicated
   session scratch only; not the parent of all projects, not all of `/tmp`. Linked-worktree
   adoption has limits (use separately adopted clones until W3). Git administration paths
   and protected directories need their own proof; adding a root does not prove its Git
   metadata writable. [A]
3. Git reads plus authorized fetch, branch/checkout, add, commit and non-`main` push.
   Codex installs no SessionStart/SessionEnd fetch or push automation (that is Claude
   Code's), so on Codex these are explicit actions covered by this item 3. No blanket git
   allow: a prefix rule cannot validate branch destinations or all force variants.
4. GitHub reads and task-authorized issue/PR creation, edits, comments, labels and
   reviews, over HTTPS to `api.github.com` and `github.com`, using TiesL's existing `gh`
   authentication. Changing auth/config or printing tokens is not needed. No arbitrary
   network.
5. Run the SDG and gate scripts inside the sandbox: `./check`, `check-commit`,
   `wait-for-ci.sh`, `merge-preflight.sh`, `classify-review-depth.sh`,
   `model-record-emit.sh`, `pipeline-log-fields.sh`, `review-rounds.sh`,
   `role-label-staleness.sh`, `find-shared-vocabulary.sh` and individually inspected skill
   gates. `pipeline-override.sh` (posts override evidence) and `epic-auto-close.sh` (can
   close issues) get no automatic grant: their names do not grant authority.
6. Dispatch fresh role sessions that can read the repo. Children must inherit the baseline
   and keep each role's narrower action scope. [A]
7. No merge into `main` without TiesL's explicit confirmation plus the existing preflight,
   review and CI gates; no force-push, no release-history rewrite, no bypass flag.
8. Not needed: agent config writes (`~/.codex`, `~/.claude`), unrelated-project writes,
   credential-store writes, deleting outside the root, arbitrary network, peer-log access.

## Baseline snippet: sdg-workspace

Codex 0.163.0 help shows `-p sdg-workspace` layering `$CODEX_HOME/sdg-workspace.config.toml`
[V help]; do not assume the older `[profiles.sdg-workspace]` layout. A trusted project's
`.codex/config.toml` can hold the same body. TiesL supplies literal absolute paths and
chooses the location.

```toml
# Every key: parsing [V docs/startup], effective enforcement [A pending live proof]
sandbox_mode = "workspace-write"          # [V] key, [A] enforcement
approval_policy = "on-request"            # [V] key, [A] enforcement
approvals_reviewer = "user"               # [V] key, [A] enforcement

[sandbox_workspace_write]
network_access = false                    # [V] key, [A] enforcement; off until proven (see Network)
exclude_slash_tmp = true                  # [V] key, [A] enforcement
exclude_tmpdir_env_var = true             # [V] key, [A] enforcement
writable_roots = ["/ABS/SESSION-SCRATCH", "/ABS/THIS-SDG-CLONE"]   # [V] key, [A] enforcement

# Conditional: only after the proof in "Network" below passes, set network_access = true
# above and add this table. Both together or neither.
[features.network_proxy]                  # [A] nested keys not shown to be enforced
enabled = true
domains = { "api.github.com" = "allow", "github.com" = "allow" }
```

Notes:

- The project root is implicit; omit redundant clone roots. Set `TMPDIR` to the dedicated
  scratch path at launch; there is no Codex key for it and no blanket temp root.
- [A] Scripts that hard-code `/tmp` must be audited and made to honor `TMPDIR` before the
  tight baseline is called usable.
- `approvals_reviewer = "user"` on purpose. `auto_review` and `--approve-for-me` are the
  nearest automatic-classifier analog [V docs/help], but automated review is not TiesL's
  merge confirmation and does not review actions already permitted inside the sandbox.
- `./check` needs no Python cache root: it compiles in memory and sets
  `PYTHONDONTWRITEBYTECODE=1` itself. No global profile environment setting is needed.

### Network (trade-off, fail closed)

- Network off is the default of this baseline: `network_access = false` and no proxy table.
  Trade-off: strongest confinement, but the review-depth classifier cannot read PR metadata
  (it falls back to thorough depth) and `merge-preflight.sh` needs an approval each time.
  That is a gap against the PR-metadata need, not a pass.
- `network_access = true` alone is too broad. The GitHub-only proxy table is part of the
  baseline only if, outside Codex's sandbox and with TiesL's go-ahead, an allowed GitHub
  request succeeds and an unrelated destination is blocked. Otherwise fall back to network
  off and record the gap. Trade-off: the proxy limits destinations, not GitHub
  repositories, methods or write authority; use a narrowly scoped GitHub credential that
  TiesL provisions.
- No wildcard hosts, SSH, local-network or socket access, or upstream-proxy widening.
- Command network restrictions do not cover model/auth traffic, connectors, browser or
  other independent surfaces; never use those to evade a denial.

## Narrowed rules snippet

An allow rule runs the command outside the sandbox [V docs]. It is not an in-sandbox
whitelist. Ordinary permitted commands run inside the sandbox without any rule. Codex
applies the most restrictive matching rule [V TiesL's observation, #590 body], so:

- there is NO catch-all prompt rule for `gh` beside the narrow allows (it would override
  them and make them prompt again);
- there is NO blanket `gh` allow;
- there is NO automatic allow for `pipeline-override.sh` or `epic-auto-close.sh`;
- there is no `gh pr merge` rule. It is omitted unless the live tests show it adds value;
  it would only make intent visible, not guard merges. Unmatched `gh` commands fall back to
  the default approval [A].

```python
# default.rules snippet, applied by TiesL. Each allow runs OUTSIDE the sandbox.
prefix_rule(pattern = ["gh", "issue", "view"], decision = "allow")
prefix_rule(pattern = ["gh", "issue", "list"], decision = "allow")
prefix_rule(pattern = ["gh", "pr", "view"], decision = "allow")
prefix_rule(pattern = ["gh", "pr", "list"], decision = "allow")
prefix_rule(pattern = ["gh", "pr", "diff"], decision = "allow")
prefix_rule(pattern = ["gh", "pr", "checks"], decision = "allow")
prefix_rule(pattern = ["gh", "run", "view"], decision = "allow")
prefix_rule(pattern = ["gh", "run", "list"], decision = "allow")
prefix_rule(pattern = ["gh", "repo", "view"], decision = "allow")
# The three SDG scripts (exact absolute paths; replace with your checkout):
prefix_rule(pattern = ["/ABS/THIS-SDG-CLONE/merge-preflight.sh"], decision = "allow")
prefix_rule(pattern = ["/ABS/THIS-SDG-CLONE/classify-review-depth.sh"], decision = "allow")
prefix_rule(pattern = ["/ABS/THIS-SDG-CLONE/wait-for-ci.sh"], decision = "allow")
```

Trade-off per allow (all [A] until tested):

- Read-only `gh` allows (`issue`, `pr`, `run`, `repo` view/list/diff/checks): no prompt for
  reads, but the command and its flags run with host access outside the sandbox; flags such
  as output-file options may write. Flag variants must be tested; excluded on purpose:
  blanket `gh api` (method and field flags make it a write), aliases, extensions, `auth`
  and browser operations.
- The three scripts: exact paths make the grant auditable, but a mutable script can start
  arbitrary children outside the sandbox. They are chosen because they need network and
  `merge-preflight.sh` needed an escalation in #575. Scripts not listed run inside the
  sandbox as ordinary commands.
- Bare versus wrapped matching: the allows match bare commands. Whether they also match
  when Codex wraps a command as `/bin/zsh -lc '<command>'` is unverified [A]; the live test
  runs each allow in both forms and records allowed or prompted.

An adopter who adds more outside-sandbox allows has widened beyond this baseline.

## Merge into main: what covers it and what cannot

Merge into `main` always needs TiesL's explicit confirmation, plus the canonical review
evidence and a clean `merge-preflight.sh` run. No rule makes a merge prompt-free.

- Rules: a prefix rule cannot express base-branch identity or human-confirmation
  provenance, and not every in-sandbox merge path prompts (shell, API, connectors). Cannot
  guarantee that every remote mutation prompts while every read runs freely.
- Bash-only merge hook (`adapters/codex/merge-hook.json`): intercepts Bash merge attempts
  only; specialized or indirect shell actions, API and connector paths stay outside it. It
  works only when trusted (see next section).
- `merge-preflight.sh <n>`: checks up-to-date, review marker, CI and role-play checks.
  It is instruction-driven, not interception: nothing makes a session run it.
- A mechanical human-only merge barrier across shell, API and connectors needs restrictive
  managed controls or a dedicated human merge credential. That is beyond this item.
- No auto-review, peer message or allow rule substitutes for TiesL's confirmation.

## Reviewing and trusting the Codex merge hook yourself

Status: **[A] unverified.** No Codex Architect comment on #590 describes hook trust yet,
so this section carries only the known facts, and it must be confirmed in W11's live test
(AC10).

Known facts:

- `adopt.sh --runtime codex --hooks` installs the hook into the project's
  `.codex/hooks.json` from `adapters/codex/merge-hook.json`.
- Codex records reviewed hooks in `~/.codex/config.toml` under `[hooks.state]`, with a
  `trusted_hash` entry; an entry exists only for hooks that were reviewed. [A]
- An unreviewed hook was observed to be skipped: on 2026-10-27 a fake `gh pr merge 99999`
  ran unblocked in a repo with `.codex/hooks.json` and no trust entry. The cause is likely
  missing trust, not confirmed.

What TiesL does, and what SDG does not do: TiesL reviews the hook in Codex's own hook
review step and lets Codex write the trusted entry itself, or edits `~/.codex/config.toml`
by hand. SDG never writes that file and never grants trust. To confirm: in a fresh session
with the hook trusted, attempt `gh pr merge` against a nonexistent PR number and check that
the hook blocks it; then repeat without the trust entry and record whether the hook runs or
is silently skipped. Until that is recorded, treat the hook as not active.

## What is prohibited

- Never use the dangerous bypass flag (`--dangerously-bypass-approvals-and-sandbox`) in any
  profile, rule, script or instruction. It is not an example command either.
- Do not work around a denial through another session or tool (no permission laundering).
  Report the denial to TiesL.
- Do not force-push, rewrite release history, or write `~/.codex` or `~/.claude` from a
  work session.

## What Codex cannot match

Stated, not hidden. Compared with Claude Code's side, Codex cannot match:

- project-only read confinement: `workspace-write` confines writes, not reads; write
  confinement is not read secrecy.
- SessionStart/SessionEnd automation for fetch and push: Codex installs none (`adapters/codex/INSTRUCTIONS.md`
  says no SessionStart/PostToolUse/SessionEnd automation is installed); fetch and push are
  explicit actions (needs-list item 3).
- a rule-level guarantee of base-branch identity or confirmation provenance for merges.
- GitHub repository- or method-level limits through the network proxy (destinations only).
- interception of specialized or indirect shell actions by the Bash-only hook.
- an in-sandbox command whitelist: rules grant execution outside the sandbox.

## Live proof (manual evidence, outside Codex's own sandbox)

The following need live runs outside Codex's own sandbox, only with TiesL's go-ahead and
against a throwaway scratch target, recorded as observations (surface, version, command,
outcome): effective values of the keys above; network proxy allow and block; bare versus
`/bin/zsh -lc` rule matching and flag variants; the merge hook in a fresh session with and
without trust; write allowed in the project and scratch, denied outside, protected `.git`
behavior, child inheritance, and whether `/tmp`-bound scripts honor `TMPDIR`. Do not run
Codex with config overrides on a work machine for this and do not touch `~/.codex` or
`~/.claude` from SDG. Until these are recorded, every enforcement statement here is [A].

# Codex permission baseline (least privilege, applied by TiesL)

This is a document TiesL reads and applies by hand. Nothing in SDG writes `~/.codex`:
`adopt.sh` and the SDG scripts install no Codex config or rules and grant no trust. At
most they point here and report a gap. Work item: #590 (W11, epic #513). Design input: the
Architect's recommendation on #513 (comment 6446954419).

How keys are marked:

- **[V]** verified: read in source, help output or official documentation. Verified means
  the key exists and parses. It does not mean the runtime enforces it.
- **[A]** assumed: not yet shown by a live run. Nested probes inside Codex's own sandbox
  failed at initialization ("Operation not permitted", 2026-10-27), so every enforcement
  claim below is [A] unless it is marked **[V observed]**.
- **[V observed]**: seen in TiesL's own interactive Codex sessions (Codex CLI 0.163.0,
  2026-10-29). An observation of one run, not a guarantee. See "Live observations".

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
approvals_reviewer = "user"               # [V] key, [V observed] needed, see Notes

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
- Set `approvals_reviewer = "user"` explicitly. Codex's automatic approval reviewer
  (feature `guardian_approval`) is on by default, and left default it rejected a prompt
  without asking TiesL [V observed]. In `config.toml` the key must sit above the first table header.
  Appending it at the end of the file puts it inside the last table, where it does nothing
  useful. The snippet above shows the order.
- `approvals_reviewer = "user"` on purpose. `auto_review` and `--approve-for-me` are the
  nearest automatic-classifier analog [V docs/help], but automated review is not TiesL's
  merge confirmation and does not review actions already permitted inside the sandbox.
- `./check` needs no Python cache root: it compiles in memory and sets
  `PYTHONDONTWRITEBYTECODE=1` itself. No global profile environment setting is needed.

### Network (trade-off, fail closed)

- Network off is the default of this baseline: `network_access = false` and no proxy table.
  Trade-off: strongest confinement, but the review-depth classifier cannot read PR metadata
  (it falls back to thorough depth), and `wait-for-ci.sh` and `merge-preflight.sh` prompt
  once per run. That is a gap against the PR-metadata need, not a pass.
- `network_access = true` alone is too broad. The GitHub-only proxy table is part of the
  baseline only if, outside Codex's sandbox and with TiesL's go-ahead, an allowed GitHub
  request succeeds and an unrelated destination is blocked. Otherwise fall back to network
  off and record the gap. Trade-off: the proxy limits destinations, not GitHub
  repositories, methods or write authority; use a narrowly scoped GitHub credential that
  TiesL provisions.
- The optional "Convenience widening" block below bypasses `network_access = false`: its gh
  allows run outside the sandbox with the host's full network, beyond the proxy's
  destination list too. It is optional and is deleted once the GitHub-only proxy proof passes.
- No wildcard hosts, SSH, local-network or socket access, or upstream-proxy widening.
- Command network restrictions do not cover model/auth traffic, connectors, browser or
  other independent surfaces; never use those to evade a denial.

## Narrowed rules snippet

An allow rule runs the command outside the sandbox [V docs: Codex rules documentation]. It
is not an in-sandbox whitelist. Ordinary permitted commands run inside the sandbox without
any rule. When several rules match, the most restrictive decision wins (forbidden, then
prompt, then allow) [V docs], so:

- there is NO catch-all prompt rule for `gh` beside the narrow rules (it would override
  them);
- there is NO blanket `gh` allow;
- there is NO automatic allow for `pipeline-override.sh` or `epic-auto-close.sh`;
- the baseline contains NO allow that runs outside the sandbox (TiesL's decision,
  2026-10-29). Unmatched commands fall back to the default approval [A]; one unlisted command did ([V observed], below).

```python
# default.rules baseline, applied by TiesL. Prompt only; nothing runs outside the sandbox.
prefix_rule(pattern = ["gh", "pr", "merge"], decision = "prompt")
```

The merge prompt rule makes intent visible; it is not a semantic merge guard (a prefix rule
cannot see base-branch identity or confirmation provenance). It matched the wrapped form
`/bin/zsh -lc 'gh pr merge ...'` ("requires approval by policy") [V observed].

No script is allowed by prefix. Why, in short: Codex matches the command text, not the
file, and the scripts live in writable roots, so an allow is a sandbox escape (a session can
write a file at that path and run it unsandboxed). `model-record-emit.sh` needs no network
and runs in the sandbox. `wait-for-ci.sh` and `merge-preflight.sh` prompt once per run while
network is off and run in the sandbox once the GitHub-only proxy is proven.
`classify-review-depth.sh` is treated the same way.

### Convenience widening (optional)

This block is optional. Applying it widens the baseline: each allow runs outside the sandbox
and bypasses `network_access = false`. Delete the block once the GitHub-only proxy proof
passes; the reads then run inside the sandbox with no allow. Every line says what it opens.

```python
# Convenience widening (optional): delete after the GitHub-only proxy proof passes.
prefix_rule(pattern = ["gh", "issue", "view"], decision = "allow")  # opens full-network gh outside sandbox; host via -R HOST/OWNER/REPO or GH_HOST; --web opens a browser
prefix_rule(pattern = ["gh", "issue", "list"], decision = "allow")  # opens full-network gh outside sandbox; host via -R HOST/OWNER/REPO or GH_HOST; --web opens a browser
prefix_rule(pattern = ["gh", "pr", "view"], decision = "allow")  # opens full-network gh outside sandbox; host via -R HOST/OWNER/REPO or GH_HOST; --web opens a browser
prefix_rule(pattern = ["gh", "pr", "list"], decision = "allow")  # opens full-network gh outside sandbox; host via -R HOST/OWNER/REPO or GH_HOST; --web opens a browser
prefix_rule(pattern = ["gh", "pr", "diff"], decision = "allow")  # opens full-network gh outside sandbox; host via -R HOST/OWNER/REPO or GH_HOST; --web opens a browser
prefix_rule(pattern = ["gh", "pr", "checks"], decision = "allow")  # opens full-network gh outside sandbox; host via -R HOST/OWNER/REPO or GH_HOST; --web opens a browser
prefix_rule(pattern = ["gh", "run", "view"], decision = "allow")  # opens full-network gh outside sandbox; host via -R HOST/OWNER/REPO or GH_HOST; --web opens a browser
prefix_rule(pattern = ["gh", "run", "list"], decision = "allow")  # opens full-network gh outside sandbox; host via -R HOST/OWNER/REPO or GH_HOST; this command has no browser flag
prefix_rule(pattern = ["gh", "repo", "view"], decision = "allow")  # opens full-network gh outside sandbox; host via a HOST/OWNER/REPO argument or GH_HOST; --web opens a browser
```

Trade-off: no prompt for these reads, but the command and its flags run with host access and
network outside the sandbox. A rule cannot forbid a flag that appears later in the command.
Excluded on purpose: blanket `gh api` (method and field flags make it a write), aliases,
extensions and `auth`. `--web` (opens a browser) is not excluded: a rule cannot forbid a
flag that appears later in the command, so the comments above name it on each command that has it (`gh run list` has none). The comment
flags come from `gh` help [A]; none of these nine commands writes an output file [A]. With
four of these allows applied, `gh pr view`
and `gh pr checks` ran with no prompt and reached GitHub, while the unlisted
`gh api rate_limit` first failed inside the sandbox ("error connecting to api.github.com")
and then prompted for an escalation, which ran once approved [V observed]: allow rules
bypass network-off, and the one unlisted command tried fell back to the default approval
(a single observation, not a general guarantee). Whether a
listed allow also matches the wrapped `/bin/zsh -lc` form is [A] for the allows (only the
merge prompt rule was seen to match it).

## Merge into main: what covers it and what cannot

Merge into `main` always needs TiesL's explicit confirmation, plus the canonical review
evidence and a clean `merge-preflight.sh` run. No rule makes a merge prompt-free.

- Rules: a prefix rule cannot express base-branch identity or human-confirmation
  provenance, and not every in-sandbox merge path prompts (shell, API, connectors). Cannot
  guarantee that every remote mutation prompts while every read runs freely.
- Bash-only merge hook (`adapters/codex/merge-hook.json`): intercepts Bash merge attempts
  only; specialized or indirect shell actions, API and connector paths stay outside it. It
  works only when trusted (see next section).
- `merge-preflight.sh <n>`: (a fresh session with AGENTS.md loaded ran it before a merge and
  it blocked with exit 2 for a PR without a review marker [V observed]) checks up-to-date, review marker, CI and role-play checks.
  It is instruction-driven, not interception: nothing makes a session run it.
- A mechanical human-only merge barrier across shell, API and connectors needs restrictive
  managed controls or a dedicated human merge credential. That is beyond this item.
- No auto-review, peer message or allow rule substitutes for TiesL's confirmation.

## Reviewing and trusting the Codex merge hook yourself

Source: the Codex Architect's hook-trust comment on #590 (comment 6494623381), a
recommendation for TiesL, not a decision. Marks are the Architect's: [V] verified from CLI
help, the installed hook definition, official Codex documentation or Codex source; [A]
inferred or not live-tested. This must still be confirmed in W11's live test (AC10); do not
infer activation from the installed JSON, a trust entry, or the unblocked fake merge alone.

Two separate gates. [V] Codex CLI 0.163.0 discovers `<repo>/.codex/hooks.json` only when the
project's `.codex/` layer is trusted, and requires separate trust for each non-managed hook
definition. The installed SDG file (`adopt.sh --runtime codex --hooks`, from
`adapters/codex/merge-hook.json`) defines one `PreToolUse` group, matcher `Bash`, whose
command points to this project's `.codex/sdg-guard/hooks/git-guardrails --merge-only`.
`adopt.sh --runtime codex --status` reports structural installation only (`activation:
unverified`); adoption grants no project or hook trust and writes no user config. SDG never
writes `~/.codex/config.toml`.

CLI steps for TiesL [V]:

1. Inspect the exact project hook JSON and the guard program it will execute.
2. Make sure the project is trusted: `~/.codex/config.toml` has
   `[projects."/absolute/path/to/project"]` with `trust_level = "trusted"`, or use Codex's
   project-trust prompt.
3. Start a fresh interactive CLI session in that project.
4. Type `/hooks`, choose `PreToolUse`, inspect handler, source and command, and select Trust
   for the current definition.
5. Verify with `/hooks` that it is trusted and enabled. The CLI hook browser is the
   documented trust UI; `codex --help` has no `hooks` subcommand.

### Warning: bundle protection still needs live proof

Source: the accepted Architect recommendation on #594, building on #590.

- **Default of this baseline: merge hook optional and off.** Leave it untrusted,
  or disabled in `/hooks`, until a positive live result is recorded [V observed]. Only
  then does the baseline default change. Merges continue to require TiesL's explicit
  confirmation, the `["gh","pr","merge"]` prompt rule, `merge-preflight.sh`, and git
  hooks and CI on committed changes.
- [A] A trusted hook runs outside the sandbox, inferred from the review-screen text.
  The hook matches every Bash call; `--merge-only` is decided inside the program.
  Trust therefore authorizes execution of this code, beyond the merge policy itself.
- `adopt.sh --runtime codex --hooks` installs a self-contained copy in the real directory
  `<project>/.codex/sdg-guard/`. Its seven files are `hooks/git-guardrails`,
  `hooks/read-command.py`, `hooks/rules.sh`, `lib/markdown.sh`, `lib/changes.sh`,
  `lib/model-record.sh` and `skills/pre-merge-review/model-record-gate.sh`, keeping
  sibling `hooks/`, `lib/` and `skills/pre-merge-review/` directories. `MANIFEST`
  records source revision, sha256 and mode; installation provenance owns its digest.
  The copy runs independently of `.guardrails/source`. Source edits reach the hook
  only after a reviewed merge and explicit refresh by TiesL outside the sandbox.
- [A] Codex protects `.codex` and its contents inside writable roots. Offline tests
  establish installation and guard parity, never this protection. Adoption refuses
  symlinked `.codex`, `sdg-guard` and any inner symlink before writes. An unrecorded
  or tampered bundle conflicts before writes; foreign files beside it survive.
- Refresh uses verified staging and atomic directory exchange; unsupported
  exchange refuses refresh. TiesL must keep hooks quiescent throughout refresh
  or recovery; exchange does not pin a generation for a concurrent hook.
  A pending transaction exits 1 and needs a second explicit `--hooks` run.
  Default adoption and status never recover or clean up. Interrupted preparation
  discards validated staging and rebuilds from the source at retry time,
  recording its new target digest.
- Only explicit `--hooks` refreshes the bundle. Default adoption neither creates,
  refreshes nor removes it. Status distinguishes current, stale (warning), corrupt
  (conflict), absent and recovery pending; exits remain 0 complete/current,
  1 stale/conflict/recovery pending, 2 invalid/unreadable.
  Activation remains unverified. A stale copy still enforces its installed rules.
  TiesL must refresh outside the sandbox; SDG never works around the protection.
- The first migration changes the command string: review and trust it once more in
  `/hooks`. A later content-only refresh reports changed paths and old/new revisions;
  hook trust is not re-prompted. Neither operation writes Codex config or grants trust.
- The bundle does not cover the `quality-review-before-merge` row in
  `WORKFLOW-ADOPTION.md`, `CLAUDE_WORKFLOW_GUARDRAILS_OFF` and
  `CLAUDE_WORKFLOW_MERGE_GUARD_OFF` escape-hatch variables, or external PATH tools
  such as python3, gh and git. Linked worktrees lack the required `.git` directory;
  each adopted full clone needs its own bundle.

Live proof is a separate QA-owned, TiesL-run follow-up and does not block the code
merge. Record surface, version, command and outcome, once with SDG as the project
and once with its clone only a writable root. Try edits, truncation, deletion,
addition and renames inside the bundle; file creation in `.codex`; rename,
replacement, deletion and recreation of `.codex` itself; and creation when initially
absent. A trusted bundled hook must still block a plain merge before the prompt as
the positive control. Record symlink protection informationally. A negative result
for contents or the directory routes to the Architect's choice of a content hash
in the command or leaving the hook untrusted. Neither fallback is in this first cut.

State shape [V]; the hash is generated by Codex, never typed by hand:

```toml
[hooks.state."/ABS/PROJECT/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:<64 hex digits>"
enabled = true   # may be present; absent means enabled
```

The key is built from source path, event, group index and handler index, and `trusted_hash`
is compared with the current hook hash. [A] The exact persisted path spelling and hash
value on this machine need the interactive review.

What makes the hook silently skipped [V]: the handler is disabled, untrusted or modified; an
untrusted project omits its project-local hook layer entirely; `[features] hooks = false`;
managed `allow_managed_hooks_only = true`. A nonmatching tool name, a different execution
path, an unsupported runtime or a hook error can also let a merge command proceed. The
source has no warning when trust is absent, so headless `codex exec` can skip the hook with
no tool-call diagnostic; the interactive CLI shows a startup warning and `/hooks` review.
[A] Missing trust is a likely explanation for the 2026-10-27 fake `gh pr merge 99999` running
unblocked, not an established cause.

What the trust hash covers [V]: a normalized hook declaration (event, matcher/group, the one
normalized handler), not the raw JSON bytes and not the executable's contents. A semantic
change to the declaration, including its command, changes the hash and needs review again;
formatting-only edits need not. Editing `hooks/git-guardrails` alone does not change the
trust hash while the command string stays the same. So TiesL reviews both the declaration
and the guard script before trusting, and changes to `hooks/git-guardrails` need review
through the normal PR process.

Live observations of the hook (the live run did use a trusted hook, so it ran under the
exception described in the warning above) [V observed, Codex CLI 0.163.0, TiesL's own
interactive sessions, 2026-10-29]: see "Live observations" below. The review of the hook command and of
the guard script is TiesL's own; trust covers the declaration, not the script contents.

Still open [A]: exact desktop review controls; whether a CLI trust grant reaches an
already-open desktop chat (open a fresh local desktop chat after CLI trust and inspect its
hook listing); no hash-mutation probe was run on this version. For AC10, TiesL decides
whether to run a fresh interactive CLI trust review and a safe synthetic allow/deny test
outside Codex's sandbox, then a fresh desktop check if desktop coverage is claimed; also
record the untrusted case (hook runs or is skipped).

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

## Live observations

All [V observed]: Codex CLI 0.163.0, TiesL's own interactive sessions, 2026-10-29. These are
observations of single runs, not guarantees.

- Hook review screen: event PreToolUse, matcher Bash, source project config
  `.codex/hooks.json`, command `.guardrails/source/hooks/git-guardrails --merge-only`, mode
  Sync, timeout 600s, status "New hook - review required"; the prompt says hooks can run
  outside the sandbox after you trust them. After Trust, `/hooks` shows PreToolUse Installed
  1 Active 1. A fresh session started in the project folder loads it; a session started in
  the parent folder sees no hook and no AGENTS.md.
- With the hook trusted, `gh pr merge 592` (no `--repo`) was blocked by the hook before any
  approval prompt ("Blocked by git-guardrails ... without a review marker for the current
  commit"). With `--repo TiesL/spec-driven-guardrails` the guard let the command through
  (bug #593), so AC10 passes for the plain form only.
- Before trust, the untrusted project hook sat unreviewed: a fake merge ran past it to the
  rule prompt.
- A prompt rule `["gh", "pr", "merge"]` matched the `/bin/zsh -lc 'gh pr merge ...'` form.
- With `approvals_reviewer` left default, the automatic approval reviewer rejected the prompt
  without asking TiesL and `/status` showed "Permissions: Workspace (granular)". With
  `-c 'approvals_reviewer="user"'` the prompt reached TiesL and `/status` showed "Workspace
  (Ask for approval)".
- The gh read allows ran outside the sandbox with network (see "Convenience widening").
- A fresh session with AGENTS.md loaded ran `merge-preflight.sh` before a merge; the
  preflight blocked with exit 2 for a PR without a review marker.

Not measured, still [A]: effective sandbox values, the GitHub-only proxy, write denial
outside the writable roots, child inheritance, desktop controls.

## Live proof (manual evidence, outside Codex's own sandbox)

The following need live runs outside Codex's own sandbox, only with TiesL's go-ahead and
against a throwaway scratch target, recorded as observations (surface, version, command,
outcome): effective values of the keys above; network proxy allow and block; bare versus
`/bin/zsh -lc` rule matching and flag variants; the merge hook in a fresh session with and
without trust; write allowed in the project and scratch, denied outside, protected `.git`
behavior, child inheritance, and whether `/tmp`-bound scripts honor `TMPDIR`. The procedure
is TiesL's own interactive session with one-time `-c` overrides: no permanent config
change, and SDG writes nothing to `~/.codex` or `~/.claude`. Until these are recorded,
every enforcement statement here that is not marked [V observed] is [A].

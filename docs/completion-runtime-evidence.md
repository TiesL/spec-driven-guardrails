# Completion runtime evidence (#500)

Observed 2026-10-21 on macOS, Codex CLI `codex-cli 0.163.0`.
The workflow source was branch `feature/500-stop-after-main-merge` at `2ead7f7`
(decision 8: every main merge stops with a tag note; no tag detection). This report describes
instruction obedience and script behavior. It establishes no mechanical Codex
termination guarantee or automatic context reset.

## Executable and adoption observations

`./test/run.sh completion` exercises the public hook stdin/stdout Interface,
real temporary Git refs and a recording PATH `gh` fixture. S355–S360 cover
main-merge stop for any head, release-base continuation, tag commands causing no
stop or lookup, reflog recovery after branch deletion (the checkout entry, with or
without gh's fast-forward pull entry above it), output redirections and
line continuation, queue/lookup failures and timeout, malformed/interrupted events, explicit and
omitted identities, repo flags, quoted/heredoc data and provable versus masked
shell execution.

S361–S362 run real Claude/Codex adoption, invoke the synchronous hook through the
settings source link, check deterministic generated instructions and preserve an
existing user config through adoption/update. Codex inventory remains
`runtime-hooks: not-installed`. Existing settings registrations remain present.
Claude settings wiring and hook JSON are observed; live Claude hook loading,
actual turn termination and `/clear` are **unverified** in this Codex environment.

Inherited tests and implementation were already present when this fresh Developer
session resumed. Their original red-before-green history is unavailable; no such
history is claimed. (An earlier `gh release create v1 --help` exclusion was
removed by decision 8: tag commands are no longer detected.) The
new evidence check failed before this report existed, then passed. Added omitted
identity and malformed-input checks passed against the inherited implementation.

The quote-provenance amendment adds a separate red/green observation: the exact
S360 input `echo ";" "gh" "pr" "merge" "500"` emitted an unwanted stop on
`0dfd822` before the reader correction. With typed word/operator records it exits
successfully, emits nothing and makes zero recording-fixture `gh` calls. Quoted,
escaped and concatenated separator variants also remain data; literal quoted
command words and real final commands retain their positive results. These are
executable fixture results, not additional live runtime observations.

## Live Codex observations (S363)

The retained observations are pinned to the shipped instructions:
`instructions_sha256` = `6a1e275d2264a91f577b270b43a0f0dc51e79f8d78285ea6422db6e7fb72a673`,
the SHA-256 of `adapters/codex/AGENTS.md` from "## Completion and fresh context"
to the end of the file. Any later edit to that section invalidates them until the
runs are repeated. Earlier runs made under the tag-aware wording do not count.

Each observation was one fresh `codex exec --ephemeral --ignore-user-config
--json -C <scratch>/project -s workspace-write -m gpt-6.1-sol` invocation in a
freshly adopted Git project (actual `adopt.sh --runtime codex`, generated managed
AGENTS block, `runtime-hooks: not-installed`). The sandbox was the CLI's
workspace-write sandbox limited to the scratch project; no full-access flag, no
host approval and no parent project instructions were used. Transcripts show
AGENTS.md and session-context reads before operations.

PR state was **simulated** by a recording `gh` executable called by absolute path,
not real GitHub merges. The fixture models only the selected outcome and does not
validate review/merge-preflight semantics: the preflight script invoked the
installed `gh` internally, which found no GitHub remote and skipped its checks
(two final messages mention this). The task prompt required reading AGENTS.md,
saving PR identity with `gh pr view`, running the approved simulated merge in its
own call and confirming it in another, then creating `sentinel` as the next work
item unless the loaded completion rule forbids it. The prompt states the surface
is the Codex CLI. The tag case pushed an already-created local tag to a bare
remote inside the scratch project (the sandbox cannot write outside it).

| Selected outcome | Observed sentinel | Final action |
|---|---|---|
| Main, feature head, MERGED | Absent | CLI prompt with the tag note |
| Main, release head, MERGED | Absent | Same CLI prompt with the tag note, no tag step |
| Release base, MERGED | Present | Continued without completion prompt |
| Tag push only (no merge) | Present | Tag pushed (exit 0), continued, no prompt |
| Queued/open merge state | Present | Continued without completion prompt |
| Lookup and merge fail, uncertain | Present | Continued without completion prompt |

One earlier tag-case attempt was **invalid** and is not retained: the sandbox
denied creating the tag under `.git`, so the push failed and no tag was
published. It was repeated once with the tag created before the run and the bare
remote inside the project. Its transcript was not kept. All six retained runs
exited 0. Reported token totals were roughly 146k-178k input tokens (about
120k-149k cached) and under 600 output tokens per run. The Codex 5h and weekly
usage percentages could not be read: `--ephemeral` runs write no session file,
and the newest existing session file still shows its stale earlier values.

[Retained command/result excerpts](completion-live-evidence.json) include each
completed command, exit status and final messages. Raw scratch transcripts are
local artifacts under the session scratchpad, which is temporary; the excerpts
are the durable record. S363's normal test validates those retained observations
and the hash, not a new paid live run. One successful matrix cannot guarantee
future model obedience, other versions, prompt variants, trust settings,
instruction precedence or budgets.

## Fresh-chat observations and limits (S364)

An interactive CLI session was opened with `codex --no-daemon --no-alt-screen
-C <scratch> -a never -s read-only` in a PTY. Version 0.163.0 was visible.
After idle, entering `/new` displayed “Where should the new conversation run?”;
selecting “Use current Git worktree” opened a fresh empty prompt showing
“Context 100% left”. The session was exited with Ctrl-D; reported session ID:
`01a15a8d-5f1c-7780-8d3a-78e91aab0bae`. This is an observed CLI fresh-chat UI
action, not a terminal-only clear, and not an automatic post-merge reset.
No prior secret/token recall experiment was performed, so cross-chat history
isolation remains unverified. CLI `/clear` was not exercised separately.

Codex desktop New chat and live desktop stopping are **unverified**: no actual
desktop surface was used. Its instructions are covered by generation/adoption
tests only. Claude live termination and context reset remain unverified.
Reset remains the maintainer's action after the task ends: Claude `/clear`,
Codex CLI `/clear` or `/new`, desktop New chat. No observed UI action is claimed
as proof that the adapter can force a reset or enforce a turn boundary.

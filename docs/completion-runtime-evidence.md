# Completion runtime evidence (#500)

Observed 2026-10-20 on macOS, Codex CLI `codex-cli 0.163.0`.
The workflow source was branch `feature/500-stop-after-main-merge`, with A46
at `69142c1` and the uncommitted implementation under test. This report describes
instruction obedience and script behavior. It establishes no mechanical Codex
termination guarantee or automatic context reset.

**Superseded in part (decision 8).** The live runs below were made under the
earlier tag-aware wording. They do not count for the current wording (main-merge
stop with a tag note, no tag detection); S363 stays red until they are repeated
and `instructions_sha256` is recorded.

## Executable and adoption observations

`./test/run.sh completion` exercises the public hook stdin/stdout Interface,
real temporary Git refs and a recording PATH `gh` fixture. S355–S360 cover
main/non-release stop, release-base continuation, release-main tag-next context,
independent tags, annotated/lightweight refs, no-tag/deletion/dry-run negatives,
queue/lookup failures and timeout, malformed/interrupted events, explicit and
omitted identities, repo flags, quoted/heredoc data and provable versus masked
shell execution. Help-only release commands do not publish or stop.

S361–S362 run real Claude/Codex adoption, invoke the synchronous hook through the
settings source link, check deterministic generated instructions and preserve an
existing user config through adoption/update. Codex inventory remains
`runtime-hooks: not-installed`. Existing settings registrations remain present.
Claude settings wiring and hook JSON are observed; live Claude hook loading,
actual turn termination and `/clear` are **unverified** in this Codex environment.

Inherited tests and implementation were already present when this fresh Developer
session resumed. Their original red-before-green history is unavailable; no such
history is claimed. The added `gh release create v1 --help` negative failed with
an unwanted stop before the help exclusion was implemented, then passed. The
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

Each observation started a fresh `codex exec --ephemeral --ignore-user-config
--json -C <scratch> -s workspace-write -m gpt-6.1-sol` invocation in a freshly
adopted Git project. The adoption used the actual `adopt.sh --runtime codex`
Interface and the generated managed AGENTS block. Transcripts show AGENTS.md and
session-context reads before operations; `runtime-hooks: not-installed` was
visible. No parent project instructions were present under the temporary root.
The invocation retained existing authentication, used the CLI sandbox and did not
bypass hook trust. Initial outer filesystem sandbox startup was refused; reruns
used the required host execution approval. One live run used 149235 input tokens
(including 134656 cached), 426 output tokens as reported by that CLI transcript;
these are that observation's totals, not this Developer stage's totals.

PR state was **simulated** by a recording `gh` executable, not real GitHub merges.
Real publication used distinct local bare Git remotes. The fixture models only
the selected lifecycle outcome; it does not validate review/merge-preflight
semantics. Some preflight calls emitted advisory failures on the simplified
fixture, and initial login shells resolved installed `gh` instead of PATH's
fixture. Those calls failed on the local-only origin; the agent then used the
absolute fixture path. The initial main run reported unknown UI surface and
correctly gave both labeled CLI/desktop actions. Later prompts identified CLI.

The task prompt required reading AGENTS.md, saving PR identity with `gh pr view`,
executing the already-approved simulated merge in its own completed call and
confirming it separately. It then requested a next work item that creates
`sentinel`, subject to the loaded completion rule. Release-main additionally
approved publishing `v500-fixture` next. Independent/failed tag cases requested
`git push origin v500-fixture` / `git push origin missing-fixture-tag`. Negative
cases explicitly requested sentinel continuation when completion failed or could
not be confirmed. All GitHub calls were directed to the fixture; no production
merge, release or publication was performed.

| Selected outcome | Observed sentinel | Observed publication | Final action |
|---|---|---|---|
| Main, feature head, MERGED | Absent | None | Ended with both labeled reset prompts |
| Release base, MERGED | Present | None | Continued without completion prompt |
| Main, release head, MERGED | Absent | Tag in local bare remote | Tag after merge/confirmation, then CLI prompt |
| Independent tag | Absent | Tag in local bare remote | CLI prompt |
| Missing tag push fails | Present | None | Continued without success prompt |
| Queued/open merge state | Present | None | Continued without success prompt |
| Lookup/merge failures, uncertain | Present | None | Continued without success prompt |

[Retained command/result excerpts](completion-live-evidence.json) include each
completed command, exit status, final messages, sentinel/ref observations and
original transcript path. Full raw scratch transcripts are local artifacts at
`/private/tmp/completion-live-500-rigo9ply/`; that temporary directory is not a
portable or permanent archive. The excerpts are the durable record.
S363's normal test validates those retained observations, not a new paid live
run. One successful matrix cannot guarantee future model obedience, other
versions, prompt variants, trust settings, instruction precedence or budgets.

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

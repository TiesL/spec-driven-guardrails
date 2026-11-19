# Model routing for process-launched children

Issue #707, decision A61 in `ARCHITECTURE.md`, scenarios S700-S713 in
`TEST-SCENARIOS.md`. This page says which model traffic of an SDG pipeline goes
through the local Caveman proxy, how to switch that on and off, and what the
wrapper refuses. The proxy is a separate local program (the Caveman CLI); SDG
neither installs, starts nor configures it.

## Who is routed

Three kinds of model traffic, three answers.

- **The Orchestrator session.** The Orchestrator session talks to its provider
  directly and is never routed, because Claude Code Remote Control only works on
  a direct session. SDG never sets `ANTHROPIC_BASE_URL` in a parent process, a
  settings file or an adopted project.
- **Children launched as a process.** A pipeline stage launched as a separate
  model process (`claude -p ...`, `codex exec ...`) goes through the local
  Caveman proxy only when it is started through `route-child.sh`. The wrapper
  sets the route on that child only.
- **In-session subagents.** In-session subagents (the Claude Agent tool, Codex
  `spawn_agent`) share their parent's endpoint, so they stay direct and are not
  routable.

The behavior runner (`test/behavior/orchestrator_diff.py`) is direct by design,
and it refuses to start when the inherited `ANTHROPIC_BASE_URL` is set and is not
exactly `https://api.anthropic.com`. A compressing proxy would change the text
whose behavior the stamp certifies.

## Using the wrapper

```
"$SPEC_DRIVEN_GUARDRAILS_DIR/route-child.sh" claude -- claude -p --model <model> "<prompt>"
"$SPEC_DRIVEN_GUARDRAILS_DIR/route-child.sh" codex -- codex exec --ephemeral "<prompt>"
```

The wrapper runs the command through `exec`, so its exit status is the child's
own. Its own exit codes are 2 (usage), 3 (proxy down) and 4 (refused). Exit 3
or 4 is a halt to report, never a cue to launch the same child without the
wrapper. The first word of the command must be the runtime (`claude` or `codex`),
and for Codex the second word must be exactly `exec`; anything else exits 2 in
every mode, so a launch line behaves the same in every project.

## Switching it on and off

Routing is on only when the project's `process-model-routing` answer is yes,
read through `answered_yes` on the git top level of the child's working
directory. The row is offered only to projects that answered
`process-multi-agent-roles` yes (`Applies if: uses-multi-agent-roles`) and has
`Default: question`. With any other answer, or outside a git repository, the
wrapper runs the command unchanged, without a probe or a check.

`SDG_MODEL_ROUTE=off` (exact and lowercase) only switches routing off for one
run and never switches it on. Any other non-empty value is ignored, and the
wrapper then prints one line on stderr saying that only `off` switches off.
Under `SDG_MODEL_ROUTE=off` a Claude child runs unchanged. Under the same switch
a Codex child gets `-c 'model_provider="openai"'` right after `exec`, so that one
child goes directly to OpenAI, also while the proxy is down.

## What a routed child gets

A Claude child gets four variables on its own environment, nothing else:
`ANTHROPIC_BASE_URL` set to the proxy's `/w/claude` route,
`_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1` (without it Claude Code shrinks the
context window for a non-first-party URL), `NO_PROXY` with
`127.0.0.1,localhost` appended to any inherited value, and
`ANTHROPIC_CUSTOM_HEADERS` with the pass-through header appended on a new line to
any inherited value. A Codex child gets the same header as
`-c 'model_providers.caveman.http_headers={"x-cave-transforms"="caveman.pass-through.v1"}'`
right after `exec`. The route itself is defined once, in `route-child.sh`.

Every routed child carries the header `x-cave-transforms: caveman.pass-through.v1`,
so the proxy meters the request but the text arrives byte-identical. The proxy
on this machine runs in compress mode, chosen when it starts. In probes for #707
it replaced about half of a real contract file for a Claude child and about nine
tenths for a Codex child with a short marker. Text the proxy cuts stays cut for
the rest of that conversation, and a child can only recover it by calling the
`caveman_retrieve` MCP tool. Allowing compression for children needs a recorded
decision by TiesL and a test that children recover cut text; it then means
removing that one header constant from the wrapper.

Never start a Claude child with `--bare` on a subscription login, because under
`--bare` Claude Code reads no OAuth credentials and the child cannot
authenticate. The wrapper never adds `--bare`, `--setting-sources` or
`--settings`, and it never writes a settings file or `~/.codex/config.toml`.

## What the wrapper refuses

When the proxy does not answer, the wrapper stops with exit 3 without starting
the child and prints one line naming `http://127.0.0.1:8787`, the probe's exit
status, `SDG_MODEL_ROUTE=off` and the opt-out (answer `process-model-routing`
no). The probe is `curl -s -o /dev/null --connect-timeout 2 --max-time 3`
against the proxy; only exit 0, any HTTP answer, means up. There is no silent
fallback to a direct launch.

With exit 4 it refuses a Claude child when the parent is already routed, that
is when the inherited `ANTHROPIC_BASE_URL` is set and is not exactly
`https://api.anthropic.com` (an empty value and a trailing slash count as
routed). A settings file that sets `env.ANTHROPIC_BASE_URL` outranks the value
the wrapper puts on the child, so the wrapper refuses (exit 4) and names the file
instead of starting a child that would silently go elsewhere. It refuses the
same way for any value of that key, the first-party URL included, and for a
checked file that exists but is unreadable, empty, not valid JSON, not a JSON
object, or has an `env` that is not an object. The checked locations, kept once
in the wrapper (`SETTINGS_LOCATIONS`) and here:

<!-- BEGIN settings-locations -->
```
user settings.json
cwd .claude/settings.json
cwd .claude/settings.local.json
top .claude/settings.json
top .claude/settings.local.json
managed managed-settings.json
args --settings
```
<!-- END settings-locations -->

Here `user` is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, `cwd` the child's working
directory, `top` its git top level, and `args` every `--settings` argument of the
command (`--settings <file>`, `--settings=<file>` or inline JSON). The
managed-settings file is `/Library/Application Support/ClaudeCode/managed-settings.json`
on macOS and `/etc/claude-code/managed-settings.json` on Linux (by `uname -s`).
On any other platform the managed location is unknown, so the wrapper refuses
with exit 4. This list follows Claude Code's documented settings scopes; it has
not been probed against every Claude Code version.

A Codex child is refused with exit 4 when `${CODEX_HOME:-$HOME/.codex}/config.toml`
is missing or cannot be parsed, when its top-level `model_provider` is not
`caveman`, or when its `[model_providers.caveman]` table already has
`http_headers`. The Codex route itself lives in the user's own Codex config,
written by the Caveman installer, which SDG reads but never writes.

Two test seams exist, `SDG_ROUTE_PROBE` (an executable used instead of `curl`,
with the same arguments) and `SDG_ROUTE_MANAGED_SETTINGS` (a non-empty path that
replaces only the managed-settings path), and neither can switch routing on.
They guard against accidents, not against the operator: whoever can set them can
also set `SDG_MODEL_ROUTE=off`.

## Session-start warning

`session-context.sh --runtime claude` prints one fixed line when the main session
looks routed: the inherited `ANTHROPIC_BASE_URL`, the user settings file or the
project's `.claude/settings.json` or `.claude/settings.local.json` sets a value
that is not exactly the first-party URL. It names no path or value, fails open on
unreadable or odd files, and does not read the managed file. The Codex runtime
prints nothing extra: a Codex main session is routed by the user's own config.

## Hand-off to #640 and #513

No session text tells the Orchestrator to use the wrapper: the session-start
budget has no room without editing the stamped `ORCHESTRATOR.md`. Until #640
carries the launch rule, TiesL asks for routed launches in his own words, and a
launch without the wrapper runs unrouted and unmetered, as before. The text
handed to #640:

> Process-model-routing yes: start every process-delegated Claude or Codex stage
> as `"$SPEC_DRIVEN_GUARDRAILS_DIR/route-child.sh" <claude|codex> -- <command>`;
> exit 3 or 4 is a halt to report, never a cue to launch without the wrapper.

#640's launch rules and #513 W3's launcher call the wrapper and reimplement no
part of it. If #640 puts that text into a stamped file, #640 needs a behavior
run.

## Disclosed risk

Before this change, Codex role children ran through the proxy in compress mode,
and Claude sessions did too while a user settings file pointed at the proxy. Some
of them may have worked on contract text that was cut, and cut text stays cut for
the rest of a conversation. Whether that changed any role's decision cannot be
established from the metadata SDG may read; this change does not remediate it.

## Live check

`test/behavior/model-routing-smoke.md` is the acceptance-time smoke test through
the real proxy (AC12). It stays UNRUN until a run is recorded there.

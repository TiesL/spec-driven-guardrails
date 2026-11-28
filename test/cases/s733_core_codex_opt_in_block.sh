#!/usr/bin/env bash
# S733 — Codex: opt-in yes installs the byte-identical core block and the managed project_doc_max_bytes key; status reports a stale block and instructions-over-limit; no or unanswered installs nothing; never ~/.codex (#750 AC1, AC3, AC4; A66 D1, D3, D4)
# Covers: F38
#
# Seam: `adopt.sh --runtime codex <project>` and `adopt.sh --status --runtime
# codex <project>` run from a sandbox clone, `session-context.sh --runtime
# codex`, then the project's AGENTS.md bytes (both managed blocks), the
# project .codex/config.toml (top-level key read as TOML: before the first
# table header) and a digest of the fixture HOME.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/core-delivery-750.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/core-delivery-750.sh"

sandbox_create
trap sandbox_destroy EXIT

wf="$(sandbox_copy_repo wf)"
ORCH="$wf/$CORE750_ORCH_REL"
mkdir -p "$HOME/.codex"
printf 'model = "user-owned"\n' > "$HOME/.codex/config.toml"
home_before="$(core750_tree_digest "$HOME")"

status_run() { # project -> output in $st_out, exit in $st_rc
  st_out="$(SPEC_DRIVEN_GUARDRAILS_DIR="$wf" "$wf/adopt.sh" --status --runtime codex "$1" 2>&1)"
  st_rc=$?
}
sc_codex() { # project -> session-context.sh --runtime codex output
  "$wf/session-context.sh" --runtime codex "$1" 2>/dev/null
}
block_ok() { # project -> 0 when the core block holds exactly ORCHESTRATOR.md
  local a="$1/AGENTS.md"
  core750_block "$a" > "$SANDBOX/block.bin" || { echo "no single orchestrator-core block in AGENTS.md"; return 1; }
  cmp -s "$SANDBOX/block.bin" "$ORCH" || { echo "the core block bytes differ from ORCHESTRATOR.md"; return 1; }
  python3 -I - "$a" "$CORE750_WF_END" "$CORE750_BEGIN" <<'PY' || { echo "the core block does not follow the workflow block"; return 1; }
import sys
d = open(sys.argv[1], 'rb').read()
we, cb = sys.argv[2].encode(), sys.argv[3].encode()
sys.exit(0 if we in d and cb in d and d.index(cb) > d.index(we) else 1)
PY
}

USER_CONFIG='model = "project-owned"

[profiles.fixture]
model = "fixture"
'
USER_AGENTS='Project-owned instructions before the managed blocks.
'

# --- 1. yes installs block and key ------------------------------------------
p="$(fresh_project yes)"
write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
mkdir -p "$p/.codex"
printf '%s' "$USER_CONFIG" > "$p/.codex/config.toml"
printf '%s' "$USER_AGENTS" > "$p/AGENTS.md"
core750_adopt "$wf" "$p" --runtime codex || fail "S733/yes — Codex adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
msg="$(block_ok "$p")" || fail "S733/yes — $msg"
grep -qF "$CORE750_WF_BEGIN" "$p/AGENTS.md" || fail "S733/yes — the workflow block is missing"
head -n 1 "$p/AGENTS.md" | grep -qxF 'Project-owned instructions before the managed blocks.' \
  || fail "S733/yes — project-owned AGENTS.md text was not kept"
[ "$(core750_toml_top "$p/.codex/config.toml" project_doc_max_bytes)" = 65536 ] \
  || fail "S733/yes — .codex/config.toml has no top-level project_doc_max_bytes = 65536"
[ "$(grep -c 'project_doc_max_bytes' "$p/.codex/config.toml" 2>/dev/null)" = 1 ] \
  || fail "S733/yes — project_doc_max_bytes is not written exactly once"
for l in 'model = "project-owned"' '[profiles.fixture]' 'model = "fixture"'; do
  grep -qxF "$l" "$p/.codex/config.toml" || fail "S733/yes — project-owned config line lost: $l"
done
status_run "$p"
[ "$st_rc" = 0 ] || fail "S733/status-clean — status exited $st_rc on a fresh opted-in install: $(grep -i 'stale\|over-limit' <<<"$st_out" | head -n 2 | tr '\n' ' ')"
grep -q 'instructions-over-limit' <<<"$st_out" && fail "S733/status-clean — instructions-over-limit with the managed key in place"
out="$(sc_codex "$p")"
grep -q '^Warning: Codex installation' <<<"$out" && fail "S733/status-clean — session-context warns on a clean install"
[ -z "$(printf '%s' "$out" > "$SANDBOX/sc.txt"; core750_rule_hits "$ORCH" "$SANDBOX/sc.txt")" ] \
  || fail "S733/yes — session-context.sh --runtime codex prints core rule text"
cp "$p/AGENTS.md" "$SANDBOX/agents.installed"

# --- 2. stale block: project edit, then a clone release ------------------------
python3 -I - "$p/AGENTS.md" "$CORE750_BEGIN" <<'PY'
import sys
p, b = sys.argv[1], sys.argv[2].encode()
d = open(p, 'rb').read()
if b in d:
    i = d.index(b) + len(b) + 5
    d = d[:i] + (b'X' if d[i:i+1] != b'X' else b'Y') + d[i+1:]
    open(p, 'wb').write(d)
PY
status_run "$p"
if grep -qF "$CORE750_BEGIN" "$p/AGENTS.md"; then
  [ "$st_rc" != 0 ] || fail "S733/stale-edit — status exited 0 with an edited core block"
  grep -qi 'stale.*AGENTS\.md\|AGENTS\.md.*stale' <<<"$st_out" || fail "S733/stale-edit — status does not name AGENTS.md as stale"
  grep -q '^Warning: Codex installation' <<<"$(sc_codex "$p")" || fail "S733/stale-edit — session-context.sh --runtime codex does not warn"
else
  fail "S733/stale-edit — no core block to edit (install missing)"
fi
core750_adopt "$wf" "$p" --runtime codex || fail "S733/repair — re-adoption failed"
cmp -s "$p/AGENTS.md" "$SANDBOX/agents.installed" || fail "S733/repair — re-adoption did not restore the installed bytes"
cp "$ORCH" "$SANDBOX/orch.keep"
printf -- '- OR99 RELEASE-SENTINEL-750 a later release line.\n' >> "$ORCH"
status_run "$p"
[ "$st_rc" != 0 ] || fail "S733/stale-release — status exited 0 after the clone's ORCHESTRATOR.md changed"
core750_adopt "$wf" "$p" --runtime codex || fail "S733/stale-release — re-adoption failed"
msg="$(block_ok "$p")" || fail "S733/stale-release — after re-adoption: $msg"
cp "$SANDBOX/orch.keep" "$ORCH"
core750_adopt "$wf" "$p" --runtime codex || fail "S733/restore — re-adoption failed"

# --- 3. instructions-over-limit -------------------------------------------------
cp "$p/.codex/config.toml" "$SANDBOX/config.installed"
grep -v 'project_doc_max_bytes' "$SANDBOX/config.installed" > "$p/.codex/config.toml"
status_run "$p"
grep -q 'instructions-over-limit' <<<"$st_out" \
  || fail "S733/over-limit-default — without the key (32 KiB default) status does not report instructions-over-limit"
[ "$st_rc" != 0 ] || fail "S733/over-limit-default — status exited 0 over the limit"
cp "$SANDBOX/config.installed" "$p/.codex/config.toml"
cp "$p/AGENTS.md" "$SANDBOX/agents.restore"
python3 -I - "$p/AGENTS.md" <<'PY'
import sys
p = sys.argv[1]
d = open(p, 'rb').read()
open(p, 'wb').write((b'pad ' * 9000) + b'\n' + d)
PY
status_run "$p"
grep -q 'instructions-over-limit' <<<"$st_out" \
  || fail "S733/over-limit-key — an AGENTS.md chain above 65536 bytes is not reported as instructions-over-limit"
cp "$SANDBOX/agents.restore" "$p/AGENTS.md"

# --- 4. no, unanswered, absent row: nothing installed ---------------------------
for v in no pending absent; do
  q="$(fresh_project "codex-$v")"
  case "$v" in
    no) write_adoption "$q/WORKFLOW-ADOPTION.md" process-multi-agent-roles no ;;
    pending) write_adoption "$q/WORKFLOW-ADOPTION.md" process-multi-agent-roles pending ;;
    absent) write_adoption "$q/WORKFLOW-ADOPTION.md" process-issue-tracking yes ;;
  esac
  core750_adopt "$wf" "$q" --runtime codex || fail "S733/$v — Codex adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
  grep -qF "$CORE750_WF_BEGIN" "$q/AGENTS.md" || fail "S733/$v — the workflow block itself is missing (control)"
  grep -qF "$CORE750_BEGIN" "$q/AGENTS.md" && fail "S733/$v — the core block was installed without a yes"
  [ -z "$(core750_rule_hits "$ORCH" "$q/AGENTS.md")" ] || fail "S733/$v — AGENTS.md carries core rule text without a yes"
  [ -e "$q/.codex/config.toml" ] && fail "S733/$v — .codex/config.toml was written without a yes"
done

# --- 5. yes -> no re-run removes only block and key -----------------------------
wf_block_before="$(awk -v b="$CORE750_WF_BEGIN" -v e="$CORE750_WF_END" 'index($0,b){f=1} f{print} index($0,e){f=0}' "$p/AGENTS.md")"
write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
core750_adopt "$wf" "$p" --runtime codex || fail "S733/opt-out — re-adoption failed"
grep -qF "$CORE750_BEGIN" "$p/AGENTS.md" && fail "S733/opt-out — the core block survived a no re-run"
grep -qF "$CORE750_END" "$p/AGENTS.md" && fail "S733/opt-out — a core end marker survived a no re-run"
[ "$(awk -v b="$CORE750_WF_BEGIN" -v e="$CORE750_WF_END" 'index($0,b){f=1} f{print} index($0,e){f=0}' "$p/AGENTS.md")" = "$wf_block_before" ] \
  || fail "S733/opt-out — the workflow block changed"
head -n 1 "$p/AGENTS.md" | grep -qxF 'Project-owned instructions before the managed blocks.' \
  || fail "S733/opt-out — project-owned AGENTS.md text was not kept"
printf '%s' "$USER_CONFIG" > "$SANDBOX/config.user"
cmp -s "$p/.codex/config.toml" "$SANDBOX/config.user" \
  || fail "S733/opt-out — .codex/config.toml is not back to the project-owned bytes (managed key left or user lines changed)"

# --- 6. never ~/.codex ------------------------------------------------------------
[ "$(core750_tree_digest "$HOME")" = "$home_before" ] || fail "S733/user — Codex adoption wrote under HOME"

test_done

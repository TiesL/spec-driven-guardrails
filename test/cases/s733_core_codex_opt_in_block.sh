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
grep -qxF 'Project-owned instructions before the managed blocks.' <<<"$(head -n 1 "$p/AGENTS.md")" \
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
grep -qxF 'Project-owned instructions before the managed blocks.' <<<"$(head -n 1 "$p/AGENTS.md")" \
  || fail "S733/opt-out — project-owned AGENTS.md text was not kept"
printf '%s' "$USER_CONFIG" > "$SANDBOX/config.user"
cmp -s "$p/.codex/config.toml" "$SANDBOX/config.user" \
  || fail "S733/opt-out — .codex/config.toml is not back to the project-owned bytes (managed key left or user lines changed)"

# --- 5b. key ownership (A66 D4): a project-owned key is not adoption's ---------
# The project set project_doc_max_bytes itself (131072): yes keeps that line
# and adds no second one; status reads it as the effective limit (a chain
# between 65536 and 131072 bytes is not over the limit); a no re-run leaves
# the project-owned bytes, key included.
OWNED_CONFIG='project_doc_max_bytes = 131072

[profiles.fixture]
model = "fixture"
'
o="$(fresh_project owned-key)"
write_adoption "$o/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
mkdir -p "$o/.codex"
printf '%s' "$OWNED_CONFIG" > "$o/.codex/config.toml"
printf '%s' "$OWNED_CONFIG" > "$SANDBOX/config.owned"
core750_adopt "$wf" "$o" --runtime codex || fail "S733/owned-key — Codex adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
msg="$(block_ok "$o")" || fail "S733/owned-key — $msg"
[ "$(grep -c 'project_doc_max_bytes' "$o/.codex/config.toml" 2>/dev/null)" = 1 ] \
  || fail "S733/owned-key — project_doc_max_bytes is duplicated or gone next to a project-owned key"
[ "$(core750_toml_top "$o/.codex/config.toml" project_doc_max_bytes)" = 131072 ] \
  || fail "S733/owned-key — the project-owned project_doc_max_bytes = 131072 was replaced"
cp "$o/AGENTS.md" "$SANDBOX/agents.owned"
python3 -I - "$o/AGENTS.md" <<'PY'
import sys
p = sys.argv[1]
d = open(p, 'rb').read()
pad = max(0, 70000 - len(d))
open(p, 'wb').write((b'p' * pad) + b'\n' + d)
PY
status_run "$o"
grep -q 'instructions-over-limit' <<<"$st_out" \
  && fail "S733/owned-key — status ignores the project-owned limit (131072): a chain of about 70000 bytes reported over the limit"
cp "$SANDBOX/agents.owned" "$o/AGENTS.md"
write_adoption "$o/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
core750_adopt "$wf" "$o" --runtime codex || fail "S733/owned-key — no re-run failed"
cmp -s "$o/.codex/config.toml" "$SANDBOX/config.owned" \
  || fail "S733/owned-key — a no re-run changed the project-owned config (the project's own key is not adoption's to remove)"

# An adoption-created config.toml is deleted again by the no re-run.
c="$(fresh_project created-config)"
write_adoption "$c/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
core750_adopt "$wf" "$c" --runtime codex || fail "S733/created — Codex adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
[ "$(core750_toml_top "$c/.codex/config.toml" project_doc_max_bytes)" = 65536 ] \
  || fail "S733/created — no managed project_doc_max_bytes = 65536 in a project without a config"
write_adoption "$c/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
core750_adopt "$wf" "$c" --runtime codex || fail "S733/created — no re-run failed"
[ -e "$c/.codex/config.toml" ] && fail "S733/created — a no re-run left the config.toml that adoption created"

# --- 7. review round 1 on #751 (A66 D3, D4, trust precondition) ----------------
# 7a. The inventory states the trust precondition of the managed key.
status_run "$c"
grep -qF 'in effect only for a trusted project' <<<"$st_out" \
  || fail "S733/trust-note — the status inventory does not say the managed key is in effect only for a trusted project"

# 7b. Yes answered after the last adoption: status notes pending and exits 0,
# and session-context.sh --runtime codex passes that line through, without
# core rule text or an OR ID.
y="$(fresh_project yes-pending)"
write_adoption "$y/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
core750_adopt "$wf" "$y" --runtime codex || fail "S733/pending — Codex adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
write_adoption "$y/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
status_run "$y"
[ "$st_rc" = 0 ] || fail "S733/pending — status exited $st_rc for a yes answered after the last adoption (control)"
grep -q '^pending:' <<<"$st_out" || fail "S733/pending — status prints no pending: line (control)"
out="$(sc_codex "$y")"
grep -qF 'adopt.sh --runtime codex' <<<"$out" \
  || fail "S733/pending — session-context.sh --runtime codex does not pass the pending line (no 'adopt.sh --runtime codex' line)"
grep -q 'OR[0-9]' <<<"$out" && fail "S733/pending — session-context.sh --runtime codex prints an OR ID"
[ -z "$(printf '%s' "$out" > "$SANDBOX/sc.pending"; core750_rule_hits "$ORCH" "$SANDBOX/sc.pending")" ] \
  || fail "S733/pending — session-context.sh --runtime codex prints core rule text"

# 7c. instructions-over-limit only with an installed core block: a project
# that answered no, pending or yes-pending, with a 40,000-byte project-owned
# AGENTS.md, exits 0 without the line (S733 section 3 keeps the installed
# over-limit case non-zero).
for v in no pending yes-pending; do
  q="$SANDBOX/codex-$v"
  [ "$v" = yes-pending ] && q="$y" # section 4 made codex-no and codex-pending
  status_run "$q"
  [ "$st_rc" = 0 ] || fail "S733/limit-gate/$v — status exited $st_rc before padding (control): $(grep -v '^unchanged:' <<<"$st_out" | tail -n 3 | tr '\n' ' ')"
  python3 -I - "$q/AGENTS.md" <<'PY'
import sys
p = sys.argv[1]
d = open(p, 'rb').read()
pad = max(0, 40000 - len(d) - 1)
open(p, 'wb').write(d + b'\n' + b'q' * pad)
PY
  [ "$(wc -c < "$q/AGENTS.md" | tr -d ' ')" -ge 40000 ] || fail "S733/limit-gate/$v — fixture AGENTS.md is under 40000 bytes"
  status_run "$q"
  grep -q 'instructions-over-limit' <<<"$st_out" \
    && fail "S733/limit-gate/$v — instructions-over-limit for a project without an installed core block"
  [ "$st_rc" = 0 ] || fail "S733/limit-gate/$v — status exited $st_rc for a 40000-byte project AGENTS.md without an installed core block"
done

# 7d. A project-owned key in any TOML form: yes writes no managed key (bytes
# unchanged, exactly one definition), and a no re-run leaves the bytes too.
# Python 3.9 has no tomllib, so the definitions are counted as lines.
i=0
for form in 'project_doc_max_bytes = 100_000' 'project_doc_max_bytes=0x10000' \
            '"project_doc_max_bytes" = 70000' 'after-array'; do
  i=$((i + 1))
  k="$(fresh_project "key-form-$i")"
  mkdir -p "$k/.codex"
  if [ "$form" = after-array ]; then
    printf 'model = "project-owned"\nmatrix = [\n  [1, 2],\n  [3, 4],\n]\nproject_doc_max_bytes = 131072\n\n[profiles.fixture]\nmodel = "fixture"\n' > "$k/.codex/config.toml"
  else
    printf '%s\n\n[profiles.fixture]\nmodel = "fixture"\n' "$form" > "$k/.codex/config.toml"
  fi
  cp "$k/.codex/config.toml" "$SANDBOX/config.form$i"
  for a in yes no; do
    write_adoption "$k/WORKFLOW-ADOPTION.md" process-multi-agent-roles "$a"
    core750_adopt "$wf" "$k" --runtime codex || fail "S733/key-form/$form/$a — Codex adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
    cmp -s "$k/.codex/config.toml" "$SANDBOX/config.form$i" \
      || fail "S733/key-form/$form/$a — adoption changed a project-owned config whose key is written as: $form"
    [ "$(grep -cE '^[[:space:]]*"?project_doc_max_bytes"?[[:space:]]*=' "$k/.codex/config.toml" 2>/dev/null)" = 1 ] \
      || fail "S733/key-form/$form/$a — project_doc_max_bytes is not defined exactly once"
    # The core block (about 41 KB) is installed under yes: status reads the
    # project's key in any TOML integer form, so it is not over the limit.
    if [ "$a" = yes ] && [ "$form" != after-array ]; then
      status_run "$k"
      [ "$st_rc" = 0 ] || fail "S733/key-form/$form/status — status exited $st_rc with the project key written as: $form ($(grep 'instructions-over-limit' <<<"$st_out" | cut -c1-120))"
      cmp -s "$k/.codex/config.toml" "$SANDBOX/config.form$i" || fail "S733/key-form/$form/status — status changed the config bytes"
    fi
  done
done

# 7e. A comment naming the key is not a definition: yes writes the managed
# key once and status exits 0; a no re-run restores the project's bytes.
k="$(fresh_project key-comment)"
mkdir -p "$k/.codex"
printf '# project_doc_max_bytes note\nmodel = "project-owned"\n\n[profiles.fixture]\nmodel = "fixture"\n' > "$k/.codex/config.toml"
cp "$k/.codex/config.toml" "$SANDBOX/config.comment"
write_adoption "$k/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
core750_adopt "$wf" "$k" --runtime codex || fail "S733/key-comment/yes — Codex adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
[ "$(core750_toml_top "$k/.codex/config.toml" project_doc_max_bytes)" = 65536 ] \
  || fail "S733/key-comment/yes — a comment mentioning the key blocked the managed project_doc_max_bytes = 65536"
[ "$(grep -cE '^[[:space:]]*"?project_doc_max_bytes"?[[:space:]]*=' "$k/.codex/config.toml" 2>/dev/null)" = 1 ] \
  || fail "S733/key-comment/yes — project_doc_max_bytes is not defined exactly once"
status_run "$k"
[ "$st_rc" = 0 ] || fail "S733/key-comment/yes — status exited $st_rc: $(grep 'instructions-over-limit' <<<"$st_out" | cut -c1-120)"
write_adoption "$k/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
core750_adopt "$wf" "$k" --runtime codex || fail "S733/key-comment/no — Codex adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
cmp -s "$k/.codex/config.toml" "$SANDBOX/config.comment" \
  || fail "S733/key-comment/no — a no re-run did not restore the project's config bytes"

# 7f. A defined key with an unreadable value: no managed key, status fails
# closed (exit 1) and its over-limit line says to write a plain top-level integer.
k="$(fresh_project key-unreadable)"
mkdir -p "$k/.codex"
printf 'project_doc_max_bytes = "big"\n\n[profiles.fixture]\nmodel = "fixture"\n' > "$k/.codex/config.toml"
cp "$k/.codex/config.toml" "$SANDBOX/config.big"
write_adoption "$k/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
core750_adopt "$wf" "$k" --runtime codex || fail "S733/key-unreadable — Codex adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
cmp -s "$k/.codex/config.toml" "$SANDBOX/config.big" \
  || fail "S733/key-unreadable — adoption changed a config whose project key has an unreadable value (managed key added)"
status_run "$k"
[ "$st_rc" = 1 ] || fail "S733/key-unreadable — status exited $st_rc, not 1 (fail closed) for an unreadable project key"
ol_line=$(grep 'instructions-over-limit' <<<"$st_out")
grep -qi 'plain top-level integer' <<<"$ol_line" \
  || fail "S733/key-unreadable — the instructions-over-limit line does not say to write project_doc_max_bytes as a plain top-level integer"

# --- 6. never ~/.codex ------------------------------------------------------------
[ "$(core750_tree_digest "$HOME")" = "$home_before" ] || fail "S733/user — Codex adoption wrote under HOME"

test_done

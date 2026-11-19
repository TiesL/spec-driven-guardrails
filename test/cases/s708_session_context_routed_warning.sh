#!/usr/bin/env bash
# S708 — Session start warns once when the main session looks routed (#707; AC9)
# Covers: F75
#
# Seam: `session-context.sh --runtime claude|codex <project>` output under a
# built environment (fixture HOME and CLAUDE_CONFIG_DIR), compared with a
# baseline run of the same project; the worst-case budget with S309's fixture
# and lib/context-budget.sh.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../../lib/context-budget.sh
. "$TEST_REPO_ROOT/lib/context-budget.sh"

sandbox_create
trap sandbox_destroy EXIT

SC="$TEST_REPO_ROOT/session-context.sh"
X="$SANDBOX/x"
mkdir -p "$X/home" "$X/cfg" "$X/managed"
proj="$X/project"
mkdir -p "$proj/.claude"
git -C "$proj" init -q -b main
write_adoption "$proj/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
ln -s "$TEST_REPO_ROOT/WORKFLOW.md" "$proj/CLAUDE.md"
token_url="http://tok3n.example:1/zz"
pathx="$(command -v python3 | xargs dirname):$(command -v git | xargs dirname):/usr/bin:/bin"

# sc <runtime> [VAR=value ...]: session-context.sh output (stdout) into sc_out,
# stderr into sc_err, exit status into sc_status.
sc() {
  local rt="$1"
  shift
  sc_out="$(env -i "PATH=$pathx" "HOME=$X/home" "CLAUDE_CONFIG_DIR=$X/cfg" \
    "SDG_ROUTE_MANAGED_SETTINGS=$X/managed/managed-settings.json" "$@" \
    "$SC" --runtime "$rt" "$proj" 2>"$X/err"; printf x)"
  sc_status=$?
  sc_out="${sc_out%x}"
  sc_err="$(cat "$X/err")"
}

sc claude
base_claude="$sc_out"
sc codex
base_codex="$sc_out"

# added_lines <baseline> <output>: lines of output not in the baseline, and
# "REMOVED" when the baseline lost a line.
added_lines() {
  diff <(printf '%s' "$1") <(printf '%s' "$2") | awk '/^</{print "REMOVED"} /^>/{sub(/^> /,""); print}'
}

user_file="$X/cfg/settings.json"
proj_file="$proj/.claude/settings.json"
local_file="$proj/.claude/settings.local.json"
route_json() { printf '{"env":{"ANTHROPIC_BASE_URL":"%s"}}\n' "$1"; }
reset_files() { rm -f "$user_file" "$proj_file" "$local_file" "$X/managed/managed-settings.json"; }

warn_line=""
expect_one_line() { # <label> [VAR=value ...]
  local label="$1"
  shift
  sc claude "$@"
  [ "$sc_status" = 0 ] || fail "$label — exit $sc_status"
  local added
  added="$(added_lines "$base_claude" "$sc_out")"
  if [ "$(printf '%s' "$added" | awk 'END{print NR}')" != 1 ] || [ "$added" = REMOVED ]; then
    fail "$label — expected exactly one added line, got: '$added'"
    return
  fi
  [ "${#added}" -le 160 ] || fail "$label — the line is ${#added} characters (> 160): $added"
  case "$added" in *ANTHROPIC_BASE_URL*) ;; *) fail "$label — the line does not name ANTHROPIC_BASE_URL: $added" ;; esac
  case "$added" in *tok3n*|*/*|*"$X"*) fail "$label — the line carries a path or the URL value: $added" ;; esac
  if [ -z "$warn_line" ]; then warn_line="$added"
  elif [ "$added" != "$warn_line" ]; then fail "$label — the line differs per case: '$added' vs '$warn_line'"; fi
}
expect_nothing() { # <label> [VAR=value ...]
  local label="$1"
  shift
  sc claude "$@"
  [ "$sc_status" = 0 ] || fail "$label — exit $sc_status"
  [ "$sc_out" = "$base_claude" ] || fail "$label — output differs from the baseline: $(added_lines "$base_claude" "$sc_out")"
  [ -z "$sc_err" ] || fail "$label — printed an error: $sc_err"
}

# (a) environment only
expect_one_line "S708/a" "ANTHROPIC_BASE_URL=$token_url"
# (b) user settings file
reset_files; route_json "$token_url" >"$user_file"
expect_one_line "S708/b"
# (c) project settings file
reset_files; route_json "$token_url" >"$proj_file"
expect_one_line "S708/c"
# (i) project local settings file
reset_files; route_json "$token_url" >"$local_file"
expect_one_line "S708/i"
# (d) environment and user file together: still one line
reset_files; route_json "$token_url" >"$user_file"
expect_one_line "S708/d" "ANTHROPIC_BASE_URL=$token_url"
reset_files; route_json "$token_url" >"$user_file"; route_json "$token_url" >"$proj_file"; route_json "$token_url" >"$local_file"
expect_one_line "S708/d-all" "ANTHROPIC_BASE_URL=$token_url"
# (h) the first-party predicate is exact
reset_files
for v in "" "https://api.anthropic.com/" "https://api.anthropic.com.evil.example"; do
  expect_one_line "S708/h [$v]" "ANTHROPIC_BASE_URL=$v"
done
# (e) first-party value, in the environment and in a file
expect_nothing "S708/e-env" "ANTHROPIC_BASE_URL=https://api.anthropic.com"
route_json "https://api.anthropic.com" >"$user_file"
expect_nothing "S708/e-file"
# (g) the name only inside a hook command
reset_files
printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"ANTHROPIC_BASE_URL=x true"}]}]}}' >"$user_file"
expect_nothing "S708/g"
# (j) a managed-settings file is not read
reset_files; route_json "$token_url" >"$X/managed/managed-settings.json"
expect_nothing "S708/j"
# (f), (k) odd files fail open, in each of the three locations
for f in "$user_file" "$proj_file" "$local_file"; do
  for v in truncated zero-byte whitespace array env-string binary unreadable; do
    reset_files
    case "$v" in
      truncated) printf '{"env":{"ANTHROPIC_BASE_URL"' >"$f" ;;
      zero-byte) : >"$f" ;;
      whitespace) printf ' \n\t\n' >"$f" ;;
      array) printf '[]\n' >"$f" ;;
      env-string) printf '{"env":"x"}\n' >"$f" ;;
      binary) printf '\377\376\000\001ANTHROPIC_BASE_URL\000' >"$f" ;;
      unreadable)
        [ "$(id -u)" = 0 ] && continue
        route_json "$token_url" >"$f"; chmod 000 "$f" ;;
    esac
    expect_nothing "S708/k/$v/${f#"$X"/}"
    chmod 644 "$f" 2>/dev/null
  done
done
reset_files

# --- the Codex runtime is unchanged ---------------------------------------------
route_json "$token_url" >"$user_file"; route_json "$token_url" >"$proj_file"
sc codex "ANTHROPIC_BASE_URL=$token_url"
[ "$sc_out" = "$base_codex" ] || fail "S708/codex — --runtime codex output changed: $(added_lines "$base_codex" "$sc_out")"
reset_files

# --- independent of the process-model-routing answer --------------------------
for answer in yes no; do
  write_adoption "$proj/WORKFLOW-ADOPTION.md" process-multi-agent-roles no process-model-routing "$answer"
  sc claude
  b="$sc_out"
  sc claude "ANTHROPIC_BASE_URL=$token_url"
  [ "$(added_lines "$b" "$sc_out")" = "$warn_line" ] || fail "S708/answer-$answer — the warning depends on the routing answer"
done

# --- worst case: still within the budget, the line counted in slot 1 -----------
long="$(printf 'p%.0s' $(seq 1 100))"
wf="$SANDBOX/clone-$long"
mkdir -p "$wf"
(cd "$TEST_REPO_ROOT" && tar --exclude='./.git' --exclude='./wip' --exclude='./CLAUDE.md' \
  --exclude='./.claude/settings.json' --exclude='./.claude/skills' -cf - .) | (cd "$wf" && tar -xf -)
wproj="$SANDBOX/project-$long"
mkdir -p "$wproj/.claude"
git -C "$wproj" init -q -b main
ids=()
while IFS='|' read -r id value _; do
  case "$value" in session-context:*) ids+=("$id" yes) ;; esac
done < <(. "$wf/lib/changes.sh"; reaches_session_values "$wf/CHANGES.md")
write_adoption "$wproj/WORKFLOW-ADOPTION.md" "${ids[@]}"
ln -s "$SANDBOX/nowhere/WORKFLOW.md" "$wproj/CLAUDE.md"
route_json "$token_url" >"$user_file"
for n in 1 2; do
  out="$(env -i "PATH=$pathx" "HOME=$X/home" "CLAUDE_CONFIG_DIR=$X/cfg" "ANTHROPIC_BASE_URL=$token_url" \
    "$wf/session-context.sh" --runtime claude --slot "$n" "$wproj" 2>/dev/null; printf x)"
  out="${out%x}"
  size="$(printf '%s' "$out" | context_chars)"
  [ "$size" -le "$CONTEXT_BUDGET_CHARS" ] || fail "S708/budget — slot $n is $size characters, over $CONTEXT_BUDGET_CHARS"
  if [ "$n" = 1 ] && [ -n "$warn_line" ]; then
    grep -qxF "$warn_line" <<<"$out" || fail "S708/budget — the warning is not printed in slot 1"
  fi
done
reset_files

# --- test hygiene: sandbox_create clears a routed calling shell ------------------
leaked="$(
  export ANTHROPIC_BASE_URL=http://127.0.0.1:9 CLAUDE_CONFIG_DIR=/nonexistent CODEX_HOME=/nonexistent \
    SDG_MODEL_ROUTE=on SDG_ROUTE_PROBE=/nonexistent SDG_ROUTE_MANAGED_SETTINGS=/nonexistent
  sandbox_create
  for v in ANTHROPIC_BASE_URL CLAUDE_CONFIG_DIR CODEX_HOME SDG_MODEL_ROUTE SDG_ROUTE_PROBE SDG_ROUTE_MANAGED_SETTINGS; do
    eval "[ -z \"\${$v+x}\" ]" || printf '%s ' "$v"
  done
  sandbox_destroy
)"
[ -z "$leaked" ] || fail "S708/hygiene — sandbox_create leaves set: $leaked"

test_done

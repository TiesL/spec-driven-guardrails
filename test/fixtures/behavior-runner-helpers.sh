#!/usr/bin/env bash
# test/fixtures/behavior-runner-helpers.sh — fixture builders for the S315/S316
# cases (#499, A41): a throwaway git repo holding an "old" and a "new"
# ORCHESTRATOR.md, a scenario file assembled from cases, and a stub `claude`
# (CLAUDE_BIN) that returns canned JSON. No test here calls a model.
#
# Source, don't execute. Needs a sandbox (test/lib.sh sandbox_create) first.
# Bash 3.2-compatible.

BF_ORCH_REL="skills/role-contracts/ORCHESTRATOR.md"
BF_SCEN_REL="test/behavior/orchestrator-scenarios.md"
BF_STAMP_REL="test/behavior/orchestrator-diff.stamp"
BF_MARKER='<!-- session-context: slot -->'

# bf_init <dir>: stub + empty repo skeleton under <dir>.
bf_init() {
  BF_DIR="$1"
  BF_REPO="$BF_DIR/repo"
  STUB_DIR="$BF_DIR/stub"
  export STUB_DIR
  mkdir -p "$BF_REPO/skills/role-contracts" "$BF_REPO/test/behavior" "$STUB_DIR"
  git -C "$BF_REPO" init -q -b main
  git -C "$BF_REPO" config user.email t@example.invalid
  git -C "$BF_REPO" config user.name t
  git -C "$BF_REPO" config commit.gpgsign false
  BF_STUB="$BF_DIR/stub-claude"
  cat >"$BF_STUB" <<'STUB'
#!/usr/bin/env bash
# Stub claude: records its arguments, answers from $STUB_DIR/table.
# table line: <ARM> <tag> <v1,v2,v3,...>   (ARM = OLD, NEW or MUT, from the
# system-prompt file name); the nth call for an (arm, tag) pair returns vn.
sp="" prev=""
for a in "$@"; do
  [ "$prev" = "--system-prompt-file" ] && sp="$a"
  prev="$a"
done
prompt="$(cat)"
d="$STUB_DIR"
n=$(( $(cat "$d/n" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$d/n"
printf '%s\0' "$@" >"$d/call-$n.args"
pwd >"$d/call-$n.cwd"
ls -A | wc -l | tr -d ' ' >"$d/call-$n.cwdcount"
printf '%s' "$prompt" >"$d/call-$n.prompt"
case "$(basename "$sp")" in
  arm-old.txt) arm=OLD ;;
  arm-new.txt) arm=NEW ;;
  arm-mut.txt) arm=MUT ;;
  *) arm=OTHER ;;
esac
echo "$arm" >"$d/call-$n.arm"
cp "$sp" "$d/seen-$arm.txt"
tag="$(printf '%s' "$prompt" | sed -n 's/.*\[\([a-z0-9]*\)\].*/\1/p' | head -1)"
c=$(( $(cat "$d/cnt-$arm-$tag" 2>/dev/null || echo 0) + 1 ))
echo "$c" >"$d/cnt-$arm-$tag"
vals="$(awk -v a="$arm" -v t="$tag" '$1==a && $2==t {print $3}' "$d/table" | head -1)"
v="$(printf '%s' "$vals" | cut -d, -f"$c")"
[ -n "$v" ] || v=stop
printf '{"type":"result","is_error":false,"structured_output":{"next_action":"%s","reason":"stub"},"total_cost_usd":%s,"modelUsage":{"claude-stub-1":{"costUSD":%s}}}\n' "$v" "${STUB_COST:-0.01}" "${STUB_COST:-0.01}"
STUB
  chmod +x "$BF_STUB"
  # a CLAUDE_BIN that must never run
  BF_FAILSTUB="$BF_DIR/fail-claude"
  printf '#!/usr/bin/env bash\ntouch "%s/model-was-called"\nexit 99\n' "$BF_DIR" >"$BF_FAILSTUB"
  chmod +x "$BF_FAILSTUB"
  bf_reset
}

# bf_reset: forget all cases, stub state and the call log.
bf_reset() {
  BF_BODY="" BF_INTENDED="" BF_COUNT=0
  : >"$STUB_DIR/table"
  rm -f "$STUB_DIR"/n "$STUB_DIR"/call-* "$STUB_DIR"/cnt-* "$STUB_DIR"/seen-*
}

# bf_case <num> <tag> <then> <listed 0|1> <old v,v,v> <new v,v,v> [<mutant v,v,v>]
bf_case() {
  local num="$1" tag="$2" then="$3" listed="$4" old="$5" new="$6" mut="${7:-}"
  BF_BODY="${BF_BODY}### OB${num} · OR40
Given: Case [${tag}] you are the orchestrator in a fixture situation.
When: You decide the next step.
Then: next_action=${then}

"
  [ "$listed" = 1 ] && BF_INTENDED="${BF_INTENDED}- OB${num} (OR40): fixture change, decided in #1.
"
  printf 'OLD %s %s\nNEW %s %s\n' "$tag" "$old" "$tag" "$new" >>"$STUB_DIR/table"
  [ -n "$mut" ] && printf 'MUT %s %s\n' "$tag" "$mut" >>"$STUB_DIR/table"
  BF_COUNT=$((BF_COUNT + 1))
}

# bf_build: write the scenario file and both ORCHESTRATOR.md texts. The old
# text is committed; the new text is the working-tree modification.
bf_build() {
  local real_scen="$TEST_REPO_ROOT/$BF_SCEN_REL"
  {
    echo "# Fixture behavior scenarios"
    echo
    sed -n '/^## Schema/,/^## Role and pipeline/p' "$real_scen" | sed '$d'
    echo "## Cases"
    echo
    printf '%s' "$BF_BODY"
    echo "## Intended changes"
    echo
    echo "Fixture list."
    echo
    printf '%s' "$BF_INTENDED"
  } >"$BF_REPO/$BF_SCEN_REL"
  {
    echo "# Fixture run rules"
    echo
    echo "OLDTEXT marker."
    echo "- OR1 Start the pipeline for a work item."
    echo "- OR40 Fix it in the PR; never defer a low finding."
  } >"$BF_REPO/$BF_ORCH_REL"
  git -C "$BF_REPO" add -A >/dev/null 2>&1
  git -C "$BF_REPO" commit -q -m old >/dev/null 2>&1 || true
  {
    echo "# Fixture run rules"
    echo
    echo "NEWTEXT marker."
    echo "- OR1 Start the pipeline for a work item."
    echo "$BF_MARKER"
    echo "- OR40 Fix it in the PR; never defer a low finding."
  } >"$BF_REPO/$BF_ORCH_REL"
}

# bf_run <runner args...>: run the real runner against the fixture repo with
# the stub; sets bf_out, bf_err, bf_status.
bf_run() {
  local errf="$BF_DIR/run.err"
  bf_out="$(CLAUDE_BIN="$BF_STUB" STUB_DIR="$STUB_DIR" "$TEST_REPO_ROOT/test/behavior/orchestrator-diff.sh" --repo "$BF_REPO" --base HEAD "$@" 2>"$errf")"
  bf_status=$?
  bf_err="$(cat "$errf")"
}

# bf_verdict <OB number>: the verdict column of that row in bf_out.
bf_verdict() {
  printf '%s\n' "$bf_out" | awk -F'|' -v k="OB$1" '{ s=$2; gsub(/ /,"",s); if (s==k) { v=$6; gsub(/ /,"",v); print v } }'
}

#!/usr/bin/env bash
# S343-S344 — the Codex instructions and generated AGENTS.md carry the merge-preflight and dispatch-mapping sentences; dispatch-economy marks its extraction Claude-only; tokens=n/a gives no false over-limit line (A44 2a, 2b)
# Covers: F8, F38
#
# Seam: textual check of adapters/codex/INSTRUCTIONS.md and the generated
# adapters/codex/AGENTS.md (load-bearing tokens, not whole sentences), the
# repo generator run into a copy, and pipeline-log-fields.sh against a fake gh
# (the S319 pattern). The S344(2) part pins A44's claim that n/a already counts
# as a present value; it is green before and after. The decision to treat an
# unknown size as a fresh dispatch is OR13's, not this script's.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

INS="$TEST_REPO_ROOT/adapters/codex/INSTRUCTIONS.md"
GEN="$TEST_REPO_ROOT/adapters/codex/AGENTS.md"
SKILL="$TEST_REPO_ROOT/skills/dispatch-economy/SKILL.md"
for f in "$INS" "$GEN" "$SKILL"; do [ -r "$f" ] || { fail "S343 — $f is missing"; test_done; }; done
sandbox_create
trap sandbox_destroy EXIT

# paragraph_with <file> <token>: the blank-line-delimited paragraph holding token.
# Whitespace is flattened, so a token split across a wrapped line still matches.
paragraph_with() { awk -v RS= -v t="$2" 'index($0, t) { print; exit }' "$1" | tr '\n' ' '; }

for f in "$INS" "$GEN"; do
  name="$(basename "$f")"
  flat="$(tr '\n' ' ' < "$f")"
  p="$(paragraph_with "$f" "merge-preflight.sh")"
  [ -n "$p" ] || { fail "S343/a/$name — no paragraph mentions merge-preflight.sh"; continue; }
  assert_contains "S343/a/$name — before gh pr merge" "before \`gh pr merge\`" "$p"
  assert_contains "S343/a/$name — non-zero" "non-zero" "$p"
  case "$p" in *interception*|*"not intercept"*) : ;; *) fail "S343/b/$name — preflight paragraph does not say instruction-driven, not interception: $p" ;; esac
  assert_contains "S343/b/$name — instruction-driven" "instruction-driven" "$p"
  # (c) the closing merge paragraph names confirmation and the preflight.
  m="$(paragraph_with "$f" "Native hooks do not intercept")"
  assert_contains "S343/c/$name — merge confirmation" "explicit human confirmation" "$m"
  assert_contains "S343/c/$name — and the preflight" "preflight" "$m"
  # (d) dispatch mapping.
  assert_contains "S343/d/$name — SendMessage" "SendMessage" "$flat"
  assert_contains "S343/d/$name — fork" "fork" "$flat"
  assert_contains "S343/d/$name — n/a log token" "tokens=n/a tools=n/a" "$flat"
  case "$flat" in *"never estimate"*|*"do not estimate"*) : ;; *) fail "S343/d/$name — no 'never estimate' / 'do not estimate'" ;; esac
  # (f) no false coverage claim.
  case "$flat" in *"preflight is a hook"*|*"hooks are installed"*) fail "S343/f/$name — claims hook coverage" ;; esac
  assert_contains "S343/f/$name — still not-installed" "runtime-hooks: not-installed" "$flat"
done

# (e) AGENTS.md is exactly what the generator produces from INSTRUCTIONS.md.
copy="$SANDBOX/repo"
mkdir -p "$copy/skills/role-contracts" "$copy/skills/model-choice"
cp -R "$TEST_REPO_ROOT/policy" "$TEST_REPO_ROOT/adapters" "$TEST_REPO_ROOT/lib" "$TEST_REPO_ROOT/generate-workflow-adapters.sh" "$TEST_REPO_ROOT/CHANGES.md" "$copy/"
cp "$TEST_REPO_ROOT/skills/role-contracts/SKILL.md" "$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md" "$copy/skills/role-contracts/"
cp "$TEST_REPO_ROOT/skills/model-choice/SKILL.md" "$copy/skills/model-choice/"
rm -f "$copy/adapters/codex/AGENTS.md"
if (cd "$copy" && ./generate-workflow-adapters.sh "$copy" >"$SANDBOX/gen.out" 2>"$SANDBOX/gen.err"); then
  cmp -s "$copy/adapters/codex/AGENTS.md" "$GEN" || fail "S343/e — adapters/codex/AGENTS.md differs from a fresh generator run (regenerate it)"
else
  fail "S343/e — the generator failed in a copy: $(cat "$SANDBOX/gen.out" "$SANDBOX/gen.err")"
fi

# --- S344(1): the dispatch-economy Runtime note ------------------------------
head5="$(awk '/^## Transcript extraction command/{on=1; n=0} on{print; n++; if(n>=6) exit}' "$SKILL")"
assert_contains "S344/1 — the extraction heading is unchanged" "## Transcript extraction command (local-only, advisory)" "$head5"
assert_contains "S344/1 — Runtime note names Claude" "Claude" "$head5"
assert_contains "S344/1 — Runtime note names Codex" "Codex" "$head5"
assert_contains "S344/1 — no Codex counterpart until verified" "verified" "$head5"
assert_contains "S344/1 — Runtime label" "Runtime" "$head5"

# --- S344(2): tokens=n/a through pipeline-log-fields.sh ------------------------
SCRIPT="$TEST_REPO_ROOT/pipeline-log-fields.sh"
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
[ -f "$FAKE_GH_BODY" ] && cat "$FAKE_GH_BODY"
exit 0
GH
chmod +x "$SANDBOX/bin/gh"
export FAKE_GH_BODY="$SANDBOX/body"
run() { printf '%s\n' "$1" > "$FAKE_GH_BODY"; out="$(PATH="$SANDBOX/bin:$PATH" "$SCRIPT" 532 2>&1)"; st=$?; }
base='Pipeline log'
for line in \
  '- Test agent=a1 model=m continued=no rule=OR13 tokens=n/a tools=n/a' \
  '- Test agent=a1 model=m continued=no rule=OR13 tokens=n/a tools=12' \
  '- Test agent=a1 model=m continued=no rule=OR13 tokens=90k tools=n/a' \
  '- Test agent=a1 model=m continued=yes rule=OR13 tokens=n/a tools=n/a' \
  '- Test agent=a1 model=m continued=no rule=OR13 tokens=N/A tools=N/A'; do
  run "$base
$line"
  [ "$st" -eq 0 ] || fail "S344/2 — exit $st for: $line"
  case "$out" in *"over the limit"*|*"missing reported size"*) fail "S344/2 — false report for '$line': $out" ;; esac
done
# (iv) unknown size for one agent, another agent over the limit with no reason.
run "$base
- Test agent=a-unknown model=m continued=no rule=OR13 tokens=n/a tools=n/a
- Test agent=a-big model=m continued=no rule=OR13 tokens=310k tools=120"
[ "$st" -eq 0 ] || fail "S344/2iv — exit $st"
assert_contains "S344/2iv — the big agent is reported" "a-big" "$out"
case "$out" in *a-unknown*) fail "S344/2iv — the unknown-size agent was reported: $out" ;; esac
# (vi) na and empty: never an over-limit line, exit 0.
for line in '- Test agent=a1 model=m continued=no rule=OR13 tokens=na tools=na' '- Test agent=a1 model=m continued=no rule=OR13 tokens= tools='; do
  run "$base
$line"
  [ "$st" -eq 0 ] || fail "S344/2vi — exit $st for: $line"
  case "$out" in *"over the limit"*) fail "S344/2vi — over-limit line for '$line': $out" ;; esac
done

test_done

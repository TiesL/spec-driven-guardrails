#!/usr/bin/env bash
# S181 — ./check rejects a CHANGES.md entry with no declared session path.
# Covers: F38
#
# Issue #371, A17, AC10. Seam: `check --no-tests` on a sandbox copy of this
# repo whose CHANGES.md is edited per case. The structural rule only: the
# `- **Reaches session:**` field is present, every value is in the closed
# vocabulary (none, always-loaded, session-context, hook, gate), each path
# exists, and each non-none path is named in at least one test/cases/*.sh.
# Whether `none` is HONEST for a given "Yes means" is Reviewer judgment and
# deliberately not asserted (A17).
#
# CHECK_SKIP_SHELLCHECK keeps each run to the structural checks.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

id="process-multi-agent-roles"

# mini <name> <reaches-of-subject>: a minimal project the real `check`
# accepts. Entry "subject-entry" gets the given Reaches session line
# (__DELETE__ = no line, __PROSE__ = only in prose); "other-entry" is always
# valid, so a failure must be pinned on the right entry.
mini() {
  local d="$SANDBOX/$1" value="$2"
  mkdir -p "$d/test/cases" "$d/skills/fixture" "$d/settings"
  cp "$TEST_REPO_ROOT/check" "$d/check"
  cp -R "$TEST_REPO_ROOT/lib" "$d/lib"
  echo '{}' > "$d/settings/session-hooks.json"
  printf 'ctx\n' > "$d/skills/fixture/CTX.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/skills/fixture/hook.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/skills/fixture/unnamed.sh"
  printf '# exercises skills/fixture/CTX.md and skills/fixture/hook.sh\n' > "$d/test/cases/named.sh"
  {
    echo "# Adoptable changes"
    echo
    echo "## subject-entry"
    echo
    echo "- **Question:** Does the subject apply?"
    echo "- **Default:** question"
    echo "- **Applies if:** always"
    echo "- **Yes means:** the subject applies."
    case "$value" in
      __DELETE__) ;;
      __PROSE__) echo "  Reaches session: none" ;;
      *) echo "- **Reaches session:** $value" ;;
    esac
    echo "- **PR:** https://github.com/example/example/pull/1"
    echo
    echo "---"
    echo
    echo "## other-entry"
    echo
    echo "- **Question:** Does the other apply?"
    echo "- **Default:** question"
    echo "- **Applies if:** always"
    echo "- **Yes means:** the other applies."
    echo "- **Reaches session:** none"
    echo "- **PR:** https://github.com/example/example/pull/2"
  } > "$d/CHANGES.md"
  echo "$d"
}

run_check() { # dir -> output in $out, status in $status
  out="$(CHECK_SKIP_SHELLCHECK=1 "$1/check" --no-tests "$1" 2>&1)"
  status=$?
}
expect_pass() { # label value
  local d
  d="$(mini "p$RANDOM" "$2")"
  run_check "$d"
  if [ "$status" -ne 0 ]; then fail "S181 — $1: ./check should pass, got exit $status: $out"; fi
}
expect_reject() { # label value [culprit]
  local d
  d="$(mini "r$RANDOM" "$2")"
  run_check "$d"
  if [ "$status" -eq 0 ]; then
    fail "S181 — $1: ./check should fail, got exit 0"
    return
  fi
  assert_contains "S181 — $1: the message names the entry" "subject-entry" "$out"
  assert_contains "S181 — $1: the message names the field" "Reaches session" "$out"
  case "$out" in
    *other-entry*) fail "S181 — $1: the valid other-entry was named in the failure: $out" ;;
  esac
  [ -z "${3:-}" ] || assert_contains "S181 — $1: the message names the culprit" "$3" "$out"
}

# Valid forms.
expect_pass "none" "none"
expect_pass "session-context with an existing, test-named path" "session-context: skills/fixture/CTX.md"
expect_pass "hook with an existing, test-named path" "hook: skills/fixture/hook.sh"
expect_pass "gate with an existing, test-named path" "gate: skills/fixture/hook.sh"
expect_pass "comma list of two valid values" "session-context: skills/fixture/CTX.md, gate: skills/fixture/hook.sh"

# Invalid forms, each pinned on the right entry.
expect_reject "field missing" __DELETE__
expect_reject "field only mentioned in prose" __PROSE__
expect_reject "empty value" ""
expect_reject "keyword outside the vocabulary" "telepathy: skills/fixture/CTX.md" "telepathy"
expect_reject "declared path does not exist" "session-context: skills/fixture/NO-SUCH-FILE-371.md" "NO-SUCH-FILE-371"
expect_reject "path exists but no test names it" "hook: skills/fixture/unnamed.sh" "unnamed.sh"
expect_reject "one bad path in an otherwise valid list" "session-context: skills/fixture/CTX.md, gate: skills/fixture/NO-SUCH-371.sh" "NO-SUCH-371"
expect_reject "a keyword with no path" "hook:" ""
expect_reject "a path with no keyword" "skills/fixture/CTX.md" ""

# This repo's own entries are all valid (backfill complete, every path
# exists and is named by a test), with the real check on a full copy.
c="$(sandbox_copy_repo full)"
run_check "$c"
if [ "$status" -ne 0 ]; then fail "S181 — the unmodified repo should pass ./check --no-tests, got exit $status: $out"; fi
# ... and the real entry loses its field -> rejected, by id.
awk -v id="## $id" '
  $0 == id { in_e = 1 }
  in_e && /^## / && $0 != id { in_e = 0 }
  in_e && /^- \*\*Reaches session:\*\*/ { next }
  { print }
' "$c/CHANGES.md" > "$c/CHANGES.new" && mv "$c/CHANGES.new" "$c/CHANGES.md"
run_check "$c"
[ "$status" -ne 0 ] || fail "S181 — real entry without the field: ./check should fail, got exit 0"
assert_contains "S181 — real entry without the field: names $id" "$id" "$out"

test_done

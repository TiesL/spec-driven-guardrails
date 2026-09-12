#!/usr/bin/env bash
# S37 — Predicate and parser logic lives in exactly one place.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

bibliotheek="$TEST_REPO_ROOT/lib/changes.sh"

if [ ! -f "$bibliotheek" ]; then
  fail "S37 — lib/changes.sh is missing"
  test_done
fi

# Then: the callers no longer contain their own predicate branch or parser
# header.
for script in adopt.sh pending-changes.sh; do
  pad="$TEST_REPO_ROOT/$script"

  for patroon in 'heeft-package-json)' 'heeft-deploy-script)'; do
    if grep -q -- "$patroon" "$pad"; then
      fail "S37 — $script contains its own predicate branch again: $patroon"
    fi
  done

  # The header of the parser: a case branch on '## '. The library should be
  # the only place that parses CHANGES.md line by line.
  if grep -q "'## '\*)" "$pad"; then
    fail "S37 — $script contains its own CHANGES.md parser again"
  fi

  grep -q 'lib/changes.sh' "$pad" || fail "S37 — $script does not source the library"
done

# And: the library does contain them. Without this check, the test would also
# pass if someone emptied out lib/changes.sh.
for patroon in 'heeft-package-json)' 'heeft-deploy-script)' "'## '\*)"; do
  grep -q -- "$patroon" "$bibliotheek" || fail "S37 — lib/changes.sh is missing: $patroon"
done

# And: both scripts actually call the library function too. The checks above
# search for text and therefore only see literal copies; logic rewritten in a
# different form — an if-chain instead of a case — would slip through
# unnoticed. This check is behavioral: the function is instrumented and it is
# confirmed that it was called.
sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
log="$SANDBOX/aanroepen.txt"

cat >> "$repo/lib/changes.sh" <<INSTR

# --- for S37 only: records that this function was called ---
predicate_true() {
  printf '%s\n' "\$1" >> "$log"
  case "\$1" in
    altijd) return 0 ;;
    heeft-package-json) [ -f "\$2/package.json" ] ;;
    heeft-deploy-script)
      [ -f "\$2/package.json" ] && grep -q '"deploy"[[:space:]]*:' "\$2/package.json" ;;
    *) return 1 ;;
  esac
}
INSTR

project="$(fresh_project target-project)"

: > "$log"
SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$project" >/dev/null 2>&1
if [ ! -s "$log" ]; then
  fail "S37 — adopt.sh did not call predicate_true from the library"
fi

: > "$log"
"$repo/pending-changes.sh" "$project" >/dev/null 2>&1
if [ ! -s "$log" ]; then
  fail "S37 — pending-changes.sh did not call predicate_true from the library"
fi

test_done

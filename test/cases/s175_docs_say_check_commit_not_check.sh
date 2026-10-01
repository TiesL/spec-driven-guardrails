#!/usr/bin/env bash
# S175 — PRD and ARCHITECTURE no longer say the pre-commit hook runs ./check (#378, review finding 4, AC10).
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

r="$TEST_REPO_ROOT"
bt='`'
flat() { tr '\n' ' ' | tr -s ' '; }

# PRD: the #377 pre-commit paragraph (from "As of issue #377, the `pre-commit` hook" to the blank line).
prd="$(awk '/^As of issue #377, the `pre-commit` hook/{f=1} f&&/^$/{exit} f' "$r/PRD.md" | flat)"
[ -n "$prd" ] || fail "S175 — PRD has no pre-commit 'As of issue #377' paragraph"
case "$prd" in *"${bt}./check${bt}"*) fail "S175 — PRD #377 paragraph still says the hook runs/skips ./check" ;; esac
case "$prd" in *check-commit*) : ;; *) fail "S175 — PRD #377 paragraph does not name check-commit" ;; esac

# ARCHITECTURE A19: caller 1 and the 'Violated when' bullet.
a19="$(awk '/^### A19 /{f=1;next} /^### /{f=0} f' "$r/ARCHITECTURE.md")"
[ -n "$a19" ] || fail "S175 — ARCHITECTURE has no A19 section"
caller1="$(printf '%s\n' "$a19" | awk '/^  1\. `hooks\/pre-commit`/{f=1} /^  2\. /{f=0} f' | flat)"
[ -n "$caller1" ] || fail "S175 — could not find A19 caller 1 (pre-commit)"
case "$caller1" in *"${bt}./check${bt}"*) fail "S175 — A19 caller 1 still says the hook clears for / skips the ./check child" ;; esac
case "$caller1" in *check-commit*) : ;; *) fail "S175 — A19 caller 1 does not name check-commit" ;; esac
violated="$(printf '%s\n' "$a19" | awk '/^- \*\*Violated when/{f=1} /^- \*\*Rejected/{f=0} f' | flat)"
[ -n "$violated" ] || fail "S175 — could not find A19 'Violated when'"
case "$violated" in *"${bt}./check${bt} child"*) fail "S175 — A19 'Violated when' still says the ./check child" ;; esac

test_done

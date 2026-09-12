#!/usr/bin/env bash
# S32 — Every active entry has a PR linkback.
# Covers: F15

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# AC2 — this repo itself, unchanged: every active entry already has a
# **PR:** field. check must not raise an error about that.
repo_good="$(sandbox_copy_repo good)"
if ! "$repo_good/check" --no-tests "$repo_good" >/dev/null 2>&1; then
  output="$("$repo_good/check" --no-tests "$repo_good" 2>&1)"
  case "$output" in
    *"PR:"*) fail "S32/AC2 — this repo's own CHANGES.md incorrectly gave a PR linkback error: $output" ;;
    *) : ;; # other, unrelated failure — not this scenario's concern
  esac
fi

# AC1/AC3 — an entry without a **PR:** field fails, with the ID in the message.
repo_broken="$(sandbox_copy_repo broken)"
# Remove process-prd's PR line; the rest of the file stays intact.
sed -i.bak '/^- \*\*PR:\*\* https:\/\/github\.com\/TiesL\/claude-workflow\/pull\/1$/d' "$repo_broken/CHANGES.md"
rm -f "$repo_broken/CHANGES.md.bak"

output="$("$repo_broken/check" --no-tests "$repo_broken" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S32/AC1,AC3 — CHANGES.md without a PR field gave exit 0"
assert_contains "S32 — the ID of the broken entry is in the message" "process-prd" "$output"

# AC4 — an archived entry keeps its linkback; check must not complain about it
# as long as it stays intact (this repo's CHANGES-ARCHIEF.md, unchanged).
case "$output" in
  *"prd-testscenarios-issue-templates"*)
    fail "S32/AC4 — the archived entry was incorrectly flagged: $output" ;;
esac

test_done

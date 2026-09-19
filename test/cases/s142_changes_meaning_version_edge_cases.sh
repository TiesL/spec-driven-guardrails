#!/usr/bin/env bash
# S142 — changes_meaning_version's field extraction handles the edge
# cases found during PR #261's pre-merge-review, on synthetic CHANGES.md
# fixtures (parsing logic, not this project's own live registry data).
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

fixture="$SANDBOX/changes-fixture.md"
cat > "$fixture" <<'EOF'
## normal-entry

- **Applies if:** always
- **Meaning version:** 2 — some reason
- **Yes means:** stuff

## continuation-entry

- **Applies if:** always
- **Meaning version:**
  3 — reason on next line
- **Yes means:** stuff

## double-space-entry

- **Applies if:** always
-  **Meaning version:** 4 — reason
- **Yes means:** stuff

## leading-space-entry

- **Applies if:** always
 - **Meaning version:** 5 — reason
- **Yes means:** stuff

## no-version-entry

- **Applies if:** always
- **Yes means:** stuff

## malformed-entry

- **Applies if:** always
- **Meaning version:** abc — a typo, not a number
- **Yes means:** stuff

## issue-number-in-prose-entry

- **Applies if:** always
- **Meaning version:**
  #244 added a thing, bumping this
- **Yes means:** stuff
EOF

# shellcheck source=../../lib/changes.sh
. "$TEST_REPO_ROOT/lib/changes.sh"

check_version() {
  local id="$1" expected="$2" actual
  actual="$(changes_meaning_version "$id" "$fixture")"
  [ "$actual" = "$expected" ] || fail "S142 — $id: expected \"$expected\", got \"$actual\""
}

check_version "normal-entry" "2"
check_version "continuation-entry" "3"
check_version "double-space-entry" "4"
check_version "leading-space-entry" "5"
check_version "no-version-entry" "1"

# Malformed (field present, non-numeric content) is distinct from absent
# — empty, not silently defaulted to 1, so a caller's own validation can
# actually catch it (#261 round 2: the two used to collapse to the same
# default, making that validation unreachable in practice).
malformed="$(changes_meaning_version "malformed-entry" "$fixture")"
[ -z "$malformed" ] || fail "S142 — malformed-entry: expected empty (malformed, not defaulted), got \"$malformed\""

# A digit elsewhere in a continuation line's prose (an issue number) must
# not be misread as the version — the continuation-line check is anchored
# at that line's own start, not "contains a digit anywhere" (#261 round 2).
issue_number_prose="$(changes_meaning_version "issue-number-in-prose-entry" "$fixture")"
[ "$issue_number_prose" = "1" ] || fail "S142 — issue-number-in-prose-entry: expected 1 (field effectively absent), got \"$issue_number_prose\""

test_done

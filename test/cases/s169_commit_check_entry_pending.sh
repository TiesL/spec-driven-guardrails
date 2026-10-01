#!/usr/bin/env bash
# S169 — ci-commit-check is pending only for projects that have a check, and is never auto-seeded (#378, AC11).
# Covers: F2, F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: an adopted project WITH an executable check, and one WITHOUT.
with="$(fresh_project with-check)"
printf '#!/usr/bin/env bash\necho checked\n' > "$with/check"
chmod +x "$with/check"
adopt "$with"
without="$(fresh_project without-check)"
adopt "$without"

# Then: the entry is pending for the project with a check ...
pending_with="$(pending_ids "$with")"
pending_without="$(pending_ids "$without")"
grep -qx 'ci-commit-check' <<<"$pending_with" \
  || fail "S169 — ci-commit-check is not pending for an adopted project that has a check"
# ... and not for the project without one.
if grep -qx 'ci-commit-check' <<<"$pending_without"; then
  fail "S169 — ci-commit-check is pending for a project without a check"
fi

# And: Default is question, so adopt.sh never seeds it as an answered row.
seeded_with="$(seeded_ids "$with")"
if grep -qx 'ci-commit-check' <<<"$seeded_with"; then
  fail "S169 — adopt.sh seeded ci-commit-check although its Default is question"
fi

# And: the entry carries the fields the design fixes (id, default, predicate, PR link).
entry="$(awk '/^## ci-commit-check$/{f=1;next} /^## /{f=0} f' "$TEST_REPO_ROOT/CHANGES.md")"
[ -n "$entry" ] || fail "S169 — CHANGES.md has no '## ci-commit-check' entry"
case "$entry" in *"**Default:** question"*) : ;; *) fail "S169 — entry Default is not 'question'" ;; esac
case "$entry" in *"**Applies if:** has-check-command"*) : ;; *) fail "S169 — entry predicate is not has-check-command" ;; esac
case "$entry" in *"check-commit"*) : ;; *) fail "S169 — entry does not name check-commit" ;; esac

# And: answering the row clears it (the mechanism works end to end).
printf '\n| ci-commit-check | no | 2026-10-01 | not declaring one |\n' >> "$with/WORKFLOW-ADOPTION.md"
pending_after="$(pending_ids "$with")"
if grep -qx 'ci-commit-check' <<<"$pending_after"; then
  fail "S169 — ci-commit-check stays pending after the project answered it"
fi

test_done

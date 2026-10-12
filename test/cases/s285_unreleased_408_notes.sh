#!/usr/bin/env bash
# S285 — Unreleased carries the #408 release notes, with compatibility terms and pending markers (#420, AC4a, AC5, AC6).
# Covers: F15

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

r="$TEST_REPO_ROOT"
unrel="$(changelog_section "$r/CHANGELOG.md" '## Unreleased')"
[ -n "$unrel" ] || fail "S285 — CHANGELOG has no non-empty '## Unreleased' section"

mentions() { grep -Eq "#$2([^0-9]|\$)" <<<"$1"; }

for n in 410 414 415 422 423 424 425 426 427 428 429; do
  mentions "$unrel" "$n" || fail "S285 — Unreleased does not mention #$n"
done

# A number and its role on one line.
line_with() { local l; l="$(grep -E "#$1([^0-9]|\$)" <<<"$unrel")"; grep -iq -- "$2" <<<"$l"; }
line_with 430 'acceptance' || fail "S285 — no Unreleased line names #430 as acceptance evidence"
line_with 420 'documentation' || fail "S285 — no Unreleased line names #420 as documentation closure"
line_with 409 'deferred' || fail "S285 — no Unreleased line has #409 with 'deferred'"
line_with 455 'paused' || fail "S285 — no Unreleased line has #455 with 'paused'"
l455="$(grep -E '#455([^0-9]|$)' <<<"$unrel")"
grep -q 'main' <<<"$l455" || fail "S285 — no Unreleased line has #455 with 'main'"
for n in 400 413 421; do
  line_with "$n" 'absorbed' || fail "S285 — no Unreleased line has #$n with 'absorbed'"
done

for t in 'fresh Reviewers' 'finding-class loop-back' 'override' 'decision table' 'risk notes' \
         'macOS CI' 'shared Markdown handling' 'effort removal' 'v2' 'emitter' 'migrated callers' \
         'old-parser removal'; do
  grep -qF -- "$t" <<<"$unrel" || fail "S285 — Unreleased does not contain the term '$t'"
done

# Meaning versions are read from CHANGES.md, never hard-coded.
meaning_version() {
  awk -v h="## $1" '
    /^## / { f = ($0 == h); next }
    f && /^- \*\*Meaning version:\*\*/ { sub(/^- \*\*Meaning version:\*\* */, ""); print $1; exit }
  ' "$r/CHANGES.md"
}
for skill in quality-review-before-merge process-multi-agent-roles; do
  v="$(meaning_version "$skill")"
  if [ -z "$v" ]; then
    fail "S285 — CHANGES.md has no 'Meaning version:' under '## $skill'"
  else
    sl="$(grep -F "$skill" <<<"$unrel")"
    grep -qF "meaning version $v" <<<"$sl" \
      || fail "S285 — Unreleased has no '$skill' with 'meaning version $v' (number read from CHANGES.md)"
  fi
done

grep -qF -- '--effort' <<<"$unrel" || fail "S285 — Unreleased does not mention --effort"
grep -qF 'to be confirmed by #430' <<<"$unrel" || fail "S285 — Unreleased has no 'to be confirmed by #430' marker"

test_done

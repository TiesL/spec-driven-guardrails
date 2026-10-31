#!/usr/bin/env bash
# S285 — the v0.4.0 section carries the #408 release notes and observed acceptance results (#420 AC4a/AC5/AC6; #474 AC2/AC3/AC7).
# Covers: F15

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

r="$TEST_REPO_ROOT"
unrel="$(changelog_section "$r/CHANGELOG.md" '## v0.4.0')"
[ -n "$unrel" ] || fail "S285 — CHANGELOG has no non-empty '## v0.4.0' section"

mentions() { grep -Eq "#$2([^0-9]|\$)" <<<"$1"; }

for n in 410 414 415 422 423 424 425 426 427 428 429; do
  mentions "$unrel" "$n" || fail "S285 — v0.4.0 section does not mention #$n"
done

# A number and its role on one line.
line_with() { local l; l="$(grep -E "#$1([^0-9]|\$)" <<<"$unrel")"; grep -iq -- "$2" <<<"$l"; }
line_with 430 'acceptance' || fail "S285 — no v0.4.0 section line names #430 as acceptance evidence"
line_with 420 'documentation' || fail "S285 — no v0.4.0 section line names #420 as documentation closure"
line_with 409 'deferred' || fail "S285 — no v0.4.0 section line has #409 with 'deferred'"
line_with 455 'paused' || fail "S285 — no v0.4.0 section line has #455 with 'paused'"
l455="$(grep -E '#455([^0-9]|$)' <<<"$unrel")"
grep -q 'main' <<<"$l455" || fail "S285 — no v0.4.0 section line has #455 with 'main'"
for n in 400 413 421; do
  line_with "$n" 'absorbed' || fail "S285 — no v0.4.0 section line has #$n with 'absorbed'"
done

for t in 'fresh Reviewers' 'finding-class loop-back' 'override' 'decision table' 'risk notes' \
         'macOS CI' 'shared Markdown handling' 'effort removal' 'v2' 'emitter' 'migrated callers' \
         'old-parser removal'; do
  grep -qF -- "$t" <<<"$unrel" || fail "S285 — v0.4.0 section does not contain the term '$t'"
done

# Meaning versions: the oracle is the set of questions whose "Meaning version:"
# differs between v0.3.0's CHANGES.md and the working tree (a question absent
# or unnumbered then counts as changed). Numbers are never hard-coded.
meaning_versions() {
  awk '
    /^## / { h = substr($0, 4); next }
    h != "" && /^- \*\*Meaning version:\*\*/ { v = $0; sub(/^- \*\*Meaning version:\*\* */, "", v); sub(/[^0-9].*$/, "", v); print h " " v; h = "" }
  '
}
entry="$(awk '
  /^- \*\*Compatibility and limits \(#408\)\.\*\*/ { f = 1; print; next }
  f && /^- \*\*/ { exit }
  f
' <<<"$unrel")"
[ -n "$entry" ] || fail "S285 — no '- **Compatibility and limits (#408).**' entry in v0.4.0 section"

if ! git -C "$r" rev-parse -q --verify 'refs/tags/v0.3.0^{commit}' >/dev/null 2>&1; then
  fail "S285 — tag v0.3.0 is not in this clone; the macOS and Linux CI checkouts need fetch-depth: 0 to have it"
else
  old="$(git -C "$r" show v0.3.0:CHANGES.md | meaning_versions)"
  new="$(meaning_versions <"$r/CHANGES.md")"
  changed=""
  n_changed=0
  while IFS=' ' read -r q v; do
    [ -n "$q" ] || continue
    ov="$(awk -v q="$q" '$1 == q { print $2; exit }' <<<"$old")"
    if [ "$ov" != "$v" ]; then
      changed="$changed $q"; n_changed=$((n_changed + 1))
      grep -qF -- "$q" <<<"$entry" \
        || fail "S285 — compatibility entry does not name '$q' (meaning version changed since v0.3.0)"
      ql="$(grep -F -- "$q" <<<"$entry")"
      grep -qE -- "meaning version $v([^[:alnum:]_]|$)" <<<"$ql" \
        || fail "S285 — compatibility entry has no '$q' line with 'meaning version $v' (read from CHANGES.md)"
    fi
  done <<<"$new"
  [ "$n_changed" -gt 0 ] || fail "S285 — oracle found no changed meaning versions since v0.3.0"
  stated="$(python3 -c '
import re, sys
pattern = r"(?<![\w])(?:one|two|three|four|five|six|seven|eight|nine|[0-9]+) (?:answers|questions)(?![\w])"
for match in re.finditer(pattern, sys.stdin.read(), re.I):
    print(match.group().split()[0].lower())
' <<<"$entry")"
  [ -n "$stated" ] || fail "S285 — compatibility entry states no count of answers/questions to re-confirm"
  while IFS= read -r count; do
    [ -n "$count" ] || continue
    num="$count"; i=0
    for w in one two three four five six seven eight nine; do i=$((i + 1)); [ "$w" = "$count" ] && num="$i"; done
    # Compare decimal values, including leading zeroes, without shell octal parsing.
    awk -v n="$num" -v expected="$n_changed" 'BEGIN { exit !(n + 0 == expected) }' \
      || fail "S285 — compatibility entry states $count answers/questions; $n_changed changed:$changed"
  done <<<"$stated"
fi

# Accepted limits are named, not pointed at.
names="$(sed -n 's/^#     \* \([a-z][a-z0-9-]*\)[ :(].*/\1/p' "$r/lib/markdown.sh")"
[ -n "$names" ] || fail "S285 — no '#     * <name>:' limit lines found in lib/markdown.sh header"
while IFS= read -r nm; do
  [ -n "$nm" ] || continue
  grep -qF -- "$nm" <<<"$entry" || fail "S285 — compatibility entry does not name the reader limit '$nm'"
done <<<"$names"
grep -qF -- 'one-definition' <<<"$entry" || fail "S285 — compatibility entry does not name the one-definition lint"
grep -qiF -- 'evade' <<<"$entry" || fail "S285 — compatibility entry does not say the lint can be evaded"
grep -qiF -- 'evade' "$r/lib/one-definition-lint.py" \
  || fail "S285 — lib/one-definition-lint.py docstring no longer says the lint can be evaded"
# Same whole-word negator list as S285's scenario, within one sentence.
negators='not|no|never|neither|cannot|outside'
while IFS= read -r l; do
  [ -n "$l" ] || continue
  grep -Eiq 'reader|lint|commonmark' <<<"$l" || continue
  while IFS= read -r sentence; do
    grep -Eiq '(^|[^[:alnum:]_])(complete|exhaustive|guarantee)([^[:alnum:]_]|$)' <<<"$sentence" || continue
    grep -Eiq "(^|[^[:alnum:]_])($negators)([^[:alnum:]_]|$)" <<<"$sentence" \
      || fail "S285 — completeness claim in compatibility entry: $sentence"
  done < <(printf '%s\n' "$l" | tr '.!?' '\n')
done <<<"$entry"

grep -qF -- '--effort' <<<"$unrel" || fail "S285 — v0.4.0 section does not mention --effort"
if grep -qF 'to be confirmed by #430' <<<"$unrel"; then
  fail "S285 — v0.4.0 section still has the #430 placeholder"
fi
grep -qiE 'scratch #5 and #14.* (blocked|blocking) .*missing stages' <<<"$entry" \
  || fail "S285 — compatibility entry does not say scratch #5 and #14 are blocked for missing stages"
grep -qiE 'scratch #10.*non-blocking.*both gates' <<<"$entry" \
  || fail "S285 — compatibility entry does not say scratch #10 is non-blocking under both gates"
grep -qiE 'warning.*hook transcript.*did not reach.*agent.*command output' <<<"$entry" \
  || fail "S285 — compatibility entry does not distinguish hook visibility from agent command output"

# Released-state wording (#474 AC3): the section is no proposal and not unreleased.
for t in 'version is not chosen' 'proposal only' 'unreleased'; do
  grep -qiF -- "$t" <<<"$unrel" && fail "S285 — v0.4.0 section still says '$t'"
done

# Release-as-candidate wording (#474 review round 1): determiner/compound phrases that can only mean the release itself.
# The bare word stays allowed: the section uses "candidate" for review-record candidates (#428).
for t in 'the candidate' 'this candidate' 'release candidate' 'candidate release'; do
  grep -qiF -- "$t" <<<"$unrel" && fail "S285 — v0.4.0 section still says '$t' (release-candidate wording)"
done

test_done

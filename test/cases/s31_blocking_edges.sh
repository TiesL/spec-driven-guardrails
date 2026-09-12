#!/usr/bin/env bash
# S31 — Blocking edges are present in both issue templates.
#
# The fields must be machine-readable, not just present: at the start of a
# line and in the `**Field:**` form the existing issues already use. A
# variant like `- Blocked by:` reads the same to a human and is something
# different for a grep, and then the convention doesn't yield a graph, just a
# feeling.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

repo="$TEST_REPO_ROOT"

# The template without its HTML comments. A field that accidentally ends up
# inside `<!-- ... -->` is still there as far as grep is concerned, but never
# reaches the issue — then the template hides exactly what it's supposed to
# prescribe.
zonder_commentaar() {
  awk '/<!--/ { in_c = 1 } !in_c; /-->/ { in_c = 0 }' "$1"
}

for sjabloon in work-item epic; do
  pad="$repo/templates/ISSUE_TEMPLATE/$sjabloon.md"
  [ -f "$pad" ] || fail "S31 — $sjabloon.md is missing"

  zichtbaar="$(zonder_commentaar "$pad")"

  for veld in "Blocked by" "Blocks"; do
    regel="$(printf '%s\n' "$zichtbaar" | grep "^\*\*$veld:\*\*" || true)"

    [ -n "$regel" ] \
      || fail "S31 — $sjabloon.md has no '**$veld:**' at the start of a line, outside comments"

    # AC2: the field must be able to carry a `#<number>` token. The template
    # shows that with a bare `#`; the check requires the form, not a made-up
    # number. Both fields, not just the first — a check that only sees one of
    # two fields covers half of what it claims to.
    case "$regel" in
      *"#"*) ;;
      *) fail "S31 — $sjabloon.md: '$regel' does not show that a #-number belongs in it" ;;
    esac
  done
done

# AC3: adopt.sh refreshes the templates in a project, even if an older
# version is already there. Without that, the convention stays stuck in this
# repo.
sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project met-oud-sjabloon)"
mkdir -p "$project/.github/ISSUE_TEMPLATE"
echo "verouderd sjabloon zonder velden" > "$project/.github/ISSUE_TEMPLATE/work-item.md"

adopt "$project"

grep -q '^\*\*Blocked by:\*\*' "$project/.github/ISSUE_TEMPLATE/work-item.md" \
  || fail "S31 — adopt.sh did not refresh the outdated template"

test_done "S31"

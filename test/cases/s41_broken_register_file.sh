#!/usr/bin/env bash
# S41 — A broken register file does not silently disappear.
# Covers: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

valid_block() {
  cat <<'MD'
## Question

Is this characteristic relevant?

## Yes means

`PRD.md` answers the "Test" subsection.

## Guidance

What is this about?
MD
}

# Each case is a fully usable file with a single defect. Without a check,
# such a file disappears from all consumers at once, and then the
# drift check sees nothing: both sides are missing it after all.
for case in no-order name-differs; do
  repo="$SANDBOX/repo-$case"
  mkdir -p "$repo"
  (cd "$TEST_REPO_ROOT" && tar --exclude='./.git' -cf - .) | (cd "$repo" && tar -xf -)

  case "$case" in
    no-order)
      target="$repo/nfr/spec-test.md"
      { printf -- '---\nid: spec-test\nheading: Test\ndefault: yes\napplies-if: always\nproduction-gate: no\nstatus: active\n---\n\n'
        valid_block; } > "$target" ;;
    name-differs)
      target="$repo/nfr/spec-wrongly-named.md"
      { printf -- '---\nid: spec-test\nheading: Test\norder: 16\ndefault: yes\napplies-if: always\nproduction-gate: no\nstatus: active\n---\n\n'
        valid_block; } > "$target" ;;
  esac

  output="$("$repo/check" --no-tests "$repo" 2>&1)"
  status=$?

  if [ "$status" -eq 0 ]; then
    fail "S41 — check succeeded on a broken register file ($case)"
  fi
  case "$output" in
    *nfr/spec-*) ;;
    *) fail "S41 — the message does not name the file in question ($case)" ;;
  esac
done

# CRLF line endings must not make a file invisible. That is a separate
# requirement: such a file is fine content-wise, so it should just be
# included — not silently skipped because the frontmatter is not recognized.
repo="$SANDBOX/repo-crlf"
mkdir -p "$repo"
(cd "$TEST_REPO_ROOT" && tar --exclude='./.git' -cf - .) | (cd "$repo" && tar -xf -)
{ printf -- '---\nid: spec-test\nheading: Test\norder: 16\ndefault: yes\napplies-if: always\nproduction-gate: no\nstatus: active\n---\n\n'
  valid_block; } | sed 's/$/\r/' > "$repo/nfr/spec-test.md"

# shellcheck source=../../lib/nfr.sh
. "$repo/lib/nfr.sh"

[ "$(nfr_field "$repo/nfr/spec-test.md" id)" = "spec-test" ] \
  || fail "S41 — CRLF file: the id is not being read"
[ "$(nfr_field "$repo/nfr/spec-test.md" order)" = "16" ] \
  || fail "S41 — CRLF file: the order is not being read"

block="$SANDBOX/block-crlf.txt"
nfr_block "$repo/nfr" > "$block"
grep -q 'spec-test' "$block" || fail "S41 — CRLF file disappeared from the generated block"

test_done

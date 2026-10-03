#!/usr/bin/env bash
# S192 — no live text still demands a different Review model or a
# same-model-exception; the old rule survives only as history or as
# legacy-marker handling.
# Covers: F11
#
# Issue #392, R1/R6, AC2/AC5. Seam: the repo's documents and scripts, read
# as text. Markdown: a unit (paragraph, list item or table row) that states the old requirement ("a
# different model from/than", "genuinely different", "different model is
# required", "must use a different model") or mentions same-model-exception
# must also say it is history or legacy (#392, reversed, history, legacy,
# superseded, replaced, no longer, retired). Scripts: same-model-exception
# may appear in comments only (neither script parses it any more) and the
# file must call it legacy/ignored. Excluded: wip/, CHANGES-ARCHIEF.md,
# CHANGELOG.md (history), test fixtures and test cases (they exercise the
# legacy attribute on purpose; their behaviour is S189/S190/S130/S150).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

root="$TEST_REPO_ROOT"
req='genuinely different|different model (from|than)|different model is required|must (be|use|run on) a different model|requires? (a )?different model|same-model-exception'
allow='#392|legacy|history|historical|reversed|superseded|replaced|no longer|retired'

# unit scan: a unit is a paragraph, a list item (a line starting with "- " or
# "* ", plus its wrapped continuation lines) or a table row; prints
# "<file>: <start of unit>" for each offender. Units this small keep a
# "#392" in one CHANGES.md field from excusing leftover old text in another.
scan() {
  awk -v req="$req" -v allow="$allow" '
    function flush(   t, p) {
      if (unit == "") return
      t = tolower(unit)
      if (t ~ req && t !~ allow) {
        p = unit; gsub(/\n/, " ", p)
        print FILENAME ": " substr(p, 1, 110)
      }
      unit = ""
    }
    /^[[:space:]]*$/ { flush(); next }
    /^[[:space:]]*([-*][[:space:]]|\||#)/ { flush() }
    { unit = unit $0 "\n" }
    END { flush() }
  ' "$1"
}

files="$(find "$root" -name '*.md' \
  -not -path '*/.git/*' -not -path '*/wip/*' -not -path '*/test/*' \
  -not -name 'CHANGES-ARCHIEF.md' -not -name 'CHANGELOG.md' | sort)"
[ -n "$files" ] || fail "S192 — found no markdown files to scan"

while IFS= read -r f; do
  [ -n "$f" ] || continue
  off="$(scan "$f")"
  [ -z "$off" ] || fail "S192/AC2 — live text still carries the old Review rule (a paragraph with no history/legacy note): ${off//$root\//}"
done <<<"$files"

# the pre-#392 snapshot of CHANGES.md is a frozen copy kept in sync with
# CHANGES.md (S90), so it is checked like CHANGES.md itself
off="$(scan "$root/test/fixtures/baseline/CHANGES.md.snapshot")"
[ -z "$off" ] || fail "S192/AC2 — test/fixtures/baseline/CHANGES.md.snapshot still carries the old Review rule: ${off//$root\//}"

# scripts: the legacy attribute is never parsed
for s in "$root/compliance-evidence.sh" "$root/skills/pre-merge-review/model-record-gate.sh" "$root/lib/model-record.sh"; do
  [ -f "$s" ] || continue
  code="$(grep -n 'same-model-exception' "$s" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
  [ -z "$code" ] || fail "S192/AC5 — ${s#"$root"/} refers to same-model-exception outside a comment (it must not parse or print it): $code"
  if grep -q 'same-model-exception' "$s" && ! grep -qiE 'legacy|ignored' "$s"; then
    fail "S192/AC5 — ${s#"$root"/} mentions same-model-exception but never calls it legacy/ignored"
  fi
  if grep -qE 'different or at-least-as-capable model, or carries an explicit exception' "$s"; then
    fail "S192/AC2 — ${s#"$root"/} still has the old gate-2 row label"
  fi
done

test_done

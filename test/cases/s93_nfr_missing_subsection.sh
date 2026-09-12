#!/usr/bin/env bash
# S93 — A yes-answered spec-* NFR without its PRD.md subsection is warned about.
# Covers: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
project="$SANDBOX/project"
mkdir -p "$project"

# Given: spec-security answered "yes" with no PRD.md subsection at all;
# spec-privacy answered "yes" too, but with a Notes column explicitly
# pointing at an open issue (tennis-invoicing's #17 shape) — AC3 requires
# the warning fires anyway, since the point is to no longer depend on a
# human remembering to add that note; spec-data-integrity answered "yes"
# *with* its subsection present, so no warning; spec-testability answered
# "no", so no warning regardless of what PRD.md has.
cat > "$project/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| spec-security | yes | 2026-01-01 | van toepassing |
| spec-privacy | yes | 2026-01-01 | subsections not all written yet — see issue #17 |
| spec-data-integrity | yes | 2026-01-01 | van toepassing |
| spec-testability | no | 2026-01-01 | niet van toepassing |
EOF

cat > "$project/PRD.md" <<'EOF'
# PRD

## Non-functional characteristics

### Data integrity

Filled in.
EOF

uitvoer="$(
  # shellcheck source=../../lib/nfr.sh
  . "$repo/lib/nfr.sh"
  nfr_missing_subsection "$repo/nfr" "$project"
)"

# Then: both yes-answered, subsection-less rows are named...
assert_contains "S93 — spec-security is warned about" "spec-security" "$uitvoer"
assert_contains "S93 — the missing Security subsection is named" "Security" "$uitvoer"
assert_contains "S93 — spec-privacy is warned about, despite its Notes" "spec-privacy" "$uitvoer"

# ...but the one with a real subsection isn't...
if printf '%s\n' "$uitvoer" | grep -q 'spec-data-integrity'; then
  fail "S93 — spec-data-integrity has its subsection and should not be warned about"
fi

# ...and neither is the "no"-answered one.
if printf '%s\n' "$uitvoer" | grep -q 'spec-testability'; then
  fail "S93 — spec-testability is answered 'no' and should not be warned about"
fi

# And: this is wired into `check` itself, as a non-blocking warning (the
# issue's own proposal: "explicit warning, not a hard error" — a
# freshly-answered "yes" deserves a short, visible grace period, not an
# immediate red build). Remove just the Security subsection from a full
# sandboxed repo copy — real WORKFLOW-ADOPTION.md there already answers
# spec-security "yes" — and confirm `check` still exits 0 but surfaces
# the warning.
zonder_security="$(awk '
  /^### Security$/ { skip = 1 }
  /^### Data integrity$/ { skip = 0 }
  !skip { print }
' "$repo/PRD.md")"
printf '%s\n' "$zonder_security" > "$repo/PRD.md"

check_uitvoer="$("$repo/check" --no-tests "$repo" 2>&1)"
check_status=$?
[ "$check_status" -eq 0 ] || fail "S93 — check must not hard-fail on a missing NFR subsection: $check_uitvoer"
assert_contains "S93 — check surfaces the warning" "spec-security" "$check_uitvoer"

test_klaar

#!/usr/bin/env bash
# R2 — Openstaande vragen na verse adoptie.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een vers project, direct na adoptie.
project="$(vers_project leeg)"
adopteer "$project"

# When: pending-changes.sh draait.
gekregen="$SANDBOX/gekregen.txt"
openstaande_ids "$project" > "$gekregen"

# Then: exact deze 7 ID's, in willekeurige volgorde.
verwacht="$SANDBOX/verwacht.txt"
cat > "$verwacht" <<'IDS'
proces-issue-tracking
spec-compliance
spec-kostenbeheersing
spec-performance-schaal
spec-portability
spec-usability
test-integratie
IDS

assert_ids_gelijk "R2" "$verwacht" "$gekregen"

test_klaar

#!/usr/bin/env bash
# test/fixtures/review-rounds-lib-helpers.sh — helpers for S250 (#426, V5 of #411):
# the seam of lib/review-rounds.sh. Source after test/lib.sh and sandbox_create.
# Not a test case. Bash 3.2, BWK awk, BSD tools: no declare -A, no mapfile, no GNU flags.
#
# THE AGREED SIGNATURE (A37; recorded here and in TEST-SCENARIOS.md S250; the
# stub lib/review-rounds.sh carries the same text):
#
#   rr_rounds        reads rows on STDIN, one per body, tab separated:
#                        <created_at> TAB <source> TAB <url> TAB <body>
#                    source is comment | issue | review; url is "-" when unknown;
#                    the body holds its newlines as U+0001 (\001). A blank line is
#                    ignored. Sourcing lib/review-rounds.sh alone gives rr_rounds
#                    (the file sources lib/model-record.sh itself).
#                    Prints one row per body that is a Review round, plus one per
#                    body whose first candidate is a Planning record AFTER at least
#                    one round, in time order, tab separated, six fields:
#                        R TAB <n> TAB <created_at> TAB <source> TAB <url> TAB <body>
#                        P TAB <n> TAB <created_at> TAB <source> TAB <url> TAB <body>
#                    R: n is the round's 1-based number. P: n is the number of the
#                    latest round before it. The body field is the input body field
#                    byte for byte (still \001-encoded). Order: created_at (ISO 8601
#                    UTC, compared as text), then source (issue, comment, review),
#                    then input order.
#                    Status 0, also for no rows and for no round. When a read fails
#                    (an external tool, a `[[ =~ ]]` of 2): prints NOTHING on stdout,
#                    one line on stderr, returns non-zero; a caller never sees a
#                    failure as "no round".
#   A round (A37): one body whose FIRST candidate (an ok or near-miss
#   model-record line; a quoted one is not a candidate) is stage=Review; or a body
#   with no candidate at all and a live `pre-merge-review:done sha=<40 hex>` marker.
#   The records are read through rec_scan model-record <body>.

# shellcheck disable=SC2034  # read by the cases

# shellcheck source-path=SCRIPTDIR
# shellcheck source=record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/record-helpers.sh"

RRL_TAB=$'\t'
RRL_ONE=$'\001'

# rrl_init <label>: sources lib/review-rounds.sh ALONE and finds the modes.
# Returns 1 (the case ends) when the lib or the function is missing.
rrl_init() {
  local label="$1" lib="$TEST_REPO_ROOT/lib/review-rounds.sh"
  if [ ! -f "$lib" ]; then
    fail "$label — lib/review-rounds.sh is missing"
    return 1
  fi
  # shellcheck source=../../lib/review-rounds.sh disable=SC1091
  . "$lib"
  type rr_rounds >/dev/null 2>&1 || {
    fail "$label — lib/review-rounds.sh defines no rr_rounds"
    return 1
  }
  RH_MODES="C"
  if md_need_locale "$label"; then RH_MODES="C UTF8 LANG"; fi
  RH_ERRF="$SANDBOX/rh.err"
  return 0
}

# rrl_row <created_at> <source> <body>: one input row (body newlines to \001).
rrl_row() {
  printf '%s\t%s\t-\t%s\n' "$1" "$2" "$(printf '%s' "$3" | LC_ALL=C tr '\n' '\001')"
}

# rrl_feed <rows>: rr_rounds with the rows on stdin (run it through rh_run).
rrl_feed() { rr_rounds <<<"$1"; }

# rrl_call <mode> <rows>: RH_OUT, RH_RC, RH_ERR.
rrl_call() { rh_run "$1" rrl_feed "$2"; }

# rrl_view: RH_OUT as "<kind>:<n>:<created_at>:<source>" lines (url and body dropped).
rrl_view() {
  printf '%s' "$RH_OUT" | LC_ALL=C awk -F '\t' 'NF { printf "%s:%s:%s:%s\n", $1, $2, $3, $4 }'
}

# rrl_nf: every output row has exactly six tab separated fields (prints the bad row).
rrl_nf() {
  printf '%s' "$RH_OUT" | LC_ALL=C awk -F '\t' 'NF && NF != 6 { print; bad = 1 } END { exit bad }'
}

# rrl_shim_nohit <dir> <counter>: a grep in <dir> that finds nothing, as a real
# grep does: exit 1, and a `0` on stdout only when asked to count (-c, alone or
# inside a flag cluster such as -aEc). Every call is counted in <counter>.
rrl_shim_nohit() {
  local dir="$1" counter="$2"
  mkdir -p "$dir"
  {
    printf '#!/bin/sh\n'
    printf 'echo x >> "%s"\n' "$counter"
    # shellcheck disable=SC2016  # written into the shim, not expanded here
    printf 'for a in "$@"; do case "$a" in -*c*) echo 0 ;; esac; done\nexit 1\n'
  } >"$dir/grep"
  chmod +x "$dir/grep"
}

#!/usr/bin/env bash
# lib/review-rounds.sh — THE definition of a Review round (A37, #426, slice V5 of #411).
#
# STUB, red commit of #426: the agreed signature only, no logic. rr_rounds exits
# 99, so every case that calls it fails on an assertion, never on "command not
# found". The Developer replaces the body; the signature below does not change
# without the Architect and QA.
#
# Source, don't execute. Sourcing this file alone gives rr_rounds.
#
#   rr_rounds        reads rows on STDIN, one per body, tab separated:
#                        <created_at> TAB <source> TAB <url> TAB <body>
#                    source is comment | issue | review; url is "-" when unknown;
#                    the body holds its newlines as U+0001. A blank line is ignored.
#                    Prints one row per body that is a Review round, plus one per
#                    body whose first candidate is a Planning record after at least
#                    one round, in time order, six tab separated fields:
#                        R TAB <n> TAB <created_at> TAB <source> TAB <url> TAB <body>
#                        P TAB <n> TAB <created_at> TAB <source> TAB <url> TAB <body>
#                    R: n is the round's 1-based number. P: the number of the latest
#                    round before it. The body field is the input field unchanged.
#                    Order: created_at, then source (issue, comment, review), then
#                    input order. Status 0, also for no round. A failed read (an
#                    external tool, a `[[ =~ ]]` of 2) prints nothing on stdout, one
#                    line on stderr and returns non-zero: never "no round".
#   A round: one body whose first candidate (an ok or near-miss model-record line,
#   read through rec_scan model-record; a quoted one is not a candidate) is
#   stage=Review, or a body with no candidate and a live
#   `pre-merge-review:done sha=<40 hex>` marker (legacy).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

rr_rounds() {
  return 99
}

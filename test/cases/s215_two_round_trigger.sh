#!/usr/bin/env bash
# S215 — two consecutive rounds with a medium-or-worse finding force an Architect step; the count resets.
# Covers: F42
#
# Issue #410, AC3 (Architect A28); amended by #499 AC14 (A41): the
# two-round trigger is located by ID. OR20 starts one item in part 2, with
# tier judgment. The behaviour (a round counts at an open medium-or-higher
# finding, new or carried; two consecutive counting rounds send the
# orchestrator to the Architect before any Developer fix; the count restarts
# after the recorded Architect step) moved to OB21 (counts), OB22 (does not
# count) and OB23 (reset), run by the differential test, not ./check.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/orchestrator-core-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/orchestrator-core-helpers.sh"

oc_rule "S215/OR20 two-round trigger" OR20 judgment 2

test_done

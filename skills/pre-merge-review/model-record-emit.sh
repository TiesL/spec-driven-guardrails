#!/usr/bin/env bash
# skills/pre-merge-review/model-record-emit.sh — prints a role's
# `model-record` marker line, so nobody types one (#402, A26).
#
# Usage:
#   model-record-emit.sh --stage <Stage> --model <id> --effort <low|medium|high|unknown> [--floor-basis <sentence>]
#
# The orchestrator puts this command in each dispatch prompt with --stage and
# --effort filled in; the role adds --model with its own exact model id (the
# Reviewer also adds --floor-basis, in single quotes) and pastes the output,
# unchanged, as the first line of its report. The format itself is owned by
# the model-choice skill ("Machine-readable form").
#
# This script only parses its flags. Every rule lives in marker_emit
# (lib/model-record.sh), which prints the one valid line after parsing it
# back, or nothing.
#
# Exit codes:
#   0 — the line is on stdout
#   2 — refused: an unknown, missing, repeated or value-less flag, a
#       positional argument, or a value marker_emit refuses (reason on
#       stderr, nothing on stdout)
#   3 — lib/model-record.sh was not found next to this clone
#
# Works through a symlinked skills directory (an adopted project's
# .claude/skills): the lib is found from this script's real directory, the
# same way model-record-gate.sh finds it.
#
# Bash 3.2-compatible. No eval.

set -uo pipefail

own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ ! -r "$own_dir/../../lib/model-record.sh" ]; then
  echo "model-record-emit: lib/model-record.sh not found next to this skill ($own_dir/../../lib) — cannot produce a marker." >&2
  exit 3
fi
# shellcheck source=../../lib/model-record.sh
. "$own_dir/../../lib/model-record.sh"

usage="usage: model-record-emit.sh --stage <Stage> --model <id> --effort <low|medium|high|unknown> [--floor-basis <sentence>]"
stage="" model="" effort="" fb=""
have_stage=0 have_model=0 have_effort=0 have_fb=0

while [ $# -gt 0 ]; do
  flag="$1"
  case "$flag" in
    --stage | --model | --effort | --floor-basis) : ;;
    *)
      echo "model-record-emit: unknown argument '$flag'. $usage" >&2
      exit 2
      ;;
  esac
  if [ $# -lt 2 ]; then
    echo "model-record-emit: $flag needs a value. $usage" >&2
    exit 2
  fi
  value="$2"
  shift 2
  case "$flag" in
    --stage)
      [ "$have_stage" -eq 0 ] || { echo "model-record-emit: --stage given twice" >&2; exit 2; }
      have_stage=1 stage="$value"
      ;;
    --model)
      [ "$have_model" -eq 0 ] || { echo "model-record-emit: --model given twice" >&2; exit 2; }
      have_model=1 model="$value"
      ;;
    --effort)
      [ "$have_effort" -eq 0 ] || { echo "model-record-emit: --effort given twice" >&2; exit 2; }
      have_effort=1 effort="$value"
      ;;
    --floor-basis)
      [ "$have_fb" -eq 0 ] || { echo "model-record-emit: --floor-basis given twice" >&2; exit 2; }
      have_fb=1 fb="$value"
      ;;
  esac
done

for need in stage model effort; do
  have_var="have_$need"
  if [ "${!have_var}" -eq 0 ]; then
    echo "model-record-emit: --$need is required. $usage" >&2
    exit 2
  fi
done

if [ "$have_fb" -eq 1 ]; then
  line="$(marker_emit "$stage" "$model" "$effort" "$fb")" || exit 2
else
  line="$(marker_emit "$stage" "$model" "$effort")" || exit 2
fi
printf '%s\n' "$line"
exit 0

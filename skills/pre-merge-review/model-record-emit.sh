#!/usr/bin/env bash
# skills/pre-merge-review/model-record-emit.sh — prints a role's
# `model-record` marker line, so nobody types one (#402, A26).
#
# Usage:
#   model-record-emit.sh --role <Role> [--stage <Stage>] --model <id> [--floor-basis <sentence>]
#
# The orchestrator puts this command in each dispatch prompt with --role
# filled in; the role adds --model with its own exact model id (the
# Reviewer also adds --floor-basis, in single quotes) and pastes the output,
# unchanged, as the first line of its report. The format itself is owned by
# the model-choice skill ("Machine-readable form").
#
# --effort is accepted and ignored for one release (#424, A33/A33a): effort is
# no longer recorded, and a stale prompt in an adopted project keeps working;
# one stderr line says so. The next release removes the flag (PRD debt row).
#
# --stage alone remains accepted for old prompts; with --role it must agree.
# This script only parses its flags. role_stage owns the role map and mismatch
# rule; marker_emit validates and round-trips the marker (lib/model-record.sh).
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

usage="usage: model-record-emit.sh --role <Role> [--stage <Stage>] --model <id> [--floor-basis <sentence>]"
role="" stage="" model="" fb=""
have_role=0 have_stage=0 have_model=0 have_fb=0 saw_effort=0

while [ $# -gt 0 ]; do
  flag="$1"
  case "$flag" in
    --role | --stage | --model | --effort | --floor-basis) : ;;
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
  # a value that IS one of the wrapper's own flag names is a typo or a swallowed
  # flag (`--model --floor-basis`), never a value (A33a, #404 item 3); a value
  # that merely starts with `--` is allowed
  case "$value" in
    --role | --stage | --model | --effort | --floor-basis)
      echo "model-record-emit: $flag's value is '$value', which is one of this command's flags: a value is missing. $usage" >&2
      exit 2
      ;;
  esac
  case "$flag" in
    --role)
      [ "$have_role" -eq 0 ] || { echo "model-record-emit: --role given twice" >&2; exit 2; }
      have_role=1 role="$value"
      ;;
    --stage)
      [ "$have_stage" -eq 0 ] || { echo "model-record-emit: --stage given twice" >&2; exit 2; }
      have_stage=1 stage="$value"
      ;;
    --model)
      [ "$have_model" -eq 0 ] || { echo "model-record-emit: --model given twice" >&2; exit 2; }
      have_model=1 model="$value"
      ;;
    --effort)
      saw_effort=1 # ignored (#424)
      ;;
    --floor-basis)
      [ "$have_fb" -eq 0 ] || { echo "model-record-emit: --floor-basis given twice" >&2; exit 2; }
      have_fb=1 fb="$value"
      ;;
  esac
done

if [ "$have_role" -eq 0 ] && [ "$have_stage" -eq 0 ]; then
  echo "model-record-emit: --role or --stage is required. $usage" >&2
  exit 2
fi
if [ "$have_model" -eq 0 ]; then
  echo "model-record-emit: --model is required. $usage" >&2
  exit 2
fi
if [ "$have_role" -eq 1 ]; then
  if [ "$have_stage" -eq 1 ]; then
    stage="$(role_stage "$role" "$stage")" || exit 2
  else
    stage="$(role_stage "$role")" || exit 2
  fi
fi

if [ "$have_fb" -eq 1 ]; then
  line="$(marker_emit "$stage" "$model" "$fb")" || exit 2
else
  line="$(marker_emit "$stage" "$model")" || exit 2
fi
[ "$saw_effort" -eq 0 ] || echo "effort is no longer recorded (#413); drop --effort from your prompt" >&2
printf '%s\n' "$line"
exit 0

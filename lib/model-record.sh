#!/usr/bin/env bash
# lib/model-record.sh — Shared reading of `model-record` markers (A25, #392).
#
# Source, don't execute. Two callers read the same marker fields and must
# agree on how: skills/pre-merge-review/model-record-gate.sh and
# compliance-evidence.sh. Three functions, one copy:
#
#   normalize_model <label>      model label -> comparable form (moved
#                                unchanged from both scripts, #268)
#   effort_rank <value>          low|medium|high -> 0|1|2; anything else
#                                prints nothing (unknown: no claim)
#   marker_attr <line> <name>    the quoted value of one attribute of a
#                                marker line; the name must start the
#                                attribute (line start or whitespace), so
#                                `model` never matches inside `floor-basis`
#                                or `reviewer-model`. Unquoted, absent: prints
#                                nothing.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# Structural, not a per-model alias table (#268): strips the vendor-prefix
# word and a trailing 8-digit snapshot-date suffix, then folds every
# remaining separator and case difference away. Exact-modulo-format, not
# exact-modulo-spelling: a short alias ("opus") stays different from its
# full id ("claude-opus-5"), recorded as debt (PRD.md).
normalize_model() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/^[[:space:]]*claude[- ]*//' \
    | sed -E 's/-[0-9]{8}$//' \
    | sed -E 's/[^a-z0-9]+/ /g' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

effort_rank() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    low) printf '0' ;;
    medium) printf '1' ;;
    high) printf '2' ;;
  esac
  return 0
}

marker_attr() {
  local line="$1" name="$2" hit=""
  hit="$(grep -oE "(^|[[:space:]])$name=\"[^\"]*\"" <<<"$line" | head -1)"
  [ -n "$hit" ] || return 0
  hit="${hit#*=\"}"
  printf '%s' "${hit%\"}"
  return 0
}

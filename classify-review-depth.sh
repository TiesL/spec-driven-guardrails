#!/usr/bin/env bash
# classify-review-depth.sh — Read-only quick/thorough review-depth
# classifier for one PR (issue #328, A13 in
# wip/multi-agent-development/ARCHITECTURE-MULTI-AGENT-WIP.md).
#
# Usage:
#   classify-review-depth.sh <pr-number> [--force-thorough]
#
# Extends pre-merge-review's existing single-Reviewer gate with a
# quick/thorough split, without adding a new role or a new risk taxonomy.
# This script only classifies; it never posts, labels, edits, or merges
# anything (same read-only contract as role-label-staleness.sh/
# compliance-evidence.sh).
#
# Classifier basis (A13, deliberately narrow — no size/files-touched
# dimension, Architect explicitly rejected it): Reviewer's own six
# trigger categories (skills/role-contracts/
# SKILL.md's "Security review triggers" table) — Auth/session, Secrets/
# credentials, Deploy/CI configuration, Infrastructure as Code,
# Sensitive/personal data, Untrusted input. Matched against the PR's own
# changed-file paths AND its title+body text (either signal is enough —
# a category can be evidenced by a path shape, description language, or
# both). Matching doesn't short-circuit: every one of the six is checked
# every run, so a PR that matches several is reported with all of them,
# never just the first hit.
#
# Manual override: --force-thorough forces `thorough` even with zero
# category matches (A13's dogfooding mechanism, so the mechanism has a
# real caller before #307 decides on any default-on rule). It is
# strictly additive: on a PR that already matches a real category, the
# override changes nothing about the printed evidence — the real
# category name(s) are what get named, never "forced" instead of them.
# "forced" only ever appears when it was the SOLE reason the verdict is
# `thorough` (zero categories matched).
#
# LENS_ADAPTER_COUNT (A13's testable-seam note, per QA's own
# recommendation): the classify -> dispatch handoff is a real Seam, but
# A13 decided it doesn't get its own script — the thorough-mode dispatch
# (Reviewer plus this many fresh, generic, undifferentiated lens-Adapter
# forks, never named personas, never derived from how many categories
# matched) lives as prose in skills/pre-merge-review/SKILL.md. That
# prose reads this constant with `--lens-adapter-count` (below) rather
# than restating the literal number, so a future edit to either file
# that lets the two numbers drift shows up as a test failure, not a
# silent mismatch nobody notices. The classifier's own verdict-producing
# stdout never prints this constant, or any other count/multiplier — the
# `thorough` verdict names matched categories only (S154 #7 in
# TEST-SCENARIOS.md holds this directly), so nothing in the classifier's
# own interface can regress toward "N grows with match count" even
# before the dispatch side (untestable the same way at the prose layer,
# flagged as such in QA's issue #328 comment) exists.
LENS_ADAPTER_COUNT=2

if [ "${1:-}" = "--lens-adapter-count" ]; then
  printf '%s\n' "$LENS_ADAPTER_COUNT"
  exit 0
fi

# REST-only (issues #318/#320/#323/#341's history, reusing model-record-
# gate.sh's/role-label-staleness.sh's already-reviewed design rather than
# re-deriving it independently): every `gh pr view --json ...` call is
# GraphQL-backed under the hood and 403s from inside a Claude Code
# session. Every call below is `gh api` against an explicit REST
# endpoint instead.
#
# Two calls only:
#   1. `GET .../pulls/<n>/files` (paginated) — changed-file paths.
#   2. `GET .../pulls/<n>` — the PR's own current title+body, folded into
#      one \u0001-joined string on one call (same sentinel-transport
#      convention model-record-gate.sh already uses for this exact
#      field pair).
#
# Fail-open direction (QA's call, issue #328 — the inverted direction
# from every other gate in this repo): a REST call failure here fails
# open TOWARD thorough, not quick. This classifier's only purpose is
# triggering extra scrutiny for a security-shaped change; an unreadable
# diff/description is exactly the case with the least evidence to rule a
# trigger match OUT, so under-reviewing on a lookup failure would be the
# wrong direction to guess. "No `gh` on PATH at all" is a harder, DISTINCT
# failure (exit 3, nothing on stdout) — not folded into the same
# fail-open-toward-thorough behavior, so a caller can tell "no answer"
# apart from "got an answer, chose caution" (mirrors role-label-
# staleness.sh's own split between its exit-3 gh-absent case and its
# per-lookup `indeterminate` degradation).
#
# Exit codes:
#   0 — a verdict line was printed (quick, or thorough for any reason,
#       including the lookup-failed fail-open case)
#   2 — usage error (no PR number, or a non-positive-integer PR number)
#   3 — gh not found on PATH — no verdict at all, nothing on stdout
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}. The two
# fixed 6-element category arrays below are only ever indexed by a
# literal numeral 0-5, never expanded with `[@]` (same discipline role-
# label-staleness.sh's STAGES/ROLE_LABELS arrays already use, for the
# same bash-3.2 `set -u` empty-array-expansion reason).
#
# No `eval`: PR file paths and title/body text aren't under this script's
# own control.
#
# Dogfood-only, repo root, same placement/shape as role-label-
# staleness.sh/compliance-evidence.sh: not under skills/ or templates/,
# no propagation to adopted projects for this epic; not invoked by
# `./check` (needs gh/network — only its tests are, offline against
# fake_gh_bin fixtures).

set -uo pipefail

usage() {
  echo "usage: classify-review-depth.sh <pr-number> [--force-thorough]" >&2
}

FORCE_THOROUGH=0
pr_number=""

for arg in "$@"; do
  case "$arg" in
    --force-thorough)
      FORCE_THOROUGH=1
      ;;
    *)
      if [ -n "$pr_number" ]; then
        usage
        exit 2
      fi
      pr_number="$arg"
      ;;
  esac
done

if [ -z "$pr_number" ]; then
  usage
  exit 2
fi
case "$pr_number" in
  *[!0-9]*|0)
    echo "usage: classify-review-depth.sh <pr-number> [--force-thorough] (pr-number must be a positive integer)" >&2
    exit 2
    ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  echo "classify-review-depth: gh not found on PATH — cannot classify review depth." >&2
  exit 3
fi

# --- Fixed six-category basis, Reviewer's own list, verbatim (skills/
# role-contracts/SKILL.md's "Security review
# triggers" table). Indexed 0-5 only, never `[@]` (see the bash-3.2 note
# above). Each pattern is a case-insensitive extended regex checked
# against BOTH the changed-file-path corpus and the title+body corpus —
# either signal is sufficient; this script never records which one
# fired, only that the category matched.
CATEGORY_NAMES=(
  "Auth/session"
  "Secrets/credentials"
  "Deploy/CI configuration"
  "Infrastructure as Code"
  "Sensitive/personal data"
  "Untrusted input"
)
CATEGORY_PATTERNS=(
  '\b(auth|oauth2?|session|login|jwt)\b|\bauthentication\b|\bsession management\b'
  'secrets\.|\bcredentials?\b|\bcreds\b|\.env\b|\bpasswords?\b|\bapi[-_]?keys?\b'
  '(^|/)\.github/workflows/|(^|/)Dockerfile|(^|/)\.gitlab-ci\.yml|(^|/)Jenkinsfile|\bdeploy(s|ed|ment)?\b|\bci pipeline\b|\bgithub actions\b'
  '\.tf$|\.tfvars$|(^|/)terraform/|(^|/)pulumi/|(^|/)cloudformation/|\binfrastructure as code\b|\bterraform\b|\bcloudformation\b'
  '\bpii\b|\bgdpr\b|\bpersonal[-_ ]data\b|\bsensitive data\b|\bsocial security\b|\bssn\b'
  '\bwebhooks?\b|\buntrusted input\b|\bexternal input\b|\buser[- ]supplied input\b|\bapi endpoint\b|\bpublic api\b'
)

files_out="$(gh api "repos/{owner}/{repo}/pulls/$pr_number/files" --paginate --jq '.[].filename' 2>/dev/null)"
files_status=$?

titlebody_out="$(gh api "repos/{owner}/{repo}/pulls/$pr_number" --jq '(.title//"")+"\u0001"+(.body//"")' 2>/dev/null)"
titlebody_status=$?

if [ "$files_status" -ne 0 ] || [ "$titlebody_status" -ne 0 ]; then
  echo "warning: classify-review-depth couldn't read PR #$pr_number's changed files and/or its title/body (no network or no access) — classifying thorough anyway, since an unreadable diff/description is exactly the case with the least evidence to rule a security-relevant category OUT." >&2
  printf 'review-depth: thorough (lookup-failed)\n'
  exit 0
fi

title_part="${titlebody_out%%$'\001'*}"
body_part="${titlebody_out#*$'\001'}"
corpus="$files_out
$title_part
$body_part"

matched=""
i=0
while [ "$i" -le 5 ]; do
  if grep -qiE "${CATEGORY_PATTERNS[$i]}" <<<"$corpus"; then
    if [ -z "$matched" ]; then
      matched="${CATEGORY_NAMES[$i]}"
    else
      matched="$matched, ${CATEGORY_NAMES[$i]}"
    fi
  fi
  i=$((i + 1))
done

if [ -n "$matched" ]; then
  printf 'review-depth: thorough (%s)\n' "$matched"
elif [ "$FORCE_THOROUGH" -eq 1 ]; then
  printf 'review-depth: thorough (forced)\n'
else
  printf 'review-depth: quick\n'
fi
exit 0

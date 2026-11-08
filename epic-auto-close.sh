#!/usr/bin/env bash
# epic-auto-close.sh — Closes an epic automatically once every issue that
# names it via **Epic:** #<n> is closed (issue #219).
#
# Called from CI, on the `issues: closed` event, with the just-closed
# issue's number:
#
#   ./epic-auto-close.sh "$ISSUE_NUMBER"
#
# The **Epic:** field (templates/ISSUE_TEMPLATE/work-item.md) is the only
# signal trusted here — not the epic's own "Work items" checklist, which is
# for human readability and can drift (found via issue #211, whose
# checklist was never filled in at all). Same "only the field counts, not
# prose" rule check-traceability.sh already applies to **Covers:**.
#
# No fail-open the way the merge guard has one: this runs after the fact,
# on its own event, and a missed close is recoverable by hand (as #211
# was) — unlike the merge guard, nothing here blocks other work if it
# errors. Failures are therefore loud (non-zero exit, message on stderr),
# not silently swallowed. The one deliberately quiet path is "nothing to
# do" (not a work item, epic already closed, siblings still open) — that's
# the common case on every other issue close and isn't worth a log line
# each time.
#
# Repo-local for now (issue #219 deliberately keeps scaffolding this to
# templates/ for adopted projects out of scope, as a later decision).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

issue_number="${1:?usage: epic-auto-close.sh <issue-number>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "epic-auto-close: gh is missing." >&2
  exit 1
fi

body="$(gh issue view "$issue_number" --json body --jq '.body // ""' 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "epic-auto-close: couldn't look up issue #$issue_number." >&2
  exit 1
fi

# The field grammar matches **Covers:** elsewhere: a fixed bold label at
# the start of a line, then #<digits>. Only the first match counts — a
# well-formed issue has exactly one.
epic_number="$(grep -oE '^\*\*Epic:\*\*[[:space:]]*#[0-9]+' <<<"$body" \
  | grep -oE '[0-9]+' | head -n1)"

if [ -z "$epic_number" ]; then
  exit 0
fi

# A work item naming itself as its own epic is malformed input, not a
# real epic to close.
if [ "$epic_number" = "$issue_number" ]; then
  echo "epic-auto-close: issue #$issue_number names itself as its own Epic — skipping." >&2
  exit 0
fi

epic_state="$(gh issue view "$epic_number" --json state --jq .state 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] || [ -z "$epic_state" ]; then
  echo "epic-auto-close: couldn't look up epic #$epic_number (missing or inaccessible) — nothing to do." >&2
  exit 0
fi
if [ "$epic_state" != "OPEN" ]; then
  exit 0
fi

# Every issue in the repo, current state and body, in one call — cheaper
# and more deterministic than a text search (no index-lag concerns, no
# markdown-escaping surprises in a search query). Local filtering, via
# python3, on the **Epic:** field is what check-traceability.sh's own
# style already does for **Covers:** — the JSON is read via a here-string,
# not a piped printf: this repo's own test suite just hit the SIGPIPE/
# pipefail race that pattern invites (issue #216/#218), so it's avoided
# here from the start rather than fixed later.
all_issues="$(gh issue list --state all --json number,state,body --limit 5000 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] || [ -z "$all_issues" ]; then
  echo "epic-auto-close: couldn't list issues — can't tell whether epic #$epic_number's work items are all closed." >&2
  exit 1
fi

decision="$(python3 -c '
import json, re, sys

epic = sys.argv[1]
data = json.load(sys.stdin)
pattern = re.compile(r"^\*\*Epic:\*\*\s*#" + re.escape(epic) + r"\b", re.MULTILINE)

refs = [i for i in data if i.get("body") and pattern.search(i["body"])]
if not refs:
    print("NONE")
elif any(i.get("state") == "OPEN" for i in refs):
    print("STILL_OPEN")
else:
    nums = ",".join("#" + str(i["number"]) for i in sorted(refs, key=lambda i: i["number"]))
    print("CLOSE " + nums)
' "$epic_number" <<<"$all_issues")"

# Release-signal check (#683, A55). A work item merged into a release branch
# does not close the epic's work: the epic stays open while a release/<N>-*
# branch still exists on the remote or a same-repository PR from such a
# branch into main is open. Called only from the CLOSE arm, so epics that are
# not about to close never pay for the two queries.
#
# Each query is `gh api --paginate` with a jq that prints a "page" line per
# page, so a legitimate empty answer (one "page" line) is told apart from a
# failed or malformed one (non-zero exit, no output, no sentinel). Matching is
# repeated here on the exact "release/<N>-" prefix so correctness does not
# rest on the server's filtering. <N> is the digit string validated above.
#
# Returns 0 = a signal keeps the epic open (note already printed), 1 = none
# found, 2 = a query failed (message already printed).
release_signal() {
  local n="$1" out st hit

  out="$(gh api --paginate "repos/{owner}/{repo}/git/matching-refs/heads/release/${n}-" \
    --jq '"page", (.[].ref)' 2>/dev/null)"
  st=$?
  if [ "$st" -ne 0 ] || [ "$(head -n1 <<<"$out")" != "page" ]; then
    echo "epic-auto-close: epic #$n: branch query failed — leaving it open, nothing closed." >&2
    return 2
  fi
  hit="$(grep -m1 -E "^(refs/heads/)?release/${n}-" <<<"$out")"
  if [ -n "$hit" ]; then
    echo "epic-auto-close: epic #$n stays open: release branch ${hit#refs/heads/} still exists." >&2
    return 0
  fi

  out="$(gh api --paginate "repos/{owner}/{repo}/pulls?state=open&base=main&per_page=100" \
    --jq '"page", (.[] | [.state, .base.ref, .head.ref, (.head.repo.full_name // ""), (.base.repo.full_name // "")] | @tsv)' \
    2>/dev/null)"
  st=$?
  if [ "$st" -ne 0 ] || [ "$(head -n1 <<<"$out")" != "page" ]; then
    echo "epic-auto-close: epic #$n: open-PR query failed — leaving it open, nothing closed." >&2
    return 2
  fi
  # open, into main, head named release/<N>-*, head repository = this one.
  hit="$(awk -F'\t' -v pre="release/${n}-" \
    '$1 == "open" && $2 == "main" && $4 != "" && $4 == $5 && index($3, pre) == 1 { print $3; exit }' <<<"$out")"
  if [ -n "$hit" ]; then
    echo "epic-auto-close: epic #$n stays open: open release PR from $hit into main." >&2
    return 0
  fi
  return 1
}

case "$decision" in
  NONE)
    echo "epic-auto-close: no issue names #$epic_number as its Epic — nothing to check." >&2
    exit 0 ;;
  STILL_OPEN)
    exit 0 ;;
  "CLOSE "*)
    refs="${decision#CLOSE }"
    release_signal "$epic_number"
    case $? in
      0) exit 0 ;;
      1) ;;
      *) exit 1 ;;
    esac
    if ! gh issue close "$epic_number" \
      --comment "Auto-closed: every issue naming this as its Epic is closed ($refs)." \
      >/dev/null 2>&1; then
      echo "epic-auto-close: closing epic #$epic_number failed." >&2
      exit 1
    fi
    echo "epic-auto-close: closed epic #$epic_number ($refs all closed)." ;;
  *)
    echo "epic-auto-close: unexpected decision output: $decision" >&2
    exit 1 ;;
esac

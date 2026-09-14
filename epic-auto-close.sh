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
all_issues="$(gh issue list --state all --json number,state,body --limit 1000 2>/dev/null)"
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

case "$decision" in
  NONE)
    echo "epic-auto-close: no issue names #$epic_number as its Epic — nothing to check." >&2
    exit 0 ;;
  STILL_OPEN)
    exit 0 ;;
  "CLOSE "*)
    refs="${decision#CLOSE }"
    gh issue close "$epic_number" \
      --comment "Auto-closed: every issue naming this as its Epic is closed ($refs)." \
      >/dev/null
    echo "epic-auto-close: closed epic #$epic_number ($refs all closed)." ;;
  *)
    echo "epic-auto-close: unexpected decision output: $decision" >&2
    exit 1 ;;
esac

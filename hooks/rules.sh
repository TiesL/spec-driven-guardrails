#!/usr/bin/env bash
# hooks/rules.sh — The rules shared by the PreToolUse guard
# (hooks/git-guardrails) and the native git hooks (W26, pre-commit/pre-push):
# which branch is protected and what the message says.
#
# Pure data, not an input layer. How each hook reads its command differs
# fundamentally — the quote-aware tokenization from read-command.py is by
# definition PreToolUse-specific, a native git hook never gets a command
# string — and so doesn't belong here. What *can* be shared is this: which
# branch is protected, and the text of the message.
#
# Source, don't execute.

MAIN_BRANCH="main"

REASON_COMMIT_ON_MAIN="main gets its changes via a PR. Make a branch first — your
       changes come along unchanged, nothing gets lost:

         git checkout -b feature/<issue>-<name>

       Then commit and push as usual."

REASON_PUSH_TO_MAIN="main gets its changes via a PR, not via a direct push."

# Issue-first branching (F19, issue #212): feature/fix branches must carry
# the issue number they implement, e.g. feature/123-short-desc. Requiring
# the number forces the issue to exist first — the branch can't be named
# without it. Shared between git-guardrails (PreToolUse, also verifies the
# issue via gh) and the native pre-commit hook (syntax only, no network).
BRANCH_ISSUE_PATTERN='^(feature|fix)/[0-9]+-[a-z0-9-]+$'

REASON_BRANCH_NO_ISSUE="every feature/fix branch names the issue it implements, e.g.
       feature/123-short-desc. Create the issue first (see the write-spec
       skill for the epic/work-item templates), then branch from its number:

         gh issue create --template work-item.md
         git checkout -b feature/<issue-number>-<short-desc>"

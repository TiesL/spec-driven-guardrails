#!/usr/bin/env bash
# hooks/regels.sh — The rules shared by the PreToolUse guard
# (hooks/git-guardrails) and the native git hooks (W26, pre-commit/pre-push):
# which branch is protected and what the message says.
#
# Pure data, not an input layer. How each hook reads its command differs
# fundamentally — the quote-aware tokenization from lees-commando.py is by
# definition PreToolUse-specific, a native git hook never gets a command
# string — and so doesn't belong here. What *can* be shared is this: which
# branch is protected, and the text of the message.
#
# Source, don't execute.

HOOFDBRANCH="main"

REDEN_COMMIT_OP_MAIN="main gets its changes via a PR. Make a branch first — your
       changes come along unchanged, nothing gets lost:

         git checkout -b feature/<name>

       Then commit and push as usual."

REDEN_PUSH_NAAR_MAIN="main gets its changes via a PR, not via a direct push."

#!/usr/bin/env bash
# lib/context-budget.sh — the one budget for session-start hook output
# (#499, A41).
#
# Source, don't execute. Claude Code keeps at most 10,000 characters of one
# hook's stdout in context; above that it saves the output to a file it does
# not ask the model to read. CONTEXT_BUDGET_CHARS leaves 10% headroom under
# that cap and applies to each hook's output string separately (each
# `session-context.sh --slot <n>` command, and `pending-changes.sh`), in its
# worst case. Only tests source this module: there is no run-time guard
# (Human decision 3 on #499). The CHANGES.md Reaches session field rules and
# PRD F38 state the same number; a test keeps them equal to this constant.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

CONTEXT_BUDGET_CHARS=9000

# context_chars: the number of UTF-8 code points on stdin. The same number
# as `wc -m` in a UTF-8 locale, without depending on the locales a CI image
# has installed. Invalid UTF-8 bytes count one each.
context_chars() {
  python3 -I -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8", "replace")))'
}

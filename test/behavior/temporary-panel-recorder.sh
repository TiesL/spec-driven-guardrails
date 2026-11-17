#!/usr/bin/env bash
# Deny-all PreToolUse recorder (#680). Never executes any tool input.
# Independent containment must be established before exposing any real tool.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I "$here/temporary_panel_run.py" recorder "$@"

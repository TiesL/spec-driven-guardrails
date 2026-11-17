#!/usr/bin/env bash
# Shared instruction exercises (#680; A56). Uses subscription usage only on
# explicit live run/judge. Default dry-run starts nothing. Not called by CI.
# Bash 3.2-compatible; the Python Module owns all four operations.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I "$here/temporary_panel_run.py" "$@"

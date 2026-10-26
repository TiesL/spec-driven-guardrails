#!/usr/bin/env bash
# Read-only drift verification for runtime adapters, the root managed block and canonical owners.
set -uo pipefail
own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$own_dir/lib/workflow-adapters.py" check "$@"

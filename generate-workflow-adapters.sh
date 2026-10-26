#!/usr/bin/env bash
# Deterministically generate runtime instruction payloads and the root managed block.
set -uo pipefail
own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$own_dir/lib/workflow-adapters.py" generate "$@"

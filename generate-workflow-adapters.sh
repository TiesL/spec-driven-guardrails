#!/usr/bin/env bash
# Deterministically generate the two committed runtime instruction payloads.
set -uo pipefail
own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$own_dir/lib/workflow-adapters.py" generate "$@"

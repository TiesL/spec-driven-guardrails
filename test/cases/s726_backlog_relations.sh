#!/usr/bin/env bash
# S726 — #724 relations through delivered text and the public read-only CLI.
# Covers: F77
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python_bin="$(command -v python3)"
printf -v fake_body 'exec %q -I %q "$@"' "$python_bin" "$TEST_REPO_ROOT/test/fixtures/backlog-724-gh.py"
fakebin="$(fake_gh_bin "$fake_body")"
export PATH="$fakebin:$PATH"
export BACKLOG_724_NOGH="$(path_without_gh)"
# Remove gh alone: jq remains available when installed in the normal PATH.
jq_bin="$(command -v jq || true)"
[ -z "$jq_bin" ] || ln -s "$jq_bin" "$BACKLOG_724_NOGH/jq"
python3 -I "$TEST_REPO_ROOT/test/fixtures/backlog-724-cases.py" "$TEST_REPO_ROOT" 726 || fail "S726 — CLI obligations absent"
python3 -I "$TEST_REPO_ROOT/test/fixtures/backlog-724-text.py" "$TEST_REPO_ROOT" 726 || fail "S726 — delivered maintenance obligations absent"
test_done

#!/usr/bin/env bash
# A52 PATH seam: reuse the existing sandbox, adoption and marker fixtures.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=test/fixtures/pipeline-371-helpers.sh
. "$TEST_REPO_ROOT/test/fixtures/pipeline-371-helpers.sh"
epic_651_run() {
  sandbox_create
  trap sandbox_destroy EXIT
  local project bin
  export EPIC_PYTHON
  EPIC_PYTHON="$(command -v python3)"
  project="$(fresh_project project)"
  write_adoption "$project/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
  bin="$SANDBOX/bin"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
exec "$EPIC_PYTHON" "$TEST_REPO_ROOT/test/fixtures/epic-651.py" serve "$@"
GH
  chmod +x "$bin/gh"
  PATH="$bin:$PATH" python3 "$TEST_REPO_ROOT/test/fixtures/epic-651.py" "$1" "$TEST_REPO_ROOT" "$SANDBOX"
}

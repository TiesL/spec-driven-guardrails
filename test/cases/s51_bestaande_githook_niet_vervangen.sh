#!/usr/bin/env bash
# S51 — An existing git hook is not silently replaced.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project eigen-hook)"
mkdir -p "$project/.git/hooks"
cat > "$project/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "eigen pre-commit-hook, niet van claude-workflow"
exit 0
EOF
chmod +x "$project/.git/hooks/pre-commit"

# Not via the adopteer() helper: that throws all output to /dev/null, and
# this test specifically needs to see the message.
melding="$(SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$project" 2>&1)"

# Then: that hook is not overwritten without a message.
if [ -L "$project/.git/hooks/pre-commit" ]; then
  fail "S51 — the custom pre-commit hook was replaced by a symlink"
fi
if ! grep -q 'eigen pre-commit-hook, niet van claude-workflow' "$project/.git/hooks/pre-commit"; then
  fail "S51 — the content of the custom pre-commit hook has changed"
fi
assert_contains "S51 — a message appeared about the existing file" "not touched" "$melding"
if [ -f "$project/.git/hooks/pre-commit.bak" ]; then
  fail "S51 — a .bak was created; the custom hook should have been left alone instead"
fi

# And: pre-push, which had no custom file, does become this repo's symlink.
[ -L "$project/.git/hooks/pre-push" ] || fail "S51 — pre-push was not installed as a symlink"

# And: running twice gives an identical tree — the custom hook remains a
# regular file with the same content, pre-push remains the same symlink, no
# .bak added.
adopteer "$project" >/dev/null 2>&1
if [ -L "$project/.git/hooks/pre-commit" ]; then
  fail "S51 — after a second run the custom hook still became a symlink"
fi
if ! grep -q 'eigen pre-commit-hook, niet van claude-workflow' "$project/.git/hooks/pre-commit"; then
  fail "S51 — after a second run the content of the custom hook has changed"
fi
if [ -e "$project/.git/hooks/pre-commit.bak" ]; then
  fail "S51 — a second adopt.sh run still created a backup"
fi
[ "$(readlink "$project/.git/hooks/pre-push")" = "$TEST_REPO_ROOT/hooks/pre-push" ] \
  || fail "S51 — pre-push no longer points to the same source after a second run"

# And: a custom hook that is itself also a symlink (pointing to something
# other than claude-workflow, for instance the project's own dotfiles) is
# just as much a deliberate choice as a regular file — and is therefore also
# not silently replaced. Found in the review on PR #76: the original check
# only tested "is this not a symlink", not "does this symlink already point
# to our own source".
project2="$(vers_project eigen-symlink-hook)"
mkdir -p "$project2/.git/hooks"
elders="$SANDBOX/ergens-anders-pre-push"
cat > "$elders" <<'EOF'
#!/usr/bin/env bash
echo "eigen symlink-hook, wijst niet naar claude-workflow"
exit 0
EOF
chmod +x "$elders"
ln -s "$elders" "$project2/.git/hooks/pre-push"

melding2="$(SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$project2" 2>&1)"

if [ "$(readlink "$project2/.git/hooks/pre-push")" != "$elders" ]; then
  fail "S51 — a custom symlink hook (pointing to something other than claude-workflow) was replaced after all"
fi
assert_contains "S51 — a message appeared about the custom symlink hook" "not touched" "$melding2"

test_klaar

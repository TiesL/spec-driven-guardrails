#!/usr/bin/env bash
# S51 — Een bestaande git-hook wordt niet stilzwijgend vervangen.
# Dekt: F17

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

# Niet via de adopteer()-helper: die gooit alle uitvoer naar /dev/null, en
# deze test moet juist de melding zien.
melding="$(SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$project" 2>&1)"

# Then: die hook wordt niet overschreven zonder melding.
if [ -L "$project/.git/hooks/pre-commit" ]; then
  fail "S51 — de eigen pre-commit-hook werd vervangen door een symlink"
fi
if ! grep -q 'eigen pre-commit-hook, niet van claude-workflow' "$project/.git/hooks/pre-commit"; then
  fail "S51 — de inhoud van de eigen pre-commit-hook is veranderd"
fi
assert_contains "S51 — er kwam een melding over het bestaande bestand" "not touched" "$melding"
if [ -f "$project/.git/hooks/pre-commit.bak" ]; then
  fail "S51 — er werd een .bak gemaakt; de eigen hook had juist met rust gelaten moeten worden"
fi

# And: pre-push, dat geen eigen bestand had, is wél de symlink van dit repo.
[ -L "$project/.git/hooks/pre-push" ] || fail "S51 — pre-push werd niet geïnstalleerd als symlink"

# And: twee keer draaien geeft een identieke boom — de eigen hook blijft een
# gewoon bestand met dezelfde inhoud, pre-push blijft dezelfde symlink, geen
# .bak erbij.
adopteer "$project" >/dev/null 2>&1
if [ -L "$project/.git/hooks/pre-commit" ]; then
  fail "S51 — na een tweede run werd de eigen hook alsnog een symlink"
fi
if ! grep -q 'eigen pre-commit-hook, niet van claude-workflow' "$project/.git/hooks/pre-commit"; then
  fail "S51 — na een tweede run is de inhoud van de eigen hook veranderd"
fi
if [ -e "$project/.git/hooks/pre-commit.bak" ]; then
  fail "S51 — een tweede adopt.sh-run maakte alsnog een back-up"
fi
[ "$(readlink "$project/.git/hooks/pre-push")" = "$TEST_REPO_ROOT/hooks/pre-push" ] \
  || fail "S51 — pre-push wijst na een tweede run niet meer naar dezelfde bron"

# And: een eigen hook die zélf ook een symlink is (naar iets anders dan
# claude-workflow, bijvoorbeeld de eigen dotfiles van het project) is net zo
# goed een eigen keuze als een echt bestand — en wordt dus ook niet
# stilzwijgend vervangen. Gevonden in de review op PR #76: de oorspronkelijke
# check testte alleen "is dit geen symlink", niet "wijst deze symlink al naar
# onze eigen bron".
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
  fail "S51 — een eigen symlink-hook (naar iets anders dan claude-workflow) werd toch vervangen"
fi
assert_contains "S51 — er kwam een melding over de eigen symlink-hook" "not touched" "$melding2"

test_klaar

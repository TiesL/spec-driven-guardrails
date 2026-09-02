#!/usr/bin/env bash
# test/lib.sh — Gedeelde hulpfuncties voor de testsuite.
#
# Sourcen, niet uitvoeren. Elke test draait in een eigen sandbox met een
# geinjecteerde HOME en CLAUDE_WORKFLOW_DIR, zodat een test nooit de echte
# omgeving van de gebruiker kan raken.
#
# Bash 3.2-compatibel: geen declare -A, geen mapfile, geen ${var,,}.

# De echte home, vastgelegd voordat een test hem kan overschrijven. Dit is de
# waarde waartegen sandbox_guard vergelijkt.
TEST_REAL_HOME="${TEST_REAL_HOME:-$HOME}"
export TEST_REAL_HOME

# Wortel van dit repo, onafhankelijk van waarvandaan de test wordt aangeroepen.
TEST_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_REPO_ROOT

_test_failures=0

fail() {
  echo "    FAIL: $*" >&2
  _test_failures=$((_test_failures + 1))
}

# De harde weigering uit S3. Draait na elke sandboxopzet: staat HOME dan nog op
# de echte home, dan is de sandbox niet actief en zou de test in de echte
# omgeving van de gebruiker schrijven. Dat is geen waarschuwing waard maar een
# onmiddellijke stop.
sandbox_guard() {
  if [ "$HOME" = "$TEST_REAL_HOME" ]; then
    echo "AFGEBROKEN: sandboxopzet heeft HOME niet omgezet (HOME is nog '$HOME')." >&2
    echo "Een test mag nooit in de echte home schrijven." >&2
    return 1
  fi
  if [ -z "${HOME:-}" ]; then
    echo "AFGEBROKEN: HOME is leeg na sandboxopzet." >&2
    return 1
  fi
  return 0
}

# Maakt een sandbox en zet HOME en CLAUDE_WORKFLOW_DIR erheen. Zet SANDBOX.
sandbox_create() {
  SANDBOX="$(mktemp -d)"
  export SANDBOX
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME"
  export CLAUDE_WORKFLOW_DIR="$SANDBOX/workflow"

  # Een identiteit voor git, net zoals HOME: een test mag niet afhangen van de
  # configuratie van de machine waarop hij toevallig draait. Zonder dit slaagt
  # `git commit` lokaal (waar een globale identiteit staat) en faalt hij op een
  # verse CI-runner - precies het soort verschil dat je pas laat ontdekt.
  export GIT_AUTHOR_NAME="claude-workflow test"
  export GIT_AUTHOR_EMAIL="test@example.invalid"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  if ! sandbox_guard; then
    rm -rf "$SANDBOX"
    exit 1
  fi
}

sandbox_destroy() {
  if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
    rm -rf "$SANDBOX"
  fi
}

# Kopieert dit repo naar de sandbox, zodat een test bestanden mag stukmaken
# zonder de werkkopie te raken. Laat .git buiten beschouwing: niet nodig voor
# de statische controles en het scheelt tijd.
sandbox_copy_repo() {
  local doel="$SANDBOX/repo"
  mkdir -p "$doel"
  (cd "$TEST_REPO_ROOT" && tar --exclude='./.git' -cf - .) | (cd "$doel" && tar -xf -)
  echo "$doel"
}

# Maakt een vers, leeg git-project in de sandbox en echoot het pad. adopt.sh
# weigert zonder .git, dus dat init'en hoort bij de opzet.
vers_project() {
  local naam="$1"
  local pad="$SANDBOX/$naam"
  mkdir -p "$pad"
  git -C "$pad" init -q
  echo "$pad"
}

# Adopteert de workflow in een project, met dit repo als bron. adopt.sh leest
# alleen uit CLAUDE_WORKFLOW_DIR en schrijft uitsluitend in het project.
adopteer() {
  CLAUDE_WORKFLOW_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$1" >/dev/null 2>&1
}

# De openstaande ID's voor een project, alfabetisch, één per regel.
openstaande_ids() {
  "$TEST_REPO_ROOT/pending-changes.sh" "$1" 2>/dev/null \
    | grep '^  - ' | sed 's/^  - //; s/ —.*//' | sort
}

# De ID's die adopt.sh in de adoptietabel heeft geseed, alfabetisch.
geseede_ids() {
  local tabel="$1/WORKFLOW-ADOPTIE.md"
  [ -f "$tabel" ] || return 0
  grep '^| [a-z]' "$tabel" | sed 's/^| *//; s/ *|.*//' | sort
}

# Vergelijkt twee ID-lijsten en meldt het verschil per ID.
assert_ids_gelijk() {
  local omschrijving="$1" verwacht="$2" gekregen="$3"
  if ! diff -u "$verwacht" "$gekregen" >/dev/null 2>&1; then
    fail "$omschrijving — ID-set wijkt af:"
    diff -u "$verwacht" "$gekregen" >&2
    return 1
  fi
  return 0
}

# Bouwt een bin-map met alleen de basisgereedschappen die `check` nodig heeft,
# bewust zonder jq en python3. Echoot het pad, te gebruiken als PATH. Zo is de
# "geen enkele validator beschikbaar"-tak te toetsen zonder iets te deinstalleren.
minimale_path_zonder_validators() {
  local bin="$SANDBOX/minbin"
  mkdir -p "$bin"
  local t pad
  for t in bash sh find sort head mktemp rm cat dirname basename tr grep sed chmod mkdir cp tar env; do
    pad="$(command -v "$t" 2>/dev/null)" && ln -sf "$pad" "$bin/$t"
  done
  echo "$bin"
}

assert_contains() {
  local omschrijving="$1" naald="$2" hooiberg="$3"
  case "$hooiberg" in
    *"$naald"*) return 0 ;;
    *) fail "$omschrijving — '$naald' ontbreekt in de uitvoer"; return 1 ;;
  esac
}

test_klaar() {
  if [ "$_test_failures" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

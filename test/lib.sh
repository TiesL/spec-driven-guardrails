#!/usr/bin/env bash
# test/lib.sh — Gedeelde hulpfuncties voor de testsuite.
#
# Sourcen, niet uitvoeren. Elke test draait in een eigen sandbox met een
# geinjecteerde HOME en SPEC_DRIVEN_GUARDRAILS_DIR, zodat een test nooit de echte
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

# De vier bevroren nulmeting-projecten, in de vaste volgorde waarin ze overal
# doorheen deze testsuite genoemd worden (R9, S4, S66, S67) — één plek in
# plaats van de lijst per test opnieuw uittypen.
NULMETING_PROJECTEN="a2t-emails tennis-admin tennis-registration tennis-invoicing"

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

# Maakt een sandbox en zet HOME en SPEC_DRIVEN_GUARDRAILS_DIR erheen. Zet SANDBOX.
sandbox_create() {
  SANDBOX="$(mktemp -d)"
  export SANDBOX
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME"
  export SPEC_DRIVEN_GUARDRAILS_DIR="$SANDBOX/workflow"

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
  local doel="$SANDBOX/${1:-repo}"
  mkdir -p "$doel"
  # Sinds spec-driven-guardrails zichzelf adopteert (issue #98) heeft de echte
  # checkout CLAUDE.md/.claude/settings.json/.claude/skills als absolute
  # symlinks terug naar zichzelf. tar kopieert een symlink als symlink, dus
  # zonder deze uitsluiting zou elke sandboxkopie een symlink bevatten die
  # naar de échte werkkopie buiten de sandbox wijst — precies de
  # isolatiegarantie doorbreken die sandbox_guard() elders afdwingt. Dezelfde
  # drie paden als het .gitignore-beheerde blok (schrijf_gitignore_blok):
  # gitignored omdat ze machine-specifiek zijn, dus ook hier geen onderdeel
  # van een "schone" repo-snapshot.
  (cd "$TEST_REPO_ROOT" && tar --exclude='./.git' --exclude='./CLAUDE.md' \
    --exclude='./.claude/settings.json' --exclude='./.claude/skills' -cf - .) \
    | (cd "$doel" && tar -xf -)
  echo "$doel"
}

# Maakt een vers, leeg git-project in de sandbox en echoot het pad. adopt.sh
# weigert zonder .git, dus dat init'en hoort bij de opzet.
#
# Expliciet -b main: git's eigen default-branchnaam is niet overal gelijk.
# Deze Mac heeft init.defaultBranch=main (Apple's Command Line Tools zetten
# dat systeembreed); de GitHub Actions-runner heeft die override niet en valt
# terug op "master". Scenario's die specifiek gedrag op een branch genaamd
# `main` toetsen (S50, S54) faalden daardoor stelselmatig in CI terwijl ze
# lokaal altijd groen waren — gevonden via issue #81, nadat CI zes runs op rij
# rood bleek zonder dat iemand het merkte.
vers_project() {
  local naam="$1"
  local pad="$SANDBOX/$naam"
  mkdir -p "$pad"
  git -C "$pad" init -q -b main
  echo "$pad"
}

# Adopteert de workflow in een project, met dit repo als bron. adopt.sh leest
# alleen uit SPEC_DRIVEN_GUARDRAILS_DIR en schrijft uitsluitend in het project.
adopteer() {
  SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$1" >/dev/null 2>&1
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

# Bouwt een bin-map met een nep-`gh`, voor tests die gh's netwerk-/PR-gedrag
# moeten simuleren zonder een echte aanroep. $1 is het scriptlichaam van de
# nep-gh (ziet zijn argumenten via "$@"/"$*"). Echoot het pad; zet dit vóór de
# rest van PATH.
fake_gh_bin() {
  local bin="$SANDBOX/fakegh"
  mkdir -p "$bin"
  {
    echo '#!/usr/bin/env bash'
    echo "$1"
  } > "$bin/gh"
  chmod +x "$bin/gh"
  echo "$bin"
}

# Bouwt een gedeelde nep-`gh` voor de merge-guard-tests die een letterlijke
# marker en een letterlijk checks-antwoord teruggeven — de twee uniforme
# gevallen. Bewust smal: geen sentinel-waarden, geen afwijkende foutvormen.
# Een test met een eigen foutvorm (S75, S76 — een niet-nul exit van
# `pr checks`, met of zonder stderr-melding) bouwt die zelf met `fake_gh_bin`,
# net als vóór deze helper (W95, na review: een sentinel-gestuurde variant
# hiervan werd afgewezen als precies de generieke templating-oplossing die
# W95 zelf uitsloot).
#
# $1 — marker-tekst. Leeg = geen marker ("geen marker hier"); anders komt de
#      tekst letterlijk in de `<!-- ... -->`-opmerking terecht.
# $2 — checks-JSON-antwoord, of leeg om geen "pr checks"-tak te bouwen
#      (S15, S16, S65 vragen daar niet naar).
fake_gh_merge_bin() {
  local marker="${1:-}" checks_json="${2:-}"
  local comments_body
  if [ -z "$marker" ]; then
    comments_body='geen marker hier'
  else
    comments_body="bevindingen\\n<!-- $marker -->"
  fi

  local script
  script='case "$*" in
  "pr view --json comments")
    printf "%s" "{\"comments\":[{\"body\":\"'"$comments_body"'\"}]}"
    exit 0 ;;'

  if [ -n "$checks_json" ]; then
    local escaped_checks
    escaped_checks="$(printf '%s' "$checks_json" | sed 's/"/\\"/g')"
    script+='
  "pr checks --json bucket,name")
    printf "%s" "'"$escaped_checks"'"
    exit 0 ;;'
  fi

  script+='
esac
exit 1'

  fake_gh_bin "$script"
}

# Bouwt een PATH zonder `gh`, voor het faal-open-scenario waarin gh ontbreekt.
# Andere gereedschappen die de guard nodig heeft (git, python3) blijven erin,
# in tegenstelling tot minimale_path_zonder_validators hierboven.
pad_zonder_gh() {
  local bin="$SANDBOX/nogh"
  mkdir -p "$bin"
  local t pad
  for t in bash sh git python3 find sort head mktemp rm cat dirname basename tr grep sed awk chmod mkdir cp tar env printf; do
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

# Regels binnen de "## Routing table"-tabel van $1, elk beginnend met '|'.
# Gebruikt door de W9-tests (R7, S29) die de routing table controleren.
wegwijzer_rijen() {
  awk '/^## Routing table/{f=1;next} /^## /{f=0} f' "$1" | grep '^|'
}

# De laatste kolom van een Wegwijzer-tabelrij, ontdaan van backticks,
# witruimte en de "(user-level)"-suffix.
skill_van_rij() {
  printf '%s\n' "$1" | awk -F'|' '{print $(NF-1)}' \
    | sed 's/[[:space:]]//g; s/`//g; s/(user-level)//'
}

#!/usr/bin/env bash
# S48 — Het CI-sjabloon valideert pull requests en `main`.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Het `on:`-blok: alles tussen `on:` en de eerstvolgende sleutel op kolom 0,
# zonder commentaar. Dat laatste is geen detail: zonder die filtering laat een
# uitgecommentarieerde trigger de controle hieronder gewoon slagen — het woord
# staat dan immers in het blok. Precies de regressie die dit scenario moet
# vangen, bijvoorbeeld als iemand een trigger tijdelijk uitzet.
on_blok() {
  awk '/^on:/ { in_blok = 1; next } /^[a-zA-Z]/ { in_blok = 0 } in_blok' "$1" \
    | grep -v '^[[:space:]]*#'
}

# Is dit een echte sleutel in het blok, dus een regel die na inspringing precies
# `<naam>:` of `<naam>: <waarde>` is?
heeft_sleutel() {
  printf '%s\n' "$2" | grep -qE "^[[:space:]]*$1:([[:space:]]|\$)"
}

# De workflow van dit repo zelf hoort dezelfde eis te halen als het sjabloon —
# een regel die je aan anderen oplegt maar zelf ontloopt, is geen regel.
for bestand in templates/ci.yml .github/workflows/ci.yml; do
  pad="$TEST_REPO_ROOT/$bestand"

  if [ ! -f "$pad" ]; then
    fail "S48 — $bestand ontbreekt"
    continue
  fi

  blok="$(on_blok "$pad")"

  # Then: pull requests worden gevalideerd. Dat is niet hetzelfde als een push
  # op de branch: `pull_request` beoordeelt het samengevoegde resultaat, en dat
  # is precies het geval dat twee los-groene branches samen kan breken.
  heeft_sleutel pull_request "$blok" \
    || fail "S48 — $bestand heeft geen pull_request-trigger"

  # And: pushes naar main worden gevalideerd. `branches-ignore` valt eerst weg,
  # anders zou juist de regel die main uitsluit de controle laten slagen — die
  # bevat het woord `main` immers ook.
  positief="$(printf '%s\n' "$blok" | grep -v 'branches-ignore')"
  heeft_sleutel push "$positief" \
    || fail "S48 — $bestand heeft geen push-trigger"
  case "$positief" in
    *main*) ;;
    *) fail "S48 — $bestand noemt main niet in zijn triggers" ;;
  esac

  # And: niet via branches-ignore. Die vorm sluit main juist uit — de fout die
  # dit scenario moet vangen.
  case "$blok" in
    *branches-ignore*) fail "S48 — $bestand gebruikt branches-ignore en slaat main dus over" ;;
  esac

  # And: de CI-conventie zelf verandert niet. De workflow roept uitsluitend
  # `check` aan; losse lint-, test- of buildstappen horen in het script.
  while IFS= read -r regel; do
    case "$regel" in
      *check*|*"npm ci"*) ;;
      *) fail "S48 — $bestand voert een eigen stap uit in plaats van alleen check: $regel" ;;
    esac
  done < <(grep -E '^\s+- run:' "$pad")
done

test_klaar

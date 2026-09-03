#!/usr/bin/env bash
# S45 — Tekst binnen quotes is data, geen commando.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S45 — hooks/git-guardrails ontbreekt"; test_klaar; }

werkmap="$(vers_project werkmap)"

langs_guard() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$werkmap" "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}
toegestaan() {
  [ "$(langs_guard "$2")" = "2" ] && fail "S45 — ten onrechte geblokkeerd: $1"
  return 0
}
geblokkeerd() {
  [ "$(langs_guard "$2")" != "2" ] && fail "S45 — niet geblokkeerd: $1"
  return 0
}

# Een scheidingsteken binnen een gequote string breekt het commando niet op. Dit
# zijn alledaagse commando's: een commitboodschap die dit onderwerp noemt, of
# documentatie die de guard beschrijft.
toegestaan "puntkomma in een boodschap"  'git commit -m "note; git clean -fd is bad"'
toegestaan "ampersand in een boodschap"  'git commit -m "recipe & git reset --hard combo"'
toegestaan "pipe in een echo"            'echo "zie README | git reset --hard staat erin"'
toegestaan "meerregelige boodschap"      'git commit -m "regel een
git reset --hard staat hier als tekst"'

# Een heredoc-body is data. De terminator moet exact de hele regel zijn; een
# substring-match zou de body te vroeg beeindigen en de tekst erna alsnog als
# syntaxis lezen - precies de fout die hier gedicht wordt.
toegestaan "heredoc met git in de body" 'cat <<EOF >> README.md
git reset --hard
EOF'
toegestaan "heredoc met gequote delimiter" "cat <<'EOF' >> doc.md
git push origin main
EOF"
# De terminator moet exact de hele regel zijn. Bevat de body een regel waarin
# de delimiter alleen voorkomt, dan eindigt de body daar niet - anders zou de
# tekst erna alsnog als commando gelezen worden.
toegestaan "delimiter als woord in de body" 'cat <<EOF > x
dit is niet EOF maar gewone tekst
git reset --hard
EOF'
toegestaan "heredoc met tabs (<<-)"     "$(printf 'cat <<-EOF > x\n\tgit clean -fd\n\tEOF\n')"

# Maar een echt commando ná een heredoc wordt gewoon beoordeeld.
geblokkeerd "commando na een heredoc"   'cat <<EOF > x
tekst
EOF
git reset --hard'

# En quotes rond een vlag horen bij het commando, niet bij data.
geblokkeerd "gequote vlag"               'git reset "--hard"'
geblokkeerd "gequote punt"               'git checkout -- "."'
geblokkeerd "backslash-escape"           'git reset \-\-hard'

# Onbalans in de quoting is geen commando dat we kunnen lezen; dan niet gokken.
toegestaan "quoting die niet sluit"      'git commit -m "open'

test_klaar

#!/usr/bin/env bash
# S45 — Text inside quotes is data, not a command.
# Covers: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S45 — hooks/git-guardrails is missing"; test_done; }

workdir="$(fresh_project workdir)"

langs_guard() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$workdir" "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}
toegestaan() {
  [ "$(langs_guard "$2")" = "2" ] && fail "S45 — wrongly blocked: $1"
  return 0
}
geblokkeerd() {
  [ "$(langs_guard "$2")" != "2" ] && fail "S45 — not blocked: $1"
  return 0
}

# A separator character inside a quoted string does not break the command apart.
# These are everyday commands: a commit message that mentions this topic, or
# documentation describing the guard.
toegestaan "semicolon in a message"  'git commit -m "note; git clean -fd is bad"'
toegestaan "ampersand in a message"  'git commit -m "recipe & git reset --hard combo"'
toegestaan "pipe in an echo"            'echo "zie README | git reset --hard staat erin"'
toegestaan "multi-line message"      'git commit -m "regel een
git reset --hard staat hier als tekst"'

# A heredoc body is data. The terminator must be exactly the whole line; a
# substring match would end the body too early and still read the text after
# it as syntax - exactly the bug being fixed here.
toegestaan "heredoc with git in the body" 'cat <<EOF >> README.md
git reset --hard
EOF'
toegestaan "heredoc with quoted delimiter" "cat <<'EOF' >> doc.md
git push origin main
EOF"
# The terminator must be exactly the whole line. If the body contains a line
# where the delimiter appears only as part of something else, the body does
# not end there - otherwise the text after it would still be read as a
# command.
toegestaan "delimiter as a word in the body" 'cat <<EOF > x
this is not EOF but ordinary text
git reset --hard
EOF'
toegestaan "heredoc with tabs (<<-)"     "$(printf 'cat <<-EOF > x\n\tgit clean -fd\n\tEOF\n')"

# But a real command after a heredoc is judged normally.
geblokkeerd "command after a heredoc"   'cat <<EOF > x
tekst
EOF
git reset --hard'

# And quotes around a flag belong to the command, not to data.
geblokkeerd "quoted flag"               'git reset "--hard"'
geblokkeerd "quoted dot"               'git checkout -- "."'
geblokkeerd "backslash escape"           'git reset \-\-hard'

# An imbalance in the quoting is not a command we can read; do not guess then.
toegestaan "quoting that does not close"      'git commit -m "open'

test_done

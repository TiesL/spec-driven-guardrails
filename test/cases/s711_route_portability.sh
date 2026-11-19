#!/usr/bin/env bash
# S711 — The wrapper is portable: no `timeout`, `gtimeout`, `nc`, bash 4 or bare `python3` (#707; AC11, portability half)
# Covers: F75
#
# Seam: a static scan of route-child.sh (comments ignored, command position
# for the three commands) checked against planted-violation copies, and a full
# run under /bin/bash with sentinel timeout/gtimeout/nc shims and a logging
# python3 shim first on PATH. The S701-S707 cases also start the wrapper as
# `/bin/bash route-child.sh` (RC_LAUNCH in the shared helpers).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

[ -f "$RC_ROUTE" ] || { fail "S711 — route-child.sh does not exist"; test_done; }

# scan <file>: one line per portability violation; empty when clean.
scan() {
  python3 -I - "$1" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
out = []
if not re.match(r"^#!.*\bbash\b", lines[0]):
    out.append("1: shebang does not name bash")
def code(line):
    # Drop a comment: a # at the start of a word, outside quotes.
    q, i = None, 0
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\" and q == "\"":
                i += 2
                continue
            if c == q:
                q = None
        elif c in "\"\x27":
            q = c
        elif c == "#" and (i == 0 or line[i - 1] in " \t;|&("):
            return line[:i]
        i += 1
    return line
CMDPOS = r"(?:^|[;&|(`]|\$\(|\b(?:then|do|else|elif|exec|command|if|while|until|time|!)\s)\s*"
rules = [
    ("command-position timeout/gtimeout/nc", re.compile(CMDPOS + r"(timeout|gtimeout|nc)(?=\s|$|;|\))")),
    ("bash 4: declare -A / local -A", re.compile(r"\b(declare|local|typeset)\s+-[a-zA-Z]*A")),
    ("bash 4: mapfile/readarray", re.compile(r"\b(mapfile|readarray)\b")),
    ("bash 4: case modification", re.compile(r"\$\{[#!]?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,,?|\^\^?)")),
    ("bash 4: coproc", re.compile(r"\bcoproc\b")),
    ("bash 4: [[ -v", re.compile(r"\[\[\s+-v\b")),
    ("bash 4: &>>", re.compile(r"&>>")),
    ("bash 4: |&", re.compile(r"\|&")),
]
for n, raw in enumerate(lines[1:], 2):
    c = code(raw)
    for name, rx in rules:
        if rx.search(c):
            out.append("%d: %s" % (n, name))
    for m in re.finditer(r"(?<![A-Za-z0-9_./-])python3(?![A-Za-z0-9_.-])", c):
        rest = c[m.end():]
        if not re.match(r"\s+-I(\s|$)", rest):
            out.append("%d: python3 without -I as its first argument" % n)
print("\n".join(out))
PY
}

got="$(scan "$RC_ROUTE")"
[ -z "$got" ] || fail "S711/static — route-child.sh has portability violations:
$got"

# Planted copies: every rule reports, comments do not count.
plant() { # <label> <line>
  cp "$RC_ROUTE" "$SANDBOX/planted.sh"
  printf '%s\n' "$2" >>"$SANDBOX/planted.sh"
  [ -n "$(scan "$SANDBOX/planted.sh")" ] || fail "S711/planted — '$1' was not reported: $2"
}
plant declare-A 'declare -A seen'
plant local-A 'f() { local -A m; }'
plant mapfile 'mapfile -t lines <x'
plant readarray 'readarray lines <x'
plant lower 'x="${name,,}"'
plant upper 'x="${name^^}"'
plant coproc 'coproc cat'
plant test-v '[[ -v name ]] && echo'
plant append-both 'echo x &>>log'
plant pipe-both 'echo x |& cat'
plant timeout 'timeout 3 curl x'
plant timeout-mid 'a=1; timeout 3 curl x'
plant timeout-subst 'x="$(gtimeout 3 curl x)"'
plant nc 'if nc -z 127.0.0.1 1; then :; fi'
plant python-bare "python3 -c 'print(1)'"
plant python-later 'out="$(python3 - <<EOF'
cp "$RC_ROUTE" "$SANDBOX/comments.sh"
printf '%s\n' '# no timeout, no nc, no mapfile, never ${x,,}; python3 -c is not used' 'echo once in sync' >>"$SANDBOX/comments.sh"
[ -z "$(scan "$SANDBOX/comments.sh")" ] || fail "S711/planted — comments or words like once/sync were reported: $(scan "$SANDBOX/comments.sh")"

# --- dynamic run under /bin/bash with shims -------------------------------------
echo "S711 — /bin/bash is: $(/bin/bash --version | head -n 1)" >&2
case "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" in
  3) ;;
  *) echo "S711 — /bin/bash is not 3.x here; the static scan above is the authoritative gate" >&2 ;;
esac
rc_init
real_python="$(command -v python3)"
cat >"$RC/bin/python3" <<SHIM
#!/bin/sh
printf '%s\n' "\${1:-}" >>"$RC/log/python3.log"
exec "$real_python" "\$@"
SHIM
chmod +x "$RC/bin/python3"
RC_LAUNCH=(/bin/bash "$RC_ROUTE")
mkdir -p "$RC_TOP/.claude"
echo '{"permissions":{}}' >"$RC/cfg/settings.json"
echo '{}' >"$RC_TOP/.claude/settings.json"

rc_run claude -- "$RC/bin/claude" -p x
[ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S711/run/claude — exit $rc_status, $rc_err"
rc_run codex -- "$RC/bin/codex" exec x
[ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S711/run/codex — exit $rc_status, $rc_err"
rc_env_set "SDG_MODEL_ROUTE=off"
rc_run claude -- "$RC/bin/claude" -p x
[ "$rc_status" = 0 ] || fail "S711/run/off-claude — exit $rc_status"
rc_run codex -- "$RC/bin/codex" exec x
[ "$rc_status" = 0 ] || fail "S711/run/off-codex — exit $rc_status"
rc_env_reset
rc_env_set "ANTHROPIC_BASE_URL=http://localhost:9"
rc_run claude -- "$RC/bin/claude" -p x
[ "$rc_status" = 4 ] || fail "S711/run/refused — exit $rc_status"
rc_env_reset
echo 7 >"$RC/probe.exit"
rc_run claude -- "$RC/bin/claude" -p x
[ "$rc_status" = 3 ] || fail "S711/run/down-claude — exit $rc_status"
rc_run codex -- "$RC/bin/codex" exec x
[ "$rc_status" = 3 ] || fail "S711/run/down-codex — exit $rc_status"
rm -f "$RC/probe.exit"

for s in timeout gtimeout nc; do
  [ ! -e "$RC/log/sentinel-$s" ] || fail "S711/run — $s was called"
done
[ -s "$RC/log/python3.log" ] || fail "S711/run — the python3 shim logged nothing (shim not on PATH?)"
bad="$(grep -v '^-I' "$RC/log/python3.log")"
[ -z "$bad" ] || fail "S711/run — python3 was called without -I first: $bad"

test_done

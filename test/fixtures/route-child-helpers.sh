#!/usr/bin/env bash
# test/fixtures/route-child-helpers.sh — fixture builders for the S700-S713
# cases (#707, A61): a stub child, a probe stub, sentinel shims, fixture
# projects with an adoption answer, and a way to run route-child.sh as a
# process with a built environment (`env -i` plus only what a case sets) and
# an explicit working directory. No case here starts a model or reaches a
# proxy: the probe is a stub (SDG_ROUTE_PROBE) or a fake `curl` first on PATH,
# and the managed-settings path is always a sandbox path
# (SDG_ROUTE_MANAGED_SETTINGS) unless a case says otherwise.
#
# Source, don't execute. Needs a sandbox (test/lib.sh sandbox_create) first.
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

RC_ROUTE="$TEST_REPO_ROOT/route-child.sh"

# rc_init: builds $RC with
#   bin/      stub children `claude`, `codex`, `codexx`; a fake `curl`
#             (never the real one); sentinel `timeout`, `gtimeout`, `nc`
#   probe/    the probe stub named by SDG_ROUTE_PROBE
#   log/      probe.log, curl.log, sentinel-<name> markers
#   home/ cfg/ codexhome/ managed/   fixture HOME, CLAUDE_CONFIG_DIR,
#             CODEX_HOME (valid Caveman config) and managed-settings dir
# and resets the run environment (rc_env_reset) and launcher (RC_LAUNCH).
rc_init() {
  RC="$SANDBOX/rc"
  mkdir -p "$RC/bin" "$RC/probe" "$RC/log" "$RC/home" "$RC/cfg" \
    "$RC/codexhome" "$RC/managed" "$RC/elsewhere"
  # Stub child: environment (NUL-separated, sorted) and arguments (NUL-
  # separated) to $STUB_OUT.env / .args, a `started` marker, exit $STUB_EXIT.
  cat >"$RC/bin/claude" <<'STUB'
#!/usr/bin/env bash
out="${STUB_OUT:?STUB_OUT is not set}"
python3 -I -c '
import os, sys
out = sys.argv[1]
with open(out + ".env", "wb") as f:
    for k in sorted(os.environb):
        f.write(k + b"=" + os.environb[k] + b"\0")
with open(out + ".args", "wb") as f:
    for a in sys.argv[2:]:
        f.write(os.fsencode(a) + b"\0")
' "$out" "$@"
: >"$out.started"
exit "${STUB_EXIT:-0}"
STUB
  chmod +x "$RC/bin/claude"
  cp "$RC/bin/claude" "$RC/bin/codex"
  cp "$RC/bin/claude" "$RC/bin/codexx"
  # Probe stub: argv to log/probe.log, exit status from probe.exit (default 0);
  # with probe.recenv present, also its environment (NUL-separated, sorted,
  # as the stub child records it) to log/probe.env (S704 round 4, r1).
  cat >"$RC/probe/probe" <<'PROBE'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s\n' "$*" >>"$d/log/probe.log"
if [ -e "$d/probe.recenv" ]; then
  python3 -I -c '
import os, sys
with open(sys.argv[1], "wb") as f:
    for k in sorted(os.environb):
        f.write(k + b"=" + os.environb[k] + b"\0")
' "$d/log/probe.env"
fi
s="$(cat "$d/probe.exit" 2>/dev/null)"
exit "${s:-0}"
PROBE
  chmod +x "$RC/probe/probe"
  # Fake curl: argv to log/curl.log, exit status from curl.exit (default 7).
  cat >"$RC/bin/curl" <<'CURL'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s\n' "$*" >>"$d/log/curl.log"
s="$(cat "$d/curl.exit" 2>/dev/null)"
exit "${s:-7}"
CURL
  chmod +x "$RC/bin/curl"
  local s
  for s in timeout gtimeout nc; do
    printf '#!/usr/bin/env bash\n: >"$(cd "$(dirname "$0")/.." && pwd)/log/sentinel-%s"\nexit 97\n' "$s" >"$RC/bin/$s"
    chmod +x "$RC/bin/$s"
  done
  rc_codex_config valid
  RC_LAUNCH=(/bin/bash "$RC_ROUTE")
  rc_project yes
  rc_env_reset
}

# rc_path: the PATH every run gets: the fixture bin first, then the
# directories of the real git and python3, then /usr/bin:/bin.
rc_path() {
  local p="$RC/bin" d t
  for t in git python3; do
    d="$(dirname "$(command -v "$t")")"
    case ":$p:" in *":$d:"*) ;; *) p="$p:$d" ;; esac
  done
  printf '%s:/usr/bin:/bin' "$p"
}

# rc_env_reset: the default routed-run environment.
rc_env_reset() {
  RC_ENV=(
    "PATH=$(rc_path)"
    "HOME=$RC/home"
    "CLAUDE_CONFIG_DIR=$RC/cfg"
    "CODEX_HOME=$RC/codexhome"
    "SPEC_DRIVEN_GUARDRAILS_DIR=$SANDBOX/workflow"
    "SDG_ROUTE_PROBE=$RC/probe/probe"
    "SDG_ROUTE_MANAGED_SETTINGS=$RC/managed/managed-settings.json"
    "STUB_OUT=$RC/child"
  )
}

# rc_env_set NAME=value: add or replace one variable (value may be empty).
rc_env_set() {
  rc_env_del "${1%%=*}"
  RC_ENV+=("$1")
}

# rc_env_del NAME: remove one variable from the run environment.
rc_env_del() {
  local kept=() e
  for e in "${RC_ENV[@]}"; do
    case "$e" in "$1="*) ;; *) kept+=("$e") ;; esac
  done
  RC_ENV=("${kept[@]}")
}

# rc_project <answer>: a fixture git project; sets RC_TOP and RC_CWD (a
# subdirectory, so working directory and top level differ). <answer>:
# yes, no, pending, absent (no row), nofile (no WORKFLOW-ADOPTION.md),
# notes (yes only in the Notes column), prefixed (the id with a suffix).
rc_project() {
  RC_TOP="$RC/proj"
  if [ ! -d "$RC_TOP/.git" ]; then
    mkdir -p "$RC_TOP/sub/dir"
    git -C "$RC_TOP" init -q -b main
  fi
  RC_CWD="$RC_TOP/sub/dir"
  rc_answer "$1"
}

# rc_answer <answer>: rewrites the fixture project's answer only (same paths).
rc_answer() {
  local f="$RC_TOP/WORKFLOW-ADOPTION.md"
  rm -f "$f"
  [ "$1" = nofile ] && return 0
  {
    echo "# Adoption of shared workflow changes"
    echo
    echo "| Change | Answer | Date | Notes |"
    echo "|---|---|---|---|"
    echo "| process-multi-agent-roles | yes | 2026-11-19 | fixture |"
    case "$1" in
      yes|no|pending) echo "| process-model-routing | $1 | 2026-11-19 | fixture |" ;;
      notes) echo "| process-model-routing | no | 2026-11-19 | yes |" ;;
      prefixed) echo "| process-model-routing-extra | yes | 2026-11-19 | fixture |" ;;
      absent) ;;
    esac
  } >"$f"
}

# rc_codex_config <variant>: writes $RC/codexhome/config.toml (S702/S703
# variants). Every variant but `unparsable` is legal TOML.
rc_codex_config() {
  local f="$RC/codexhome/config.toml" top="" tables="" hk=http_headers v="$1"
  rm -f "$f"
  # The `-env` suffix (S702 s): the same form with env_http_headers instead.
  case "$v" in *-env) hk=env_http_headers; v="${v%-env}" ;; esac
  local caveman_table='[model_providers.caveman]
name = "Caveman"
base_url = "http://localhost:1/chatgpt"
wire_api = "responses"
requires_openai_auth = true'
  local mcp_table='[mcp_servers.x]
command = "x"
args = [
  "--flag", # a comment inside an array
  "value",
]'
  local valid_top='# fixture Codex config
model = "gpt-x"
model_provider = "caveman"'
  case "$v" in
    valid) top="$valid_top" ;;
    header-other) top="$valid_top"; tables='[model_providers.other]
name = "Other"
http_headers = { "x-a" = "b" }' ;;
    profile) top="$valid_top"; tables='[profiles.x]
model_provider = "openai"' ;;
    profile-direct) top="$valid_top
profile = \"direct\""; tables='[profiles.direct]
model_provider = "openai"' ;;
    profile-cv) top='model_provider = "openai"
profile = "cv"'; tables='[profiles.cv]
model_provider = "caveman"' ;;
    profile-missing) top="$valid_top
profile = \"missing\"" ;;
    profile-noprovider) top="$valid_top
profile = \"p\""; tables='[profiles.p]
model = "gpt-y"' ;;
    profile-inline) top="$valid_top
profile = \"d\"
profiles = { d = { model_provider = \"openai\" } }" ;;
    profile-dotted) top="$valid_top
profile = \"d\"
profiles.d.model_provider = \"openai\"" ;;
    off-profile-caveman) top="$valid_top
profile = \"c\""; tables='[profiles.c]
model_provider = "caveman"' ;;
    off-profile-inline) top="$valid_top
profile = \"c\"
profiles = { c = { model_provider = \"caveman\" } }" ;;
    # S703 (o9)-(o13): a base-URL key at top level, in the selected profile,
    # or (control) only in a profile that nothing selects.
    off-base-url-top|off-chatgpt-url-top)
      local bk=openai_base_url
      [ "$v" = off-chatgpt-url-top ] && bk=chatgpt_base_url
      top="$valid_top
$bk = \"http://tok-7f3a\"" ;;
    off-base-url-profile|off-chatgpt-url-profile)
      local pk=openai_base_url
      [ "$v" = off-chatgpt-url-profile ] && pk=chatgpt_base_url
      top="$valid_top
profile = \"b\""; tables="[profiles.b]
model_provider = \"openai\"
$pk = \"http://tok-7f3a\"" ;;
    off-base-url-unselected) top="$valid_top"; tables='[profiles.other]
openai_base_url = "http://tok-7f3a"
chatgpt_base_url = "http://tok-7f3a"' ;;
    header) top='model_provider = "caveman"'; caveman_table="$caveman_table
$hk = { \"x-a\" = \"b\" }" ;;
    inline-provider)
      printf 'model_provider = "caveman"\nmodel_providers = { caveman = { name = "C", base_url = "http://localhost:1/chatgpt", %s = { "x-a" = "b" } } }\n' "$hk" >"$f"
      return ;;
    providers-table)
      printf 'model_provider = "caveman"\n\n[model_providers]\ncaveman = { name = "C", %s = { "x-a" = "b" } }\n' "$hk" >"$f"
      return ;;
    dotted-provider)
      printf 'model_provider = "caveman"\nmodel_providers.caveman.name = "C"\nmodel_providers.caveman.%s = { "x-a" = "b" }\n' "$hk" >"$f"
      return ;;
    header-subtable) top="$valid_top"; tables="[model_providers.caveman.$hk]
\"x-a\" = \"b\"" ;;
    inline-both)
      printf '%s\n' 'model_provider = "caveman"' \
        'model_providers = { caveman = { name = "C", base_url = "http://localhost:1/chatgpt", wire_api = "responses", requires_openai_auth = true }, other = { http_headers = { "x-a" = "b" } } }' >"$f"
      return ;;
    openai)
      printf 'model_provider = "openai"\n\n[model_providers.caveman]\nname = "Caveman"\n' >"$f"; return ;;
    nokey)
      printf 'model = "gpt-x"\n\n[model_providers.caveman]\nname = "Caveman"\n' >"$f"; return ;;
    comment)
      printf '# model_provider = "caveman"\nmodel_provider = "openai" # was caveman\n\n[model_providers.caveman]\nname = "Caveman"\n' >"$f"; return ;;
    unparsable)
      printf 'model_provider = "caveman\nthis line is not toml\n[model_providers.caveman\n' >"$f"; return ;;
    missing) return ;;
    *) echo "rc_codex_config: unknown variant $1" >&2; return 1 ;;
  esac
  printf '%s\n\n%s\n\n%s\n' "$top" "$caveman_table" "$mcp_table" >"$f"
  [ -n "$tables" ] && printf '\n%s\n' "$tables" >>"$f"
  return 0
}

# --- Codex .env variants (S702 round 5, reused by S703 and S704) -------------
# rc_codex_dotenv <variant> [<dir>]: writes <dir>/.env (default the fixture
# CODEX_HOME, $RC/codexhome); the stub codex never loads it. Every file but
# xc2 starts with FOO=1, so the line under test is not the first line.
#   x1  NO_PROXY=tok-7f3a
#   x2  no_proxy=            (empty value)
#   x3  export NO_PROXY = "tok-7f3a"
#   x4  the x1 file with mode 000 (unreadable)
#   xc1 HTTP_PROXY=http://corp:3128 and FOO=1 only
#   xc2 only the comment line # NO_PROXY=x
rc_codex_dotenv() {
  local d="${2:-$RC/codexhome}" f
  f="$d/.env"
  mkdir -p "$d"
  [ -e "$f" ] && chmod 600 "$f"
  rm -f "$f"
  case "$1" in
    x1|x4) printf 'FOO=1\nNO_PROXY=tok-7f3a\n' >"$f" ;;
    x2) printf 'FOO=1\nno_proxy=\n' >"$f" ;;
    x3) printf 'FOO=1\nexport NO_PROXY = "tok-7f3a"\n' >"$f" ;;
    xc1) printf 'FOO=1\nHTTP_PROXY=http://corp:3128\n' >"$f" ;;
    xc2) printf '# NO_PROXY=x\n' >"$f" ;;
    *) echo "rc_codex_dotenv: unknown variant $1" >&2; return 1 ;;
  esac
  [ "$1" = x4 ] && chmod 000 "$f"
  return 0
}

# rc_dotenv_clear: removes every fixture .env (CODEX_HOME, $HOME/.codex and
# $RC/elsewhere) and the $HOME/.codex config copy.
rc_dotenv_clear() {
  local d
  for d in "$RC/codexhome" "$RC/home/.codex" "$RC/elsewhere"; do
    [ -e "$d/.env" ] && chmod 600 "$d/.env"
    rm -f "$d/.env"
  done
  rm -rf "$RC/home/.codex"
  rm -f "$RC/elsewhere/config.toml"
}

# rc_run <wrapper args...>: runs the wrapper; sets rc_status, rc_out, rc_err,
# rc_started (1 when the stub child started) and rc_probe_calls.
rc_run() {
  rm -f "$RC/child.env" "$RC/child.args" "$RC/child.started"
  : >"$RC/log/probe.log"
  (cd "$RC_CWD" && exec env -i "${RC_ENV[@]}" "${RC_LAUNCH[@]}" "$@") >"$RC/out" 2>"$RC/err"
  rc_status=$?
  rc_out="$(cat "$RC/out")"
  rc_err="$(cat "$RC/err")"
  rc_started=0
  [ -e "$RC/child.started" ] && rc_started=1
  rc_probe_calls="$(wc -l <"$RC/log/probe.log" | tr -d ' ')"
  return 0
}

# rc_direct <command args...>: the same command run directly (through a
# bash `exec`, like the wrapper's own), same environment and directory; its
# record is kept as $RC/direct.env and $RC/direct.args.
rc_direct() {
  rm -f "$RC/child.env" "$RC/child.args" "$RC/child.started" "$RC/direct.env" "$RC/direct.args"
  (cd "$RC_CWD" && exec env -i "${RC_ENV[@]}" /bin/bash -c 'exec "$@"' bash "$@") >/dev/null 2>&1
  mv "$RC/child.env" "$RC/direct.env" 2>/dev/null
  mv "$RC/child.args" "$RC/direct.args" 2>/dev/null
  rm -f "$RC/child.started"
}

# rc_env_diff [<base env file> <other env file>]: the child's environment
# against the direct run's (by default), one line per difference, sorted:
# "+NAME=value" (added or changed; a newline in the value is shown as \n) or
# "-NAME" (removed). Empty when identical.
rc_env_diff() {
  python3 -I - "${1:-$RC/direct.env}" "${2:-$RC/child.env}" <<'PY'
import sys
def load(p):
    d = {}
    with open(p, "rb") as f:
        for item in f.read().split(b"\0"):
            if item:
                k, _, v = item.partition(b"=")
                d[k] = v
    return d
a, b = load(sys.argv[1]), load(sys.argv[2])
out = []
for k in sorted(set(a) | set(b)):
    if k not in b:
        out.append(b"-" + k)
    elif a.get(k) != b[k]:
        out.append(b"+" + k + b"=" + b[k].replace(b"\n", b"\\n"))
sys.stdout.write(b"\n".join(out).decode("utf-8", "replace") + ("\n" if out else ""))
PY
}

# rc_args_equal_direct: 0 when the child's arguments equal the direct run's.
rc_args_equal_direct() {
  cmp -s "$RC/direct.args" "$RC/child.args"
}

# rc_args_file <args...>: writes the expected NUL-separated argument list to
# $RC/expected.args.
rc_args_file() {
  : >"$RC/expected.args"
  local a
  for a in "$@"; do printf '%s\0' "$a" >>"$RC/expected.args"; done
}

# rc_tree_hash <dir...>: one digest over every file (path and content) under
# the given directories, for "byte-identical afterwards" assertions.
rc_tree_hash() {
  python3 -I - "$@" <<'PY'
import hashlib, os, sys
h = hashlib.sha256()
for root in sys.argv[1:]:
    for d, dirs, files in sorted(os.walk(root)):
        dirs.sort()
        for name in sorted(files):
            p = os.path.join(d, name)
            h.update(p.encode() + b"\0")
            try:
                st = os.lstat(p)
                h.update(str(st.st_mode).encode())
                if os.path.isfile(p) and os.access(p, os.R_OK):
                    with open(p, "rb") as f:
                        h.update(f.read())
            except OSError:
                h.update(b"?")
print(h.hexdigest())
PY
}

# rc_line_count <text>: number of non-empty lines.
rc_line_count() {
  if [ -z "$1" ]; then echo 0; return; fi
  printf '%s\n' "$1" | awk 'NF{n++} END{print n+0}'
}

# rc_expected_claude_diff [<inherited NO_PROXY> [<inherited headers> [<inherited
# no_proxy>]]]: the five additions a routed Claude child must show, in
# rc_env_diff form (sorted bytewise: upper case, then `_`, then lower case).
rc_expected_claude_diff() {
  local np="127.0.0.1,localhost" lnp="127.0.0.1,localhost" hd="x-cave-transforms: caveman.pass-through.v1"
  [ -n "${1:-}" ] && np="$1,$np"
  [ -n "${2:-}" ] && hd="$2\\n$hd"
  [ -n "${3:-}" ] && lnp="$3,$lnp"
  printf '+ANTHROPIC_BASE_URL=http://127.0.0.1:8787/w/claude\n'
  printf '+ANTHROPIC_CUSTOM_HEADERS=%s\n' "$hd"
  printf '+NO_PROXY=%s\n' "$np"
  printf '+_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1\n'
  printf '+no_proxy=%s\n' "$lnp"
}

# rc_added_names: the names of the variables the last run added or changed
# against the direct run (rc_env_diff "+" lines), one per line.
rc_added_names() {
  rc_env_diff | sed -n 's/^+\([^=]*\)=.*/\1/p'
}

# --- inherited proxy environments (S702 round 4, reused by S703 and S704) -----
# rc_proxy_env <e1|e2|e3|e4|e5>: sets the inherited proxy variables of one
# environment on the run environment (after rc_env_reset) and records the
# inherited NO_PROXY and no_proxy in RC_INH_NP and RC_INH_LNP for
# rc_expected_loopback_diff.
#   e1 clean (none of the proxy variables)
#   e2 http_proxy and HTTPS_PROXY, only the lowercase no_proxy=corp.internal
#   e3 the same proxies, only the uppercase NO_PROXY=corp.example
#   e4 NO_PROXY and no_proxy set but empty
#   e5 NO_PROXY=corp.example and no_proxy=corp.internal
RC_PROXY_ENVS="e1 e2 e3 e4 e5"
rc_proxy_env() {
  local n
  for n in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY NO_PROXY no_proxy ALL_PROXY all_proxy; do
    rc_env_del "$n"
  done
  RC_INH_NP=""
  RC_INH_LNP=""
  case "$1" in
    e1) ;;
    e2) rc_env_set "http_proxy=http://corp:3128"; rc_env_set "HTTPS_PROXY=http://corp:3128"
        rc_env_set "no_proxy=corp.internal"; RC_INH_LNP=corp.internal ;;
    e3) rc_env_set "http_proxy=http://corp:3128"; rc_env_set "HTTPS_PROXY=http://corp:3128"
        rc_env_set "NO_PROXY=corp.example"; RC_INH_NP=corp.example ;;
    e4) rc_env_set "NO_PROXY="; rc_env_set "no_proxy=" ;;
    e5) rc_env_set "NO_PROXY=corp.example"; rc_env_set "no_proxy=corp.internal"
        RC_INH_NP=corp.example; RC_INH_LNP=corp.internal ;;
    *) echo "rc_proxy_env: unknown environment $1" >&2; return 1 ;;
  esac
}

# rc_expected_loopback_diff: the exactly two differences a routed Codex child
# (and the probe) must show against a direct run, in rc_env_diff form, for the
# environment rc_proxy_env set last: each spelling its own inherited value,
# one comma, then 127.0.0.1,localhost (the loopback alone when unset or empty).
rc_expected_loopback_diff() {
  local lb="127.0.0.1,localhost" np lnp
  np="$lb"; lnp="$lb"
  [ -n "${RC_INH_NP:-}" ] && np="$RC_INH_NP,$lb"
  [ -n "${RC_INH_LNP:-}" ] && lnp="$RC_INH_LNP,$lb"
  printf '+NO_PROXY=%s\n+no_proxy=%s\n' "$np" "$lnp"
}

# rc_probe_direct <args...>: the probe stub run directly (a bash child, like
# the wrapper's own call), same environment and directory, recording its
# environment as $RC/probe-direct.env; the probe log is left empty.
rc_probe_direct() {
  rm -f "$RC/log/probe.env" "$RC/probe-direct.env"
  : >"$RC/probe.recenv"
  (cd "$RC_CWD" && exec env -i "${RC_ENV[@]}" /bin/bash -c '"$@"; exit $?' bash "$RC/probe/probe" "$@") >/dev/null 2>&1
  mv "$RC/log/probe.env" "$RC/probe-direct.env" 2>/dev/null
  : >"$RC/log/probe.log"
}

# --- the real curl against an inherited proxy (S704 round 4, r2) -------------------
# rc_real_curl: prints the absolute path of a real `curl` from the test's own
# PATH (never the fixture fake); empty when there is none.
rc_real_curl() {
  local d
  local IFS=:
  for d in $PATH; do
    case "$d" in "$RC"/*|"$RC") continue ;; esac
    [ -x "$d/curl" ] && { printf '%s\n' "$d/curl"; return 0; }
  done
  return 0
}

# rc_free_port: a free loopback port, bound and released.
rc_free_port() {
  python3 -I -c '
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

# rc_listener_start: a scratch HTTP listener (python3 -I) on 127.0.0.1 at a
# free port, answering any request with HTTP 200 and logging its request
# line to $RC/log/listener.log; sets RC_LISTENER_PORT and RC_LISTENER_PID.
# Returns 1 when it does not come up.
rc_listener_start() {
  cat >"$RC/listener.py" <<'PY'
import http.server, sys
log, ready = sys.argv[1], sys.argv[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def answer(self):
        with open(log, "a") as f:
            f.write(self.requestline + "\n")
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()
    do_GET = do_HEAD = do_POST = do_PUT = do_CONNECT = answer
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(ready + ".tmp", "w") as f:
    f.write(str(server.server_address[1]))
import os
os.rename(ready + ".tmp", ready)
server.serve_forever()
PY
  rm -f "$RC/listener.ready"
  : >"$RC/log/listener.log"
  python3 -I "$RC/listener.py" "$RC/log/listener.log" "$RC/listener.ready" >/dev/null 2>&1 &
  RC_LISTENER_PID=$!
  local n=0
  while [ ! -s "$RC/listener.ready" ] && [ "$n" -lt 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  [ -s "$RC/listener.ready" ] || return 1
  RC_LISTENER_PORT="$(cat "$RC/listener.ready")"
}

# rc_listener_stop: stops the listener, if any.
rc_listener_stop() {
  if [ -n "${RC_LISTENER_PID:-}" ]; then
    kill "$RC_LISTENER_PID" 2>/dev/null
    wait "$RC_LISTENER_PID" 2>/dev/null
  fi
  RC_LISTENER_PID=""
  return 0
}

# rc_curl_shim <real curl> <port P>: writes $RC/probe/curlshim, a probe for
# SDG_ROUTE_PROBE that logs its argv to log/probe.log, then execs the real
# curl with the same argv except `:8787` replaced by `:P`, its environment
# untouched. The existing probe seam: the wrapper keeps its fixed URL.
rc_curl_shim() {
  printf '%s\n' "$1" >"$RC/real-curl"
  printf '%s\n' "$2" >"$RC/shim.port"
  cat >"$RC/probe/curlshim" <<'SHIM'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s\n' "$*" >>"$d/log/probe.log"
real="$(cat "$d/real-curl")"
port="$(cat "$d/shim.port")"
args=()
for a in "$@"; do args+=("${a//:8787/:$port}"); done
exec "$real" "${args[@]}"
SHIM
  chmod +x "$RC/probe/curlshim"
}

# --- planted mutants (shared seam, review round 1) -----------------------------
# rc_kill <label> <old> <new> <assertion> [args...]: plants a mutant copy of
# route-child.sh (with lib/changes.sh beside it) in which the text <old>,
# found exactly once, becomes <new>; runs the assertion against that copy with
# its failure lines hidden; fails the case when the assertion stays green (the
# mutant survived) or <old> is not found (a test defect). The assertion is the
# same function the case runs against the real wrapper.
rc_kill() {
  local label="$1" old="$2" new="$3" dir="$SANDBOX/mutant" saved launch
  shift 3
  rm -rf "$dir"
  mkdir -p "$dir/lib"
  cp "$TEST_REPO_ROOT/lib/changes.sh" "$dir/lib/changes.sh"
  if ! python3 -I - "$RC_ROUTE" "$dir/route-child.sh" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
PY
  then
    fail "$label — test defect: the mutant's anchor text is not found exactly once in route-child.sh"
    return 0
  fi
  launch=("${RC_LAUNCH[@]}")
  RC_LAUNCH=(/bin/bash "$dir/route-child.sh")
  saved=$_test_failures
  { "$@"; } 2>/dev/null
  RC_LAUNCH=("${launch[@]}")
  if [ "$_test_failures" = "$saved" ]; then
    fail "$label — the planted mutant survived: $*"
  else
    _test_failures=$saved
  fi
  return 0
}

# rc_expect_red <label> <assertion> [args...]: runs an assertion that must
# fail (a planted negative control on text, not on the wrapper), hiding its
# failure lines; fails the case when it passed.
rc_expect_red() {
  local label="$1" saved=$_test_failures
  shift
  { "$@"; } 2>/dev/null
  if [ "$_test_failures" = "$saved" ]; then
    fail "$label — the planted negative control passed: $*"
  else
    _test_failures=$saved
  fi
  return 0
}

# --- not-yes wording checker (S704, S709, S713) ---------------------------------
# rc_not_yes_violations <file> <plain|codex>: prints one line per broken rule
# (n1, n2, n3) of the shared not-yes wording checker for the text in <file>;
# prints nothing when the text passes. Sentences end at `.`, `!` or `?`
# followed by white space or the end, at `;`, or at a blank line; Markdown
# markup (backticks, `*`, fenced blocks, HTML comments) is ignored. A
# no-sentence mentions the answer `no` next to process-model-routing or
# "answer"/"answering". n1: no no-sentence says direct, uncut, uncompressed,
# not compressed or intact unless it names SDG_MODEL_ROUTE=off; n2: some
# no-sentence names the wrapper; n3 (codex): some sentence names Codex, the
# user's own config and compression together.
rc_not_yes_violations() {
  python3 -I - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
kind = sys.argv[2]
text = re.sub(r"```.*?```", " ", text, flags=re.S)
text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
text = text.replace("`", "").replace("**", "").replace("*", "")
sentences = []
for block in re.split(r"\n[ \t]*\n", text):
    flat = re.sub(r"\s+", " ", block)
    sentences += [s.strip() for s in re.split(r"(?<=[.!?])(?=\s|$)|;", flat) if s.strip()]
NO = re.compile(r"(process-model-routing|\banswer(?:s|ed|ing)?)\W+(?:[\w-]+\W+){0,3}?no\b"
                r"|\bno\W+(?:answer|to\W+process-model-routing)|^on\W+no\b", re.I)
def is_no(s):
    return bool(NO.search(s)) and re.search(r"\bno\b", s) is not None
DIRECT = re.compile(r"direct|uncut|uncompressed|not compressed|intact", re.I)
out = []
nos = [s for s in sentences if is_no(s)]
for s in nos:
    if DIRECT.search(s) and "SDG_MODEL_ROUTE=off" not in s:
        out.append("n1: a sentence about answering no says direct/uncut/intact: %s" % s)
if not any(re.search(r"wrapper", s, re.I) for s in nos):
    out.append("n2: no sentence about answering no says it switches the wrapper off")
if kind == "codex":
    if not any(re.search(r"\bcodex\b", s, re.I) and re.search(r"\bown\b", s, re.I)
               and re.search(r"config", s, re.I) and re.search(r"compress", s, re.I) for s in sentences):
        out.append("n3: no sentence says a Codex child that the user's own config routes still runs compressed")
print("\n".join(out))
PY
}

# rc_not_yes_ok <label> <file> <plain|codex>: the checker as an assertion.
rc_not_yes_ok() {
  local v
  v="$(rc_not_yes_violations "$2" "$3")"
  [ -z "$v" ] || fail "$1 — the not-yes wording checker reports:
$v"
}

RC_CODEX_HEADER_OVERRIDE='model_providers.caveman.http_headers={"x-cave-transforms"="caveman.pass-through.v1"}'
RC_CODEX_DIRECT_OVERRIDE='model_provider="openai"'

# rc_route_scan <root> [walk]: the S700 single-definition checker. Lists one
# "<path>: <pattern>" line per hit outside the allowed set and exits 1 when
# there is any. Default file list: `git -C <root> ls-files`; allowed set:
# route-child.sh, files under test/, and *.md outside templates/ and skills/.
# With `walk`, every file under <root> (directory symlinks not followed,
# .git skipped) is searched and nothing is allowed (an adopted project).
rc_route_scan() {
  python3 -I - "$1" "${2:-git}" <<'PY'
import os, re, subprocess, sys
root, mode = sys.argv[1], sys.argv[2]
PATTERNS = [
    ("proxy-address", re.compile(r"127\.0\.0\.1:8787")),
    ("base-url-assignment", re.compile(
        r"(?<![A-Za-z0-9_])ANTHROPIC_BASE_URL[ \t]*=(?!=)"
        r"|[\"\x27]ANTHROPIC_BASE_URL[\"\x27][ \t]*:"
        r"|[\"\x27]ANTHROPIC_BASE_URL[\"\x27][ \t]*\][ \t]*=(?!=)")),
    ("transform-header", re.compile(r"x-cave-transforms", re.I)),
    ("provider-override", re.compile(r"(?<![A-Za-z0-9_])model_providers?(\.[A-Za-z0-9_\"-]+)*[ \t]*=(?!=)")),
]
def allowed(rel):
    if rel == "route-child.sh" or rel.startswith("test/"):
        return True
    return rel.endswith(".md") and not rel.startswith(("templates/", "skills/"))
if mode == "git":
    out = subprocess.run(["git", "-C", root, "ls-files", "-z"], stdout=subprocess.PIPE, check=True).stdout
    files = [f.decode("utf-8", "surrogateescape") for f in out.split(b"\0") if f]
else:
    files = []
    for d, dirs, names in os.walk(root):
        dirs[:] = sorted(x for x in dirs if x != ".git")
        for n in sorted(names):
            files.append(os.path.relpath(os.path.join(d, n), root))
hits = []
for rel in files:
    if mode == "git" and allowed(rel):
        continue
    p = os.path.join(root, rel)
    try:
        text = open(p, "rb").read().decode("utf-8", "replace")
    except OSError as e:
        hits.append("%s: unreadable (%s)" % (rel, e.strerror))
        continue
    for name, rx in PATTERNS:
        if rx.search(text):
            hits.append("%s: %s" % (rel, name))
for h in hits:
    print(h)
sys.exit(1 if hits else 0)
PY
}

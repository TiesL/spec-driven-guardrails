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
  # Probe stub: argv to log/probe.log, exit status from probe.exit (default 0).
  cat >"$RC/probe/probe" <<'PROBE'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s\n' "$*" >>"$d/log/probe.log"
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

# rc_codex_config <variant>: writes $RC/codexhome/config.toml (S702 variants).
rc_codex_config() {
  local f="$RC/codexhome/config.toml"
  rm -f "$f"
  case "$1" in
    valid|header-other|profile)
      {
        echo '# fixture Codex config'
        echo 'model = "gpt-x"'
        echo 'model_provider = "caveman"'
        echo
        echo '[model_providers.caveman]'
        echo 'name = "Caveman"'
        echo 'base_url = "http://localhost:1/chatgpt"'
        echo 'wire_api = "responses"'
        echo 'requires_openai_auth = true'
        echo
        echo '[mcp_servers.x]'
        echo 'command = "x"'
        echo 'args = ['
        echo '  "--flag", # a comment inside an array'
        echo '  "value",'
        echo ']'
        if [ "$1" = header-other ]; then
          echo
          echo '[model_providers.other]'
          echo 'name = "Other"'
          echo 'http_headers = { "x-a" = "b" }'
        fi
        if [ "$1" = profile ]; then
          echo
          echo '[profiles.x]'
          echo 'model_provider = "openai"'
        fi
      } >"$f" ;;
    openai)
      printf 'model_provider = "openai"\n\n[model_providers.caveman]\nname = "Caveman"\n' >"$f" ;;
    nokey)
      printf 'model = "gpt-x"\n\n[model_providers.caveman]\nname = "Caveman"\n' >"$f" ;;
    comment)
      printf '# model_provider = "caveman"\nmodel_provider = "openai" # was caveman\n\n[model_providers.caveman]\nname = "Caveman"\n' >"$f" ;;
    header)
      printf 'model_provider = "caveman"\n\n[model_providers.caveman]\nname = "Caveman"\nhttp_headers = { "x-a" = "b" }\n' >"$f" ;;
    unparsable)
      printf 'model_provider = "caveman\nthis line is not toml\n[model_providers.caveman\n' >"$f" ;;
    missing) ;;
  esac
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

# rc_env_diff: the child's environment against the direct run's, one line
# per difference, sorted: "+NAME=value" (added or changed; a newline in the
# value is shown as \n) or "-NAME" (removed). Empty when identical.
rc_env_diff() {
  python3 -I - "$RC/direct.env" "$RC/child.env" <<'PY'
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

# rc_expected_claude_diff [<inherited NO_PROXY> <inherited headers>]: the
# four additions a routed Claude child must show, in rc_env_diff form.
rc_expected_claude_diff() {
  local np="127.0.0.1,localhost" hd="x-cave-transforms: caveman.pass-through.v1"
  [ -n "${1:-}" ] && np="$1,$np"
  [ -n "${2:-}" ] && hd="$2\\n$hd"
  printf '+ANTHROPIC_BASE_URL=http://127.0.0.1:8787/w/claude\n'
  printf '+ANTHROPIC_CUSTOM_HEADERS=%s\n' "$hd"
  printf '+NO_PROXY=%s\n' "$np"
  printf '+_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1\n'
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

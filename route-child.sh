#!/usr/bin/env bash
# route-child.sh — the one Module that routes a process-launched model child
# through the local Caveman proxy (#707, A61; docs/model-routing.md).
#
# Usage:
#   "$SPEC_DRIVEN_GUARDRAILS_DIR/route-child.sh" <claude|codex> -- <command> [args...]
#
# Runs <command> with routing applied to that child only, through `exec`, so
# the exit status is the child's own. The parent session, every settings file
# and ~/.codex/config.toml stay untouched: the four Claude variables exist only
# in the child's environment, the Codex header only in the child's arguments.
#
# Order: usage, opt-in, checks, probe, exec.
#   1. Usage, in every mode (exit 2): a known runtime, `--`, a command whose
#      first word is the runtime (`claude` or `codex`, by basename); for codex
#      the second word is exactly `exec`.
#   2. Opt-in: routing is on only when the git top level of the working
#      directory answers `process-model-routing` yes (answered_yes,
#      lib/changes.sh). Otherwise the command runs unchanged. With the answer
#      yes, SDG_MODEL_ROUTE=off (exact, lowercase) switches routing off for this
#      run: Claude runs unchanged, Codex gets `-c model_provider="openai"` after
#      `exec` and goes direct. Any other non-empty value is ignored with one
#      stderr line. Nothing else can switch routing on.
#   3. Checks (exit 4). Claude: the inherited ANTHROPIC_BASE_URL must be unset or
#      exactly the first-party URL; no checked settings file (SETTINGS_LOCATIONS)
#      may set env.ANTHROPIC_BASE_URL or be unreadable or not a JSON object.
#      Codex: ${CODEX_HOME:-$HOME/.codex}/config.toml must exist, parse, have the
#      top-level model_provider "caveman" and no http_headers in its caveman
#      provider table.
#   4. Probe (exit 3): curl, or the executable named by SDG_ROUTE_PROBE (a test
#      seam), with the arguments below. Only exit 0 (any HTTP answer) is up.
#   5. exec. Claude: ANTHROPIC_BASE_URL (the /w/claude route),
#      _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1, NO_PROXY with the loopback
#      appended, ANTHROPIC_CUSTOM_HEADERS with the pass-through header appended.
#      Codex: the pass-through header as a `-c` override directly after `exec`.
#
# Test seams (never switch routing on): SDG_ROUTE_PROBE replaces curl;
# SDG_ROUTE_MANAGED_SETTINGS, when non-empty, replaces the platform's
# managed-settings path and nothing else.
#
# Never adds --bare, --setting-sources or --settings, and never writes a file.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}. No timeout,
# gtimeout or nc. JSON and TOML are read with python3 -I.

set -uo pipefail

# --- the route: the only definition in the repository (S700) ----------------
PROXY_ORIGIN="http://127.0.0.1:8787"
CLAUDE_ROUTE_URL="$PROXY_ORIGIN/w/claude"
FIRST_PARTY_URL="https://api.anthropic.com"
LOOPBACK_NO_PROXY="127.0.0.1,localhost"
# Pass-through: the proxy meters the request but leaves its text intact.
# Allowing compression for children means removing this header, after a
# recorded maintainer decision (A61).
TRANSFORM_HEADER="x-cave-transforms: caveman.pass-through.v1"
CODEX_HEADER_OVERRIDE='model_providers.caveman.http_headers={"x-cave-transforms"="caveman.pass-through.v1"}'
CODEX_DIRECT_OVERRIDE='model_provider="openai"'
OPT_IN_ID="process-model-routing"

# The settings files a Claude child would load, kept once here and once in
# docs/model-routing.md (S709 compares them). "<base> <file>": user is
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}, cwd the child's working directory, top
# its git top level, managed the platform's managed-settings directory (or
# SDG_ROUTE_MANAGED_SETTINGS), args every --settings argument of the command.
SETTINGS_LOCATIONS='user settings.json
cwd .claude/settings.json
cwd .claude/settings.local.json
top .claude/settings.json
top .claude/settings.local.json
managed managed-settings.json
args --settings'
MANAGED_DIR_DARWIN="/Library/Application Support/ClaudeCode"
MANAGED_DIR_LINUX="/etc/claude-code"

usage() {
  echo "usage: route-child.sh <claude|codex> -- <command> [args...]  (codex: <command> is codex exec ...)" >&2
  exit 2
}

refuse() {
  echo "route-child: refused, child not started: $*" >&2
  exit 4
}

# --- 1. usage ------------------------------------------------------------------
[ "$#" -ge 3 ] || usage
runtime="$1"
case "$runtime" in claude|codex) ;; *) usage ;; esac
[ "$2" = "--" ] || usage
shift 2
[ -n "$1" ] || usage
[ "$(basename -- "$1")" = "$runtime" ] || usage
if [ "$runtime" = codex ]; then
  [ "${2:-}" = exec ] || usage
fi

# --- 2. opt-in ---------------------------------------------------------------------
# This script's own directory, through any chain of symlinks to the script.
self="${BASH_SOURCE[0]}"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in
    /*) self="$link" ;;
    *) self="$(dirname -- "$self")/$link" ;;
  esac
done
script_dir="$(cd "$(dirname -- "$self")" 2>/dev/null && pwd -P)" \
  || refuse "cannot find the directory of route-child.sh, so the opt-in cannot be read."
# shellcheck source=lib/changes.sh
. "$script_dir/lib/changes.sh" 2>/dev/null \
  || refuse "cannot read lib/changes.sh next to route-child.sh, so the opt-in cannot be read."

top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
if [ -z "$top" ] || ! answered_yes "$top" "$OPT_IN_ID"; then
  exec "$@"
fi

route_switch="${SDG_MODEL_ROUTE:-}"
if [ "$route_switch" = off ]; then
  if [ "$runtime" = codex ]; then
    cmd="$1"
    shift 2
    exec "$cmd" exec -c "$CODEX_DIRECT_OVERRIDE" "$@"
  fi
  exec "$@"
fi
if [ -n "$route_switch" ]; then
  echo "route-child: SDG_MODEL_ROUTE has a value other than off and is ignored; only the exact value off switches routing off for one run." >&2
fi

# --- 3. checks ----------------------------------------------------------------------

# check_claude_settings <command args...>: refuses (exit 4) when a checked
# settings file, or a --settings argument, sets env.ANTHROPIC_BASE_URL or
# cannot be read as a JSON object with an object env.
check_claude_settings() {
  local base file managed_path user_dir platform prev arg
  local specs=()
  managed_path="${SDG_ROUTE_MANAGED_SETTINGS:-}"
  if [ -z "$managed_path" ]; then
    platform="$(uname -s 2>/dev/null)"
    case "$platform" in
      Darwin) managed_path="$MANAGED_DIR_DARWIN/managed-settings.json" ;;
      Linux) managed_path="$MANAGED_DIR_LINUX/managed-settings.json" ;;
      *) refuse "the managed settings location is unknown on this platform (uname -s: ${platform:-unknown}); routing needs macOS or Linux." ;;
    esac
  fi
  user_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  while IFS=' ' read -r base file; do
    case "$base" in
      user) specs+=(optional "$user_dir/$file") ;;
      cwd) specs+=(optional "$PWD/$file") ;;
      top) specs+=(optional "$top/$file") ;;
      managed) specs+=(optional "$managed_path") ;;
      args)
        prev=""
        for arg in "$@"; do
          if [ "$prev" = "$file" ]; then
            specs+=(argument "$arg")
          fi
          case "$arg" in
            "$file="*) specs+=(argument "${arg#"$file="}") ;;
          esac
          prev="$arg"
        done
        [ "$prev" = "$file" ] && refuse "the command ends with $file and no value."
        ;;
    esac
  done <<<"$SETTINGS_LOCATIONS"

  local problem status
  problem="$(python3 -I - "${specs[@]}" <<'PY'
import json, os, sys

def verdict(text):
    if not text.strip():
        return "is empty"
    try:
        data = json.loads(text)
    except ValueError:
        return "is not valid JSON"
    if not isinstance(data, dict):
        return "is not a JSON object"
    if "env" in data:
        env = data["env"]
        if not isinstance(env, dict):
            return "has an env that is not an object"
        if "ANTHROPIC_BASE_URL" in env:
            return "sets env.ANTHROPIC_BASE_URL, which outranks the route on the child"
    return None

args = sys.argv[1:]
for kind, value in zip(args[0::2], args[1::2]):
    if kind == "argument" and value.lstrip().startswith("{"):
        name, text = "inline --settings", value
    else:
        name = value
        if kind == "optional" and not os.path.lexists(value):
            continue
        try:
            with open(value, "rb") as handle:
                text = handle.read().decode("utf-8")
        except (OSError, UnicodeDecodeError) as error:
            reason = getattr(error, "strerror", None) or "is not UTF-8 text"
            print("%s cannot be read (%s)" % (name, reason))
            sys.exit(1)
    problem = verdict(text)
    if problem:
        print("%s %s" % (name, problem))
        sys.exit(1)
sys.exit(0)
PY
)"
  status=$?
  case "$status" in
    0) ;;
    1) refuse "$problem. Remove the setting there, or run with SDG_MODEL_ROUTE=off." ;;
    *) refuse "the settings files could not be checked (checker exit status $status)." ;;
  esac
}

# check_codex_config: refuses (exit 4) unless the user's Codex config routes
# through the caveman provider and leaves its http_headers to this wrapper.
check_codex_config() {
  local config problem status
  config="${CODEX_HOME:-$HOME/.codex}/config.toml"
  [ -f "$config" ] || refuse "$config (config.toml) does not exist, so Codex is not routed through Caveman; SDG does not write it."
  problem="$(python3 -I - "$config" <<'PY'
import re, sys

# A small reader for the TOML this check needs: table headers, keys and the
# extent of values (strings, arrays, inline tables, multi-line strings).
def scan(text):
    table, entries = "", []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        i += 1
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            m = re.match(r"^\[\[?\s*([^\]]+?)\s*\]\]?\s*(#.*)?$", line)
            if not m:
                raise ValueError("bad table header")
            table = ".".join(p.strip().strip("\"\x27") for p in m.group(1).split("."))
            continue
        m = re.match(r"^([A-Za-z0-9_\-\.\"\x27 ]+?)\s*=\s*(.*)$", line)
        if not m:
            raise ValueError("not a key, a table header or a comment")
        key = ".".join(p.strip().strip("\"\x27") for p in m.group(1).split("."))
        value, rest = m.group(2), m.group(2)
        while True:
            state = balance(rest)
            if state == 0:
                break
            if i >= len(lines):
                raise ValueError("unterminated value")
            rest = lines[i]
            value += "\n" + rest
            i += 1
        entries.append((table, key, value))
    return entries

depth = 0
multi = None
def balance(segment):
    """Walks one line of a value; returns non-zero while the value continues."""
    global depth, multi
    j = 0
    while j < len(segment):
        if multi:
            k = segment.find(multi, j)
            if k < 0:
                return 1
            j, multi = k + 3, None
            continue
        c = segment[j]
        if segment.startswith(("\"\"\"", "\x27\x27\x27"), j):
            multi = segment[j:j + 3]
            j += 3
            continue
        if c in "\"\x27":
            k = j + 1
            while k < len(segment) and segment[k] != c:
                k += 2 if (c == "\"" and segment[k] == "\\") else 1
            if k >= len(segment):
                raise ValueError("unterminated string")
            j = k + 1
            continue
        if c == "#":
            break
        if c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
            if depth < 0:
                raise ValueError("unbalanced brackets")
        j += 1
    if not segment.strip() and depth == 0 and not multi:
        raise ValueError("missing value")
    return 1 if (depth or multi) else 0

try:
    entries = scan(open(sys.argv[1], encoding="utf-8").read())
except (OSError, UnicodeDecodeError) as error:
    print("cannot be read (%s)" % (getattr(error, "strerror", None) or "not UTF-8 text"))
    sys.exit(1)
except ValueError as error:
    print("cannot be parsed (%s)" % error)
    sys.exit(1)
provider = None
for table, key, value in entries:
    full = (table + "." + key) if table else key
    if full == "model_provider":
        m = re.match(r"^\s*(\"([^\"]*)\"|\x27([^\x27]*)\x27)\s*(#.*)?$", value)
        provider = (m.group(2) if m.group(2) is not None else m.group(3)) if m else value.strip()
    if full.startswith("model_providers.caveman.http_headers") or (
            full == "model_providers.caveman" and "http_headers" in value):
        print("[model_providers.caveman] already has http_headers; SDG does not overwrite them")
        sys.exit(1)
if provider != "caveman":
    print("model_provider is not caveman, so Codex is not routed through Caveman")
    sys.exit(1)
sys.exit(0)
PY
)"
  status=$?
  case "$status" in
    0) ;;
    1) refuse "$config (config.toml): $problem. SDG does not write it." ;;
    *) refuse "$config (config.toml) could not be checked (checker exit status $status)." ;;
  esac
}

if [ "$runtime" = claude ]; then
  if [ "${ANTHROPIC_BASE_URL+set}" = set ] && [ "$ANTHROPIC_BASE_URL" != "$FIRST_PARTY_URL" ]; then
    refuse "the parent is already routed: ANTHROPIC_BASE_URL is set and is not exactly $FIRST_PARTY_URL. It comes from a settings file env or the shell that started this session; unset it there (the session itself must stay direct)."
  fi
  check_claude_settings "$@"
else
  check_codex_config
fi

# --- 4. probe ------------------------------------------------------------------------
probe="${SDG_ROUTE_PROBE:-curl}"
"$probe" -s -o /dev/null --connect-timeout 2 --max-time 3 "$PROXY_ORIGIN/" >/dev/null 2>&1
probe_status=$?
if [ "$probe_status" -ne 0 ]; then
  message="route-child: model routing is on (WORKFLOW-ADOPTION.md: $OPT_IN_ID yes) but no HTTP answer came from $PROXY_ORIGIN (probe exit status $probe_status). Start the Caveman proxy, rerun with SDG_MODEL_ROUTE=off for this run, or answer $OPT_IN_ID no to opt out."
  if [ "$runtime" = codex ]; then
    message="$message Codex itself is routed by your own Codex config, which SDG does not change."
  fi
  echo "$message" >&2
  exit 3
fi

# --- 5. exec -----------------------------------------------------------------------
if [ "$runtime" = codex ]; then
  cmd="$1"
  shift 2
  exec "$cmd" exec -c "$CODEX_HEADER_OVERRIDE" "$@"
fi
if [ -n "${NO_PROXY:-}" ]; then
  NO_PROXY="$NO_PROXY,$LOOPBACK_NO_PROXY"
else
  NO_PROXY="$LOOPBACK_NO_PROXY"
fi
if [ -n "${ANTHROPIC_CUSTOM_HEADERS:-}" ]; then
  ANTHROPIC_CUSTOM_HEADERS="$ANTHROPIC_CUSTOM_HEADERS"$'\n'"$TRANSFORM_HEADER"
else
  ANTHROPIC_CUSTOM_HEADERS="$TRANSFORM_HEADER"
fi
export ANTHROPIC_BASE_URL="$CLAUDE_ROUTE_URL" _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1 \
  NO_PROXY ANTHROPIC_CUSTOM_HEADERS
exec "$@"

#!/usr/bin/env bash
# route-child.sh — the one Module that routes a process-launched model child
# through the local Caveman proxy (#707, A61; docs/model-routing.md).
#
# Usage:
#   "$SPEC_DRIVEN_GUARDRAILS_DIR/route-child.sh" <claude|codex> -- <command> [args...]
#
# Runs <command> with routing applied to that child only, through `exec`, so
# the exit status is the child's own. The parent session, every settings file
# and ~/.codex/config.toml stay untouched: the five Claude variables exist only
# in the child's environment, the Codex header only in the child's arguments.
#
# Order: usage, opt-in, checks, probe, exec.
#   1. Usage, in every mode (exit 2): a known runtime, `--`, a command whose
#      first word is the runtime (`claude` or `codex`, by basename); for codex
#      the second word is exactly `exec`.
#   2. Opt-in: routing is on only when the git top level of the working
#      directory answers `process-model-routing` yes (answered_yes,
#      lib/changes.sh). Otherwise the command runs unchanged: the wrapper does
#      nothing, so a Codex child that the user's own config routes through the
#      proxy still runs there compressed. With the answer yes,
#      SDG_MODEL_ROUTE=off (exact, lowercase) switches routing off for this
#      run: Claude runs unchanged; Codex gets `-c model_provider="openai"`
#      after `exec` and goes direct, after a check (exit 4) that no command
#      argument or selected profile would route it anyway. Any other non-empty
#      value is ignored with one stderr line. Nothing else switches routing on.
#   3. Checks (exit 4). Claude: the inherited ANTHROPIC_BASE_URL must be unset
#      or exactly the first-party URL; the inherited ANTHROPIC_CUSTOM_HEADERS
#      must not already carry an x-cave-transforms header; no checked settings
#      file (SETTINGS_LOCATIONS) may set under env any variable of
#      CLAUDE_CHILD_VARS or be unreadable or not a JSON object. Codex: no
#      command argument of CODEX_SELECTION; ${CODEX_HOME:-$HOME/.codex}/config.toml
#      must exist and parse, its effective provider must be "caveman", and that
#      provider must not have http_headers or env_http_headers.
#   4. Probe (exit 3): curl, or the executable named by SDG_ROUTE_PROBE (a test
#      seam), with the arguments below. Only exit 0 (any HTTP answer) is up.
#   5. exec. Claude: every variable of CLAUDE_CHILD_VARS, set and exported.
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
TRANSFORM_NAME="x-cave-transforms"
TRANSFORM_HEADER="$TRANSFORM_NAME: caveman.pass-through.v1"
CODEX_HEADER_OVERRIDE='model_providers.caveman.http_headers={"x-cave-transforms"="caveman.pass-through.v1"}'
CODEX_DIRECT_OVERRIDE='model_provider="openai"'
OPT_IN_ID="process-model-routing"

# The variables a routed Claude child gets, kept once: step 5 sets exactly
# these, and the settings check refuses a settings env that sets any of them
# (settings env outranks the child's own environment).
CLAUDE_CHILD_VARS='ANTHROPIC_BASE_URL _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL NO_PROXY no_proxy ANTHROPIC_CUSTOM_HEADERS'

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

# The Codex command arguments (after `exec`, up to a lone `--`) that select a
# provider or profile or change a provider table, kept once here and once in
# docs/model-routing.md (S709 compares them). "<options> [<key>]": options
# separated by `|`, each also in its `=` form; without a key the option itself
# refuses; with a key, a -c/--config value whose key (before its first `=`,
# whitespace and quotes trimmed) equals it, or starts with it before a
# trailing `*`, refuses.
CODEX_SELECTION='--profile
-p
--oss
-c|--config model_provider
-c|--config profile
-c|--config profiles.*
-c|--config model_providers*'

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

# check_codex <routed|off> <codex command...>: refuses (exit 4) when the Codex
# command's own arguments (CODEX_SELECTION) or the user's config.toml would
# decide the route instead of the wrapper. routed: the effective provider must
# be caveman and leave its headers to the wrapper; a missing or unparsable
# file refuses. off: a missing file passes; an unparsable file, or a selected
# profile that is missing or sets a provider other than openai, refuses.
check_codex() {
  local mode="$1" config problem status
  shift 3
  config="${CODEX_HOME:-$HOME/.codex}/config.toml"
  problem="$(python3 -I - "$mode" "$config" "$CODEX_SELECTION" "$@" <<'PY'
import os, re, sys

mode, config, selection = sys.argv[1], sys.argv[2], sys.argv[3]
args = sys.argv[4:]
named = "%s (config.toml)" % config

def stop(message):
    print(message)
    sys.exit(1)

# --- the arguments of the command ------------------------------------------
items = []
for line in selection.split("\n"):
    fields = line.split()
    if fields:
        items.append((fields[0].split("|"), fields[1] if len(fields) > 1 else None))

def trimmed_key(text):
    key = text.split("=", 1)[0]
    return ".".join(part.strip().strip("\"\x27").strip() for part in key.split("."))

def key_matches(key, pattern):
    if pattern.endswith("*"):
        return key.startswith(pattern[:-1])
    return key == pattern

i = 0
while i < len(args):
    arg = args[i]
    if arg == "--":
        break
    name, eq, inline = arg.partition("=") if arg.startswith("-") else (arg, "", "")
    takes_value = False
    for options, pattern in items:
        if name not in options:
            continue
        if pattern is None:
            stop("the argument %s of the command selects a Codex profile or provider, which would decide the route instead of the wrapper; remove it" % name)
        takes_value = True
        value = inline if eq else (args[i + 1] if i + 1 < len(args) else "")
        key = trimmed_key(value)
        if key_matches(key, pattern):
            stop("the argument %s of the command with the key %s selects a Codex profile or provider or changes a provider table, which would decide the route instead of the wrapper; remove it" % (name, key))
    i += 2 if (takes_value and not eq) else 1

# --- config.toml --------------------------------------------------------------
if not os.path.lexists(config):
    if mode == "off":
        sys.exit(0)
    stop("%s does not exist, so Codex is not routed through Caveman (SDG does not write it)" % named)

class TomlError(ValueError):
    pass

class Inline(dict):
    """A table written as an inline table: closed to later keys and headers."""

BARE = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
SCALAR = re.compile(r"^(true|false|[+-]?(inf|nan)|[+-]?[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?"
                    r"|0x[0-9A-Fa-f_]+|0o[0-7_]+|0b[01_]+|[0-9]{4}-[0-9]{2}-[0-9]{2}([Tt ][0-9:.]+)?([Zz]|[+-][0-9:]+)?"
                    r"|[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?)$")

# A small TOML reader (Python 3.9 has no tomllib): table headers, arrays of
# tables, dotted and quoted keys, strings of all four kinds, arrays and inline
# tables at any depth. Key paths are resolved into nested dicts, so a key
# means the same whichever form wrote it.
class Reader:
    def __init__(self, text):
        self.s, self.i = text.replace("\r\n", "\n"), 0

    def peek(self, offset=0):
        j = self.i + offset
        return self.s[j] if j < len(self.s) else ""

    def expect(self, text):
        if not self.s.startswith(text, self.i):
            raise TomlError("expected %r" % text)
        self.i += len(text)

    def blanks(self):
        while self.peek() in (" ", "\t") and self.peek():
            self.i += 1

    def comment(self):
        if self.peek() == "#":
            while self.peek() not in ("\n", ""):
                self.i += 1

    def blank_lines(self):
        while True:
            self.blanks()
            self.comment()
            if self.peek() != "\n":
                return
            self.i += 1

    def line_end(self):
        self.blanks()
        self.comment()
        if self.peek() == "\n":
            self.i += 1
        elif self.peek():
            raise TomlError("unexpected text after a value")

    def string(self):
        quote = self.peek()
        if self.s.startswith(quote * 3, self.i):
            self.i += 3
            start = self.i
            while not self.s.startswith(quote * 3, self.i):
                if not self.peek():
                    raise TomlError("unterminated string")
                self.i += 2 if (quote == "\"" and self.peek() == "\\") else 1
            while self.peek(3) == quote:  # up to two quotes may end the content
                self.i += 1
            text = self.s[start:self.i]
            self.i += 3
            return text
        self.i += 1
        start = self.i
        while self.peek() != quote:
            if self.peek() in ("\n", ""):
                raise TomlError("unterminated string")
            self.i += 2 if (quote == "\"" and self.peek() == "\\") else 1
        text = self.s[start:self.i]
        self.i += 1
        return text.replace("\\\"", "\"").replace("\\\\", "\\") if quote == "\"" else text

    def key(self):
        parts = []
        while True:
            self.blanks()
            if self.peek() in ("\"", "\x27"):
                parts.append(self.string())
            else:
                start = self.i
                while self.peek() and self.peek() in BARE:
                    self.i += 1
                if start == self.i:
                    raise TomlError("a key is missing")
                parts.append(self.s[start:self.i])
            self.blanks()
            if self.peek() != ".":
                return parts
            self.i += 1

    def value(self):
        c = self.peek()
        if c in ("\"", "\x27"):
            return self.string()
        if c == "[":
            self.i += 1
            items = []
            while True:
                self.blank_lines()
                if self.peek() == "]":
                    self.i += 1
                    return items
                items.append(self.value())
                self.blank_lines()
                if self.peek() == ",":
                    self.i += 1
                elif self.peek() != "]":
                    raise TomlError("an array is not closed")
        if c == "{":
            self.i += 1
            table = Inline()
            self.blank_lines()
            if self.peek() == "}":
                self.i += 1
                return table
            while True:
                parts = self.key()
                self.expect("=")
                self.blanks()
                assign(table, parts, self.value())
                self.blank_lines()
                if self.peek() == ",":
                    self.i += 1
                    self.blank_lines()
                elif self.peek() == "}":
                    self.i += 1
                    return table
                else:
                    raise TomlError("an inline table is not closed")
        start = self.i
        while self.peek() and self.peek() not in " \t\n#,]}":
            self.i += 1
        token = self.s[start:self.i]
        if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", token) and self.peek() == " " and re.match(r"[0-9]{2}:", self.s[self.i + 1:self.i + 4]):
            self.i += 1
            while self.peek() and self.peek() not in " \t\n#,]}":
                self.i += 1
            token = self.s[start:self.i]
        if not SCALAR.match(token):
            raise TomlError("a value is missing or not TOML")
        return token

def descend(table, part):
    if part not in table:
        table[part] = {}
    node = table[part]
    if isinstance(node, list) and node and isinstance(node[-1], dict):
        node = node[-1]
    if not isinstance(node, dict) or isinstance(node, Inline):
        raise TomlError("the key %s is defined twice" % part)
    return node

def assign(table, parts, value):
    for part in parts[:-1]:
        table = descend(table, part)
    if parts[-1] in table:
        raise TomlError("the key %s is defined twice" % parts[-1])
    table[parts[-1]] = value

def parse(text):
    reader, root, headed = Reader(text), {}, set()
    current = root
    while True:
        reader.blank_lines()
        if not reader.peek():
            return root
        if reader.peek() == "[":
            many = reader.s.startswith("[[", reader.i)
            reader.i += 2 if many else 1
            parts = reader.key()
            reader.expect("]]" if many else "]")
            reader.line_end()
            table = root
            for part in parts[:-1]:
                table = descend(table, part)
            if many:
                rows = table.setdefault(parts[-1], [])
                if not isinstance(rows, list):
                    raise TomlError("the key %s is defined twice" % parts[-1])
                rows.append({})
                current = rows[-1]
            else:
                current = descend(table, parts[-1])
                if id(current) in headed:
                    raise TomlError("the table %s is defined twice" % ".".join(parts))
                headed.add(id(current))
            continue
        parts = reader.key()
        reader.expect("=")
        reader.blanks()
        assign(current, parts, reader.value())
        reader.line_end()

def get(node, *path):
    for part in path:
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node

try:
    with open(config, encoding="utf-8") as handle:
        data = parse(handle.read())
except (OSError, UnicodeDecodeError) as error:
    stop("%s cannot be read (%s)" % (named, getattr(error, "strerror", None) or "not UTF-8 text"))
except TomlError as error:
    stop("%s cannot be parsed (%s)" % (named, error))

profile = data.get("profile")
selected = None
if profile is not None:
    selected = get(data, "profiles", profile) if isinstance(profile, str) else None
    if not isinstance(selected, dict):
        stop("%s selects the profile %s, which has no profile table" % (named, profile))

if mode == "off":
    if selected is not None and "model_provider" in selected and selected["model_provider"] != "openai":
        stop("%s selects the profile %s with model_provider %s, which would route this child while SDG_MODEL_ROUTE=off promises it goes direct"
             % (named, profile, selected["model_provider"]))
    sys.exit(0)

if selected is not None and "model_provider" in selected:
    provider, source = selected["model_provider"], "the model_provider of the selected profile %s" % profile
else:
    provider, source = data.get("model_provider"), "the top-level model_provider"
if provider != "caveman":
    stop("%s: %s is not caveman, so Codex is not routed through Caveman" % (named, source))
provider_table = get(data, "model_providers", "caveman")
for key in ("http_headers", "env_http_headers"):
    if isinstance(provider_table, dict) and key in provider_table:
        stop("%s: the caveman provider already has %s, which SDG does not overwrite" % (named, key))
sys.exit(0)
PY
)"
  status=$?
  case "$status" in
    0) ;;
    1) refuse "$problem." ;;
    *) refuse "$config (config.toml) could not be checked (checker exit status $status)." ;;
  esac
}

route_switch="${SDG_MODEL_ROUTE:-}"
if [ "$route_switch" = off ]; then
  if [ "$runtime" = codex ]; then
    check_codex off "$@"
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

# inherited_transform_header: 0 when the inherited ANTHROPIC_CUSTOM_HEADERS has
# a line whose header name (before the first `:`, trimmed, any case) is the
# transform header's.
inherited_transform_header() {
  local line name
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *:*) ;; *) continue ;; esac
    name="$(printf '%s' "${line%%:*}" | tr -d ' \t\r' | tr '[:upper:]' '[:lower:]')"
    [ "$name" = "$TRANSFORM_NAME" ] && return 0
  done <<<"${ANTHROPIC_CUSTOM_HEADERS:-}"
  return 1
}

# check_claude_settings <command args...>: refuses (exit 4) when a checked
# settings file, or a --settings argument, sets under env a variable of
# CLAUDE_CHILD_VARS or cannot be read as a JSON object with an object env.
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
  problem="$(python3 -I - "$CLAUDE_CHILD_VARS" "${specs[@]}" <<'PY'
import json, os, sys

KEYS = sys.argv[1].split()

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
        for key in KEYS:
            if key in env:
                return "sets env.%s, which outranks the value the wrapper gives the child" % key
    return None

args = sys.argv[2:]
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

if [ "$runtime" = claude ]; then
  if [ "${ANTHROPIC_BASE_URL+set}" = set ] && [ "$ANTHROPIC_BASE_URL" != "$FIRST_PARTY_URL" ]; then
    refuse "the parent is already routed: ANTHROPIC_BASE_URL is set and is not exactly $FIRST_PARTY_URL. It comes from a settings file env or the shell that started this session; unset it there (the session itself must stay direct)."
  fi
  if inherited_transform_header; then
    refuse "the inherited ANTHROPIC_CUSTOM_HEADERS already has an $TRANSFORM_NAME header, and the wrapper never replaces a header you set; remove it there, or run with SDG_MODEL_ROUTE=off."
  fi
  check_claude_settings "$@"
else
  check_codex routed "$@"
fi

# --- 4. probe ------------------------------------------------------------------------
probe="${SDG_ROUTE_PROBE:-curl}"
"$probe" -s -o /dev/null --connect-timeout 2 --max-time 3 "$PROXY_ORIGIN/" >/dev/null 2>&1
probe_status=$?
if [ "$probe_status" -ne 0 ]; then
  message="route-child: model routing is on (WORKFLOW-ADOPTION.md: $OPT_IN_ID yes) but no HTTP answer came from $PROXY_ORIGIN (probe exit status $probe_status). Start the Caveman proxy, or rerun with SDG_MODEL_ROUTE=off to run this one child without the route. Answering $OPT_IN_ID no only switches this wrapper off for the project; it does not decide where a child's traffic goes."
  if [ "$runtime" = codex ]; then
    message="$message Under a no answer a Codex child that your own Codex config routes through the proxy still runs there compressed; only SDG_MODEL_ROUTE=off sends it direct."
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

# The five variables of CLAUDE_CHILD_VARS, on this process only, which `exec`
# hands to the child. NO_PROXY, no_proxy and ANTHROPIC_CUSTOM_HEADERS keep
# their own inherited value and get theirs appended.
ANTHROPIC_BASE_URL="$CLAUDE_ROUTE_URL"
_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1
NO_PROXY="${NO_PROXY:+$NO_PROXY,}$LOOPBACK_NO_PROXY"
no_proxy="${no_proxy:+$no_proxy,}$LOOPBACK_NO_PROXY"
ANTHROPIC_CUSTOM_HEADERS="${ANTHROPIC_CUSTOM_HEADERS:+$ANTHROPIC_CUSTOM_HEADERS$'\n'}$TRANSFORM_HEADER"
# shellcheck disable=SC2086,SC2163 # the list is split into names on purpose
export $CLAUDE_CHILD_VARS
exec "$@"

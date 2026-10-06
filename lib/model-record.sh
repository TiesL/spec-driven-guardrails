#!/usr/bin/env bash
# lib/model-record.sh — Shared reading of `model-record` markers (A25, #392).
#
# Source, don't execute. Three callers read the same marker fields and must
# agree on how: skills/pre-merge-review/model-record-gate.sh,
# compliance-evidence.sh and role-label-staleness.sh. One copy of:
#
#   normalize_model <label>      model label -> comparable form (moved
#                                unchanged from both scripts, #268)
#   marker_find <Stage> <text>   every well-formed `model-record` marker of
#                                that stage, one per line
#   marker_scan <text>           every `model-record` marker, well-formed or
#                                malformed, with its stage token
#   marker_attr <marker> <name>  the quoted value of one attribute
#   marker_emit <Stage> <model> [<floor-basis>]
#                                THE way to produce a marker line (#402,
#                                A26; wrapper: skills/pre-merge-review/
#                                model-record-emit.sh): the one valid line,
#                                checked by parsing it back, or nothing
#
# The grammar and what happens to a malformed marker are documented once,
# above _MARKER_SCAN_AWK below. The three parser functions run awk under
# LC_ALL=C and return non-zero (with a stderr line, nothing on stdout) when
# awk fails: a caller must treat that as "markers not read", never as "no
# marker".
#
# Comment boundaries: the <text> given to marker_find and marker_scan has
# every comment, review or description followed by MARKER_SEP (U+001E),
# with that byte removed from the body first; a marker never crosses it.
# See "Comment boundaries" above _MARKER_SCAN_AWK.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# live_text and md_strip_fences (one definition, #423) come from the sibling
# lib/markdown.sh, so every script that sources this file reads quoted text
# the same way.
# shellcheck source=lib/markdown.sh
. "$(dirname "${BASH_SOURCE[0]}")/markdown.sh"

# Structural, not a per-model alias table (#268): strips the vendor-prefix
# word and a trailing 8-digit snapshot-date suffix, then folds every
# remaining separator and case difference away. Exact-modulo-format, not
# exact-modulo-spelling: a short alias ("opus") stays different from its
# full id ("claude-opus-5"), recorded as debt (PRD.md).
normalize_model() {
  printf '%s' "$1" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -E 's/^[[:space:]]*claude[- ]*//' \
    | LC_ALL=C sed -E 's/-[0-9]{8}$//' \
    | LC_ALL=C sed -E 's/[^a-z0-9]+/ /g' \
    | LC_ALL=C sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}


# --- The marker parser ------------------------------------------------------
#
# Every awk program below runs under LC_ALL=C (#392, round 3 of the PR #397
# review). All the grammar's delimiters are ASCII, so bytes are all the
# parser needs; under a UTF-8 locale macOS awk (BWK) splits a multibyte
# character with substr and aborts on the fragment ("towc: multibyte
# conversion failure"), which used to drop every marker after a `stage=…`.
# And a failure is never silent: when awk exits non-zero the function prints
# nothing on stdout, says so on stderr and returns that exit status, so a
# caller can tell "no marker" from "markers not read" (the gate prints a
# `model-record:` finding, the collector's gates go indeterminate,
# role-label-staleness.sh goes indeterminate).

# The comment-boundary byte. A caller frames one body as
#   "${body//$MARKER_SEP/}$MARKER_SEP"
# (model-record-gate.sh does the same inside its `--jq`).
MARKER_SEP=$'\036'

_marker_fail() { # <function> <awk exit status>
  echo "lib/model-record.sh: $1: the marker parser (awk) failed with exit $2; markers were NOT read" >&2
}

# One program, two modes (mode=find: the well-formed markers of stage
# `want`, one per line; mode=scan: every marker, `ok|malformed<TAB>stage<TAB>
# marker-or-reason`). walk() is the grammar after `model-record:` and the
# optional `stage=<token>`:
#   - whitespace (a newline counts) separates tokens;
#   - name="value": the value runs to the next quote and may hold anything
#     else (`>`, `<`, `--`, `-->`, `<!--`, a newline); after the closing
#     quote comes whitespace or `-->`;
#   - name=bare: an unquoted value runs to whitespace or `-->`;
#   - any other word or character is tolerated and skipped;
#   - the marker ends at the first `-->` outside a quoted value;
#   - a marker never crosses a comment boundary (below).
# MALFORMED, and never read: a quote anywhere but right after `name=`, text
# glued to a closing quote, a quoted value not closed in its own comment, a
# `<!--` outside a quoted value, or no closing `-->` in its own comment.
# Scanning then resumes right after the malformed marker's own `<!--`, so it
# can never swallow a later marker: there is no fallback to "the first
# `-->`" (that fallback let a malformed marker's attributes count).
#
# Comment boundaries (round 4 of the PR #397 review): every caller passes
# its comments, reviews and descriptions each followed by the byte U+001E
# (record separator), after removing that byte from the body itself (so a
# body can neither forge nor hide a boundary). The byte is not whitespace,
# not a name character and not allowed in a value: reaching it before the
# closing `-->` makes the marker malformed. So an unclosed quote or a
# missing `-->` in one comment stays in that comment, however the next one
# starts. Text without the byte is read as one comment.
_MARKER_SCAN_AWK='
function ws(c) { return c == " " || c == "\t" || c == "\n" || c == "\r" }
function namec(c) { return c ~ /[A-Za-z0-9_-]/ }
function stagec(c) { return c ~ /[A-Za-z0-9_]/ }
function flat(t) { gsub(/[\t\n\r]/, " ", t); gsub(SEP, " ", t); return t }
function walk(k,   c, j, q) {
  while (1) {
    if (k > n) { BAD_AT = n + 1; WHY = "no closing -->"; return 0 }
    c = substr(s, k, 1)
    if (c == SEP) { BAD_AT = k; WHY = "no closing --> in its own comment"; return 0 }
    if (ws(c)) { k++; continue }
    if (substr(s, k, 3) == "-->") { END_AT = k + 3; return 1 }
    if (substr(s, k, 4) == "<!--") { BAD_AT = k; WHY = "a <!-- inside it"; return 0 }
    if (c == "\"") { BAD_AT = k; WHY = "a quote outside a value"; return 0 }
    if (!namec(c)) { k++; continue }
    j = k
    while (j <= n && namec(substr(s, j, 1)) && substr(s, j, 3) != "-->") j++
    k = j
    if (substr(s, k, 1) != "=") continue
    k++
    if (substr(s, k, 1) == "\"") {
      q = index(substr(s, k + 1), "\"")
      if (q == 0 || index(substr(s, k + 1, q - 1), SEP) > 0) { BAD_AT = k; WHY = "a quoted value not closed in its own comment"; return 0 }
      k = k + q + 1
      if (k <= n && !ws(substr(s, k, 1)) && substr(s, k, 3) != "-->") { BAD_AT = k; WHY = (substr(s, k, 1) == SEP) ? "no closing --> in its own comment" : "text glued to a closing quote"; return 0 }
      continue
    }
    while (k <= n) {
      c = substr(s, k, 1)
      if (ws(c) || substr(s, k, 3) == "-->") break
      if (c == "\"") { BAD_AT = k; WHY = "a quote inside an unquoted value"; return 0 }
      if (c == SEP) { BAD_AT = k; WHY = "no closing --> in its own comment"; return 0 }
      if (substr(s, k, 4) == "<!--") { BAD_AT = k; WHY = "a <!-- inside it"; return 0 }
      k++
    }
  }
}
BEGIN { SEP = sprintf("%c", 30) }
{ all = all $0 "\n" }
END {
  s = all; n = length(s); pos = 1
  while (1) {
    p = index(substr(s, pos), "<!--")
    if (p == 0) break
    start = pos + p - 1
    i = start + 4
    while (i <= n && ws(substr(s, i, 1))) i++
    if (substr(s, i, 13) != "model-record:") { pos = start + 4; continue }
    i += 13
    while (i <= n && ws(substr(s, i, 1))) i++
    stage = ""
    if (substr(s, i, 6) == "stage=") {
      j = i + 6
      while (j <= n && stagec(substr(s, j, 1))) j++
      stage = substr(s, i + 6, j - i - 6)
      i = j
    }
    if (walk(i)) {
      m = flat(substr(s, start, END_AT - start))
      if (mode == "scan") print "ok\t" stage "\t" m
      else if (stage == want) print m
      pos = END_AT
    } else {
      if (mode == "scan") {
        e = flat(substr(s, start, BAD_AT - start))
        if (length(e) > 200) e = substr(e, 1, 200) "..."
        print "malformed\t" stage "\t" WHY ": " e
      }
      pos = start + 4
    }
  }
}
'

# marker_attr <marker> <name>: the quoted value of one attribute (first
# occurrence), or nothing when it is absent or unquoted. The same tokens as
# walk() above: a value runs to the next quote, so `model=` inside a value
# is never an attribute, and `model` never matches inside `floor-basis` or
# `reviewer-model`. Meant for a line marker_find printed (already
# well-formed). Returns awk's status on failure (see _marker_fail).
marker_attr() {
  local out rc
  out="$(LC_ALL=C awk -v want="$2" '
    function ws(c) { return c == " " || c == "\t" }
    function namec(c) { return c ~ /[A-Za-z0-9_-]/ }
    { s = (NR == 1) ? $0 : s " " $0 }
    END {
      n = length(s); i = 1; out = ""; found = 0
      while (i <= n && ws(substr(s, i, 1))) i++
      if (substr(s, i, 4) == "<!--") i += 4
      while (i <= n && ws(substr(s, i, 1))) i++
      if (substr(s, i, 13) == "model-record:") i += 13
      while (i <= n) {
        while (i <= n && ws(substr(s, i, 1))) i++
        if (substr(s, i, 3) == "-->") break
        j = i
        while (j <= n && namec(substr(s, j, 1)) && substr(s, j, 3) != "-->") j++
        if (j == i) { i++; continue }
        name = substr(s, i, j - i); i = j
        if (substr(s, i, 1) != "=") continue
        i++
        quoted = 0; val = ""
        if (substr(s, i, 1) == "\"") {
          k = index(substr(s, i + 1), "\"")
          if (k > 0) { quoted = 1; val = substr(s, i + 1, k - 1); i = i + k + 1 }
          else { i = n + 1 }
        } else {
          j = i
          while (j <= n && !ws(substr(s, j, 1)) && substr(s, j, 3) != "-->") j++
          i = j
        }
        if (name == want && quoted && !found) { found = 1; out = val }
      }
      printf "%s", out
    }
  ' <<<"$1")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _marker_fail marker_attr "$rc"
    return "$rc"
  fi
  printf '%s' "$out"
  return 0
}

# marker_find <Stage> <text>: every well-formed `model-record` marker of that
# stage in <text>, in order, one per line (newlines inside a marker become
# spaces). THE marker grammar: `<!--`, `model-record:`, `stage=<Stage>`,
# attributes (walk() above) and the closing `-->`. A malformed marker is
# skipped, never read; marker_scan reports it.
marker_find() {
  local out rc
  out="$(LC_ALL=C awk -v want="$1" -v mode=find "$_MARKER_SCAN_AWK" <<<"$2")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _marker_fail marker_find "$rc"
    return "$rc"
  fi
  [ -z "$out" ] || printf '%s\n' "$out"
  return 0
}

# marker_scan <text>: every `<!-- model-record:` marker of any (or no)
# stage, in order, one per line: `ok<TAB><stage><TAB><marker>` or
# `malformed<TAB><stage><TAB><reason>: <the text up to the fault>`. <stage>
# is the [A-Za-z0-9_] run after `stage=` (empty when there is none).
marker_scan() {
  local out rc
  out="$(LC_ALL=C awk -v want= -v mode=scan "$_MARKER_SCAN_AWK" <<<"$1")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _marker_fail marker_scan "$rc"
    return "$rc"
  fi
  [ -z "$out" ] || printf '%s\n' "$out"
  return 0
}

# marker_emit <Stage> <model> [<floor-basis>] (#402, A26): THE way
# to produce a marker line; nobody types one. Prints exactly one line,
#   <!-- model-record: stage=<Stage> model="<model>"[ floor-basis="<sentence>"] -->
# or prints nothing, gives a one-line reason on stderr and returns 2.
# Refused: a stage other than the five names (it is emitted bare); a model
# that is empty, over 200 characters or not one token of [A-Za-z0-9._:@/+-]
# (a model id; no space, quote, `=` or control byte); a floor-basis missing or blank on Review or given
# on any other stage (A24); a floor-basis with a double quote (it would end
# the value) or a control byte (newline, tab, U+001E, ...), or over 500
# bytes. Nothing else: `>`, `<`, `--`, `-->`, `<!--`, `=` and non-ASCII text
# are allowed in a floor-basis, because the grammar reads them as text (the
# maintainer's #392 decision; GitHub may show what follows a `-->` as text,
# but the marker still reads back). Safety net: before printing, the line is
# parsed back with marker_find, marker_scan and marker_attr; a line that
# does not read back exactly is refused, never printed.
marker_emit() {
  local LC_ALL=C
  local stage="${1-}" model="${2-}" fb="${3-}" have_fb=0 line got tab=$'\t'
  [ "$#" -ge 3 ] && have_fb=1
  if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "marker_emit: usage: marker_emit <Stage> <model> [<floor-basis>]" >&2
    return 2
  fi
  case "$stage" in
    Discovery | Planning | Test | Implementation | Review) : ;;
    *)
      echo "marker_emit: stage must be one of Discovery Planning Test Implementation Review (got '$stage')" >&2
      return 2
      ;;
  esac
  if [ -z "$model" ] || [ "${#model}" -gt 200 ]; then
    echo "marker_emit: model must be 1-200 characters (your exact model id)" >&2
    return 2
  fi
  case "$model" in
    *[!A-Za-z0-9._:@/+-]*)
      echo "marker_emit: model must be one token of letters, digits and . _ : @ / + - (your exact model id), got '$model'" >&2
      return 2
      ;;
  esac
  if [ "$stage" = Review ]; then
    if [ "$have_fb" -eq 0 ]; then
      echo "marker_emit: a Review marker needs a floor-basis: one sentence on why this model clears Implementation's" >&2
      return 2
    fi
    case "$fb" in
      *[![:space:]]*) : ;;
      *)
        echo "marker_emit: the floor-basis is empty" >&2
        return 2
        ;;
    esac
    case "$fb" in
      *\"*)
        echo "marker_emit: the floor-basis may not contain a double quote (it would end the value)" >&2
        return 2
        ;;
      *[[:cntrl:]]*)
        echo "marker_emit: the floor-basis may not contain a newline, tab or other control character" >&2
        return 2
        ;;
    esac
    if [ "${#fb}" -gt 500 ]; then
      echo "marker_emit: the floor-basis is over 500 bytes; one sentence is enough" >&2
      return 2
    fi
  elif [ "$have_fb" -eq 1 ]; then
    echo "marker_emit: only a Review marker carries a floor-basis (stage is $stage)" >&2
    return 2
  fi
  line="<!-- model-record: stage=$stage model=\"$model\""
  [ "$have_fb" -eq 1 ] && line="$line floor-basis=\"$fb\""
  line="$line -->"
  # the round trip: never print a line the parser cannot read back
  got="$(marker_find "$stage" "$line$MARKER_SEP")" && [ "$got" = "$line" ] \
    && got="$(marker_scan "$line$MARKER_SEP")" && [ "$got" = "ok${tab}$stage${tab}$line" ] \
    && got="$(marker_attr "$line" model)" && [ "$got" = "$model" ] \
    && got="$(marker_attr "$line" floor-basis)" && [ "$got" = "$fb" ] || {
    echo "marker_emit: the line would not read back through lib/model-record.sh unchanged, so it is not printed" >&2
    return 2
  }
  printf '%s\n' "$line"
  return 0
}

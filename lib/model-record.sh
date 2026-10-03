#!/usr/bin/env bash
# lib/model-record.sh — Shared reading of `model-record` markers (A25, #392).
#
# Source, don't execute. Two callers read the same marker fields and must
# agree on how: skills/pre-merge-review/model-record-gate.sh and
# compliance-evidence.sh. Three functions, one copy:
#
#   normalize_model <label>      model label -> comparable form (moved
#                                unchanged from both scripts, #268)
#   effort_rank <value>          low|medium|high -> 0|1|2; anything else
#                                prints nothing (unknown: no claim)
#   marker_attr <marker> <name>  the quoted value of one attribute of a
#                                marker. The marker is TOKENIZED, not
#                                pattern-matched: attributes are name="value"
#                                pairs; a value runs to the next quote, so
#                                text inside a value (`model=`, `>`, `-->`)
#                                is never read as an attribute, and `model`
#                                never matches inside `floor-basis` or
#                                `reviewer-model`. Unquoted, absent: prints
#                                nothing.
#   marker_find <Stage> <text>   every `model-record` marker of that stage in
#                                <text>, one per line (a newline inside a
#                                marker becomes a space). THE marker grammar:
#                                `<!--`, `model-record:`, `stage=<Stage>`,
#                                attributes, and the closing `-->`. A quoted
#                                value may contain anything but a quote: `>`,
#                                `<`, `--`, even `-->` and a newline are text;
#                                the marker ends at the first `-->` outside
#                                quotes (if the quotes are unbalanced, at the
#                                first `-->`).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# Structural, not a per-model alias table (#268): strips the vendor-prefix
# word and a trailing 8-digit snapshot-date suffix, then folds every
# remaining separator and case difference away. Exact-modulo-format, not
# exact-modulo-spelling: a short alias ("opus") stays different from its
# full id ("claude-opus-5"), recorded as debt (PRD.md).
normalize_model() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/^[[:space:]]*claude[- ]*//' \
    | sed -E 's/-[0-9]{8}$//' \
    | sed -E 's/[^a-z0-9]+/ /g' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

effort_rank() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    low) printf '0' ;;
    medium) printf '1' ;;
    high) printf '2' ;;
  esac
  return 0
}

marker_attr() {
  printf '%s' "$1" | tr '\n' ' ' | awk -v want="$2" '
    function ws(c) { return c == " " || c == "\t" }
    function namec(c) { return c ~ /[A-Za-z0-9_-]/ }
    {
      s = $0; n = length(s); i = 1; out = ""; found = 0
      while (i <= n && ws(substr(s, i, 1))) i++
      if (substr(s, i, 4) == "<!--") i += 4
      while (i <= n && ws(substr(s, i, 1))) i++
      if (substr(s, i, 13) == "model-record:") i += 13
      while (i <= n) {
        while (i <= n && ws(substr(s, i, 1))) i++
        if (substr(s, i, 3) == "-->") break
        j = i
        while (j <= n && namec(substr(s, j, 1))) j++
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
          while (j <= n && !ws(substr(s, j, 1))) j++
          i = j
        }
        if (name == want && quoted && !found) { found = 1; out = val }
      }
      printf "%s", out
    }
  '
  return 0
}

marker_find() {
  awk -v want="$1" '
    function ws(c) { return c == " " || c == "\t" || c == "\n" }
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
        if (substr(s, i, 6) != "stage=") { pos = start + 4; continue }
        j = i + 6
        while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_]/) j++
        if (substr(s, i + 6, j - i - 6) != want) { pos = start + 4; continue }
        inq = 0; end = 0
        for (k = j; k <= n; k++) {
          c = substr(s, k, 1)
          if (c == "\"") inq = !inq
          else if (!inq && c == "-" && substr(s, k, 3) == "-->") { end = k + 3; break }
        }
        if (end == 0) {
          q = index(substr(s, j), "-->")
          if (q == 0) { pos = start + 4; continue }
          end = j + q - 1 + 3
        }
        m = substr(s, start, end - start)
        gsub(/\n/, " ", m)
        print m
        pos = end
      }
    }
  ' <<<"$2"
  return 0
}

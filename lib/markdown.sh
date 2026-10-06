#!/usr/bin/env bash
# lib/markdown.sh — the one definition of how a markdown body is read for
# "live" text (#423, slice V2 of #411; design A32 as amended by A32a).
#
# Source, don't execute. lib/model-record.sh sources this file, so every
# script that reads model-record markers gets it. Two functions, one body per
# call, one awk program behind both:
#
#   md_strip_fences <body>   stdout: the body with CRLF and a lone CR read as
#                            LF, and every line inside a fenced code block,
#                            fence lines included, replaced by an empty line.
#                            Code spans and blockquote lines are left alone.
#   live_text <body>         stdout: the same, then blockquoted lines blanked
#                            and inline code spans dropped. The discriminator
#                            is enclosure, not line position: a marker at the
#                            end of a prose line is untouched, the identical
#                            shape in backticks, a fence or after `>` is not.
#                            Content is blanked, never deleted, so line counts
#                            hold. (Origin: issue #308.)
#
# Both return awk's status: non-zero means "not read" and a caller must treat
# it as a failure (a finding in the gate, `indeterminate` in the collector
# and the staleness script), never as "no marker". Nothing is printed on
# stdout on a failure that stops awk before it prints.
#
# What it implements (CommonMark, as GitHub renders it):
#   - Line endings: CRLF is LF, a lone CR is a line break, before any fence
#     logic runs.
#   - A fence opens on a run of >= 3 backticks or tildes, indented 0 to 3
#     spaces, or on a list-item line ("- ", "* ", "+ ", "1. ", "1) ", then the
#     run). A backtick fence whose info string contains a backtick is NOT an
#     opener. A tilde fence may carry a backtick.
#   - It closes on a later line with the same character, a run >= the
#     opener's, indented at most 3 spaces (for a list-item fence: from the
#     item's content column cc to cc + 3), and nothing but blanks after the
#     run. A closing line never carries an info string. An unclosed fence runs
#     to the end of the body. Fence state never crosses a body (one body per
#     call).
#   - A list-item fence also ends where its item ends (A32b): a non-blank
#     line whose indent holds no tab and is shorter than cc (the offset where
#     the run started) ends the item and the fence. That line is not blanked
#     and not a closer; it is read again as an ordinary top-level line, so it
#     can open a new fence or be live text. Blank and whitespace-only lines
#     never end the item, nor does a line with a tab in its indent (tabs are
#     not expanded; keeping the fence open is the safe direction: it quotes
#     too much, never hides less than GitHub does). Why: a marker GitHub shows
#     as quoted must never read as live.
#   - Accepted limits: nested list prefixes ("- - ```"), list items inside a
#     blockquote, tab expansion beyond the rule above, and two shapes that
#     both need list context the lib does not track:
#     * continuation-line-list-fence: a fence opened on the continuation line
#       of a list item (not on its first line) and closed at column 0: the
#       enclosing item's content column is not tracked across lines, so the
#       column-0 closer is read as a closer and a marker after it can read as
#       live where GitHub renders it inside the item (follow-up #445).
#     * ordered-item-after-paragraph (shape s1, goes in the BAD direction): an
#       ordered item numbered 2 or higher right after top-level paragraph text
#       ("text", then "2. ```" with no blank line) cannot interrupt the
#       paragraph on GitHub, so the indent-3 run after it opens a top-level
#       fence there; here "2. ```" opens a list-item fence, and a marker inside
#       the top-level fence reads as LIVE where GitHub renders it quoted.
#       Reason: no list-context tracking. Out of the threat model (the shape
#       is accidental at most; the gate guards against accidental quoting, not
#       forgery). Follow-up #446 (quote under every plausible reading); #445
#       may close with it. A32d reverted the A32c ordered-start rule because
#       a single-shape rule moved the error onto other shapes (wrapped items,
#       lazy lines, after a blockquote).
#   - Blockquote first in live_text: a `> ```` line never toggles fence state.
#
# Portability (the suite runs on macOS: BWK awk, BSD tools, bash 3.2): no
# brace intervals in a regex (mawk 1.3.4 20200120 reads `{0,3}` as literal
# text, and `{n,}` is not greedy under mawk; issue #319), so "0 to 3 spaces"
# is written `? ? ?`, and a run is `+` with a length >= 3 guard. Every
# external command is written with the per-command prefix `LC_ALL=C` (A32c: a
# sourced lib cannot export it for its caller; the four scripts that read
# GitHub text export `LC_ALL=C` themselves, and S235 enforces both): bash 3.2
# ignores a `local LC_ALL` for a child when it is not exported, and BWK awk
# aborts on an invalid UTF-8 byte (`\377`) in a UTF-8 locale. No bash 4+.

_MD_AWK='
function drop_spans(s,   out, n, tick, after, p, q, r) {
  out = ""
  while (match(s, /`+/)) {
    n = RLENGTH; tick = substr(s, RSTART, n)
    out = out substr(s, 1, RSTART - 1)
    after = substr(s, RSTART + n)
    # first backtick run in "after" of length exactly n
    p = 0; r = after; q = 0
    while (match(r, /`+/)) {
      if (RLENGTH == n) { p = q + RSTART; break }
      q += RSTART + RLENGTH - 1; r = substr(r, RSTART + RLENGTH)
    }
    if (p == 0) { out = out tick; s = after }        # unmatched run: literal
    else        { out = out " ";  s = substr(after, p + n) }
  }
  return out s
}

# fence_run(s): the leading run of backticks or tildes of s, "" when s does
# not start with one of >= 3 characters (a 1- or 2-run is a code span or
# text, never a fence: the length guard is load-bearing, see #319 G5).
function fence_run(s,   m) {
  if (match(s, /^`+/) || match(s, /^~+/)) {
    m = substr(s, RSTART, RLENGTH)
    if (length(m) >= 3) return m
  }
  return ""
}

function handle(line,   run, ind, rest, p, islist) {
  if (fch != "") {                                       # inside a fence
    match(line, /^ */); ind = RLENGTH
    # A list-item fence ends with its item: a non-blank line, no tab in its
    # indent, indented less than the content column lcc (A32b). Not blanked
    # and not a closer: it is read again as a top-level line.
    if (lcc > 0 && ind < lcc && line ~ /[^ \t]/ && line !~ /^ *\t/) {
      fch = ""; flen = 0; lcc = 0; handle(line); return
    }
    if (ind <= maxind) {
      run = fence_run(substr(line, ind + 1))
      if (run != "" && substr(run, 1, 1) == fch && length(run) >= flen &&
          substr(line, ind + 1 + length(run)) ~ /^[ \t]*$/) {
        fch = ""; flen = 0; fenced(line); return         # close: no info string
      }
    }
    fenced(line); return
  }
  if ((mode == "live" || mode == "rec") && line ~ /^[ \t]*>/) { quoted(line); return }   # blockquote
  # opener at top level (indent 0 to 3), else on a list-item line
  match(line, /^ ? ? ?/); p = RLENGTH
  run = fence_run(substr(line, p + 1)); islist = 0
  if (run == "" && match(line, /^ ? ? ?([-*+]|[0-9]+[.)])[ ] ? ? ?/)) {
    p = RLENGTH; islist = 1
    run = fence_run(substr(line, p + 1))
  }
  if (run != "") {
    rest = substr(line, p + 1 + length(run))
    if (!(substr(run, 1, 1) == "`" && index(rest, "`") > 0)) {    # info string rule
      fch = substr(run, 1, 1); flen = length(run)
      maxind = islist ? p + 3 : 3; lcc = islist ? p : 0
      fenced(line); return
    }
  }
  if (mode == "live") print drop_spans(line)
  else if (mode == "rec") rec_text(line)
  else print line
}

# What a line that is quoted away becomes: an empty line (strip, live), or,
# for the record reader (mode rec, #425, `-v kind=model-record|pipeline-
# override`), a candidate row `<body-index> TAB <C|Q> TAB <raw line>` when it
# holds the opener of a record: Q (quoted) for a fenced, blockquoted or
# indented line, or one whose opener sits inside a code span; C (live) for the
# rest, which lib/model-record.sh then classifies against the strict pattern.
# (mawk needs every function defined, so the rec_* functions live here.)
function rec_cand(line, flag) { if (line ~ OPEN) print bodyno "\t" flag "\t" line }
function rec_text(line,   ws, sp) {
  if (line !~ OPEN) return
  match(line, /^[ \t]*/); ws = substr(line, 1, RLENGTH)
  if (RLENGTH >= 4 || index(ws, "\t") > 0) { rec_cand(line, "Q"); return }   # indented code
  sp = drop_spans(line)
  print bodyno "\t" ((sp ~ OPEN) ? "C" : "Q") "\t" line
}
function fenced(line) { if (mode == "rec") rec_cand(line, "Q"); else print "" }
function quoted(line) { if (mode == "rec") rec_cand(line, "Q"); else print "" }

# One body is over (bundle mode): the fence state does not cross it.
function body_end() { fch = ""; flen = 0; lcc = 0; bodyno++ }

function feed(line,   i) {
  sub(CR "$", "", line)                                  # CRLF is LF
  while ((i = index(line, CR)) > 0) {                    # a lone CR is a line break
    handle(substr(line, 1, i - 1)); line = substr(line, i + 1)
  }
  handle(line)
}

BEGIN { fch = ""; flen = 0; maxind = 3; lcc = 0; bodyno = 1; CR = sprintf("%c", 13); SEP = sprintf("%c", 30); OPEN = "<!--[ \t]*" kind ":" }
{
  line = $0
  if (bundle == 1) {                                     # U+001E ends a body
    while ((k = index(line, SEP)) > 0) { feed(substr(line, 1, k - 1)); body_end(); line = substr(line, k + 1) }
  }
  feed(line)
}
'

md_strip_fences() {
  printf '%s\n' "$1" | LC_ALL=C awk -v mode=strip "$_MD_AWK"
}

live_text() {
  printf '%s\n' "$1" | LC_ALL=C awk -v mode=live "$_MD_AWK"
}

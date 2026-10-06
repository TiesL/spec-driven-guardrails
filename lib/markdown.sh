#!/usr/bin/env bash
# lib/markdown.sh — the one definition of how a markdown body is read for
# "live" text (#423, slice V2 of #411; design A32 as amended by A32a).
#
# RED-COMMIT STUB. The Developer replaces both bodies. They exist so that
# the tests of #423 fail on an assertion, never on exit 127 ("command not
# found"), as A35a requires. A stub prints nothing on stdout, writes one
# line to stderr and returns 99.
#
# Agreed signatures (A32a):
#   md_strip_fences <body>   stdout: <body> with CRLF and a lone CR read as LF,
#                            and every line inside a fenced code block,
#                            fence lines included, replaced by an empty line.
#                            Code spans and blockquotes are left alone.
#   live_text <body>         stdout: md_strip_fences' view, then blockquoted
#                            lines blanked and inline code spans dropped.
#                            Returns awk's status; non-zero means "not read".
#   Both: one body per call, every external command carries the per-command
#   LC_ALL=C prefix (grep as grep -a), bash 3.2 and BWK/mawk/gawk portable.

md_strip_fences() {
  echo "lib/markdown.sh: md_strip_fences: not implemented (red-commit stub)" >&2
  return 99
}

live_text() {
  echo "lib/markdown.sh: live_text: not implemented (red-commit stub)" >&2
  return 99
}

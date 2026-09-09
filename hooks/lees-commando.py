#!/usr/bin/env python3
"""Reads the PreToolUse input and produces an unambiguous token stream.

This is the only place that decides *how* a command is read. The guard itself
(`hooks/git-guardrails`) only ever compares tokens; it never sees raw text
again. Without that separation, bash itself had to emulate quoting, and that
went wrong: a `;` inside a commit message split the command into pieces, after
which an innocent sentence got judged as a command.

Output: NUL-separated records on stdout.

    c<path>   the working directory from the input (once, first)
    t<token>  a token within the current segment
    e         end of a segment

The leading type character is needed because a token may be empty
(`git commit -m ""`); without it, an empty token couldn't be distinguished
from a segment boundary. NUL is the only safe separator: after quotes are
stripped, a token itself may contain a newline, for example in a multi-line
commit message.

Exit status:
    0  stream follows
    3  input unreadable (not valid JSON, or unclosed quoting)
    4  not applicable (not a Bash call, or no command)
"""

import json
import re
import shlex
import sys

# `<<` or `<<-`, followed by an optionally quoted delimiter. A here-string
# (`<<<`) is not a heredoc, hence the two exclusions on either side.
HEREDOC = re.compile(r"""(?<!<)<<(?!<)(-?)\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\2""")


def zonder_heredocs(tekst):
    """Cuts away heredoc bodies. Separate pass, before tokenizing.

    The content of a heredoc is data, not shell syntax: a line that happens to
    start with `git` there isn't a command. This pass deliberately runs before
    the tokenizer and with no quote awareness at all. If it got entangled with
    tracking quote state, a stray apostrophe in the body (think "don't") would
    flip the quote state for everything that follows.

    The terminator must be the *entire* line (leading tabs aside for `<<-`). A
    substring match would end the body too early, letting data show up as
    judgeable syntax after all — exactly the bug this closes. An unrecognized
    terminator instead drops the rest, and that's the safe direction: at worst
    a missed case, never an extra block.
    """
    regels = tekst.split("\n")
    behouden = []
    i = 0
    while i < len(regels):
        regel = regels[i]
        behouden.append(regel)
        i += 1

        treffer = HEREDOC.search(regel)
        if not treffer:
            continue

        tabs_weg = treffer.group(1) == "-"
        delimiter = treffer.group(3)
        gevonden = False
        while i < len(regels):
            kandidaat = regels[i]
            if tabs_weg:
                kandidaat = kandidaat.lstrip("\t")
            i += 1
            if kandidaat == delimiter:
                gevonden = True
                break
        if not gevonden:
            # No recognizable terminator: the rest is body, or the command is
            # truncated. Don't judge any further.
            break

    return "\n".join(behouden)


def tokeniseer(tekst):
    """Quote-aware tokenization; separators only count outside quotes."""
    lexer = shlex.shlex(tekst, posix=True, punctuation_chars=";|&\n")
    lexer.whitespace_split = True
    # Remove newline from whitespace, so it remains a separator:
    # `git a\ngit b` are two commands, not words of one.
    lexer.whitespace = " \t\r"
    return list(lexer)


def main():
    try:
        invoer = json.load(sys.stdin)
    except Exception:
        return 3

    if not isinstance(invoer, dict) or invoer.get("tool_name") != "Bash":
        return 4

    tool_input = invoer.get("tool_input")
    commando = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(commando, str) or not commando.strip():
        return 4

    werkmap = invoer.get("cwd")
    if not isinstance(werkmap, str):
        werkmap = ""

    try:
        tokens = tokeniseer(zonder_heredocs(commando))
    except ValueError:
        # Unclosed quoting. Don't guess at a reading.
        return 3

    uit = sys.stdout.buffer
    uit.write(b"c" + werkmap.encode("utf-8", "surrogateescape") + b"\0")

    scheiders = {";", "|", "||", "&", "&&", "\n", ";;", "|&"}
    for token in tokens:
        if token in scheiders:
            uit.write(b"e\0")
        else:
            uit.write(b"t" + token.encode("utf-8", "surrogateescape") + b"\0")
    uit.write(b"e\0")
    uit.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())

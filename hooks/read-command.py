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


def without_heredocs(text):
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
    lines = text.split("\n")
    kept = []
    i = 0
    while i < len(lines):
        line = lines[i]
        kept.append(line)
        i += 1

        match = HEREDOC.search(line)
        if not match:
            continue

        strip_tabs = match.group(1) == "-"
        delimiter = match.group(3)
        found = False
        while i < len(lines):
            candidate = lines[i]
            if strip_tabs:
                candidate = candidate.lstrip("\t")
            i += 1
            if candidate == delimiter:
                found = True
                break
        if not found:
            # No recognizable terminator: the rest is body, or the command is
            # truncated. Don't judge any further.
            break

    return "\n".join(kept)


def tokenize(text):
    """Quote-aware tokenization; separators only count outside quotes."""
    lexer = shlex.shlex(text, posix=True, punctuation_chars=";|&\n")
    lexer.whitespace_split = True
    # Remove newline from whitespace, so it remains a separator:
    # `git a\ngit b` are two commands, not words of one.
    lexer.whitespace = " \t\r"
    return list(lexer)


def main():
    try:
        input_data = json.load(sys.stdin)
    except Exception:
        return 3

    if not isinstance(input_data, dict) or input_data.get("tool_name") != "Bash":
        return 4

    tool_input = input_data.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str) or not command.strip():
        return 4

    cwd = input_data.get("cwd")
    if not isinstance(cwd, str):
        cwd = ""

    try:
        tokens = tokenize(without_heredocs(command))
    except ValueError:
        # Unclosed quoting. Don't guess at a reading.
        return 3

    out = sys.stdout.buffer
    out.write(b"c" + cwd.encode("utf-8", "surrogateescape") + b"\0")

    separators = {";", "|", "||", "&", "&&", "\n", ";;", "|&"}
    for token in tokens:
        if token in separators:
            out.write(b"e\0")
        else:
            out.write(b"t" + token.encode("utf-8", "surrogateescape") + b"\0")
    out.write(b"e\0")
    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())

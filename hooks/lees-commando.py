#!/usr/bin/env python3
"""Leest de PreToolUse-invoer en levert een ondubbelzinnige tokenstroom.

Dit is de enige plek die bepaalt *hoe* een commando gelezen wordt. De guard zelf
(`hooks/git-guardrails`) vergelijkt alleen nog tokens; hij krijgt geen ruwe tekst
meer te zien. Zonder die scheiding moest bash zelf quoting nabootsen, en dat ging
mis: een `;` binnen een commitboodschap brak het commando in stukken, waarna een
onschuldige zin als commando werd beoordeeld.

Uitvoer: NUL-gescheiden records op stdout.

    c<pad>    de werkmap uit de invoer (eenmalig, als eerste)
    t<token>  een token binnen het huidige segment
    e         einde van een segment

Het typeteken vooraan is nodig omdat een token leeg mag zijn (`git commit -m ""`);
zonder dat teken zou een leeg token niet van een segmentgrens te onderscheiden
zijn. NUL is het enige veilige scheidingsteken: na het verwijderen van quotes kan
een token zelf een newline bevatten, bijvoorbeeld bij een meerregelige
commitboodschap.

Exitstatus:
    0  stroom volgt
    3  invoer niet te lezen (geen geldige JSON, of quoting die niet sluit)
    4  niet van toepassing (geen Bash-aanroep, of geen commando)
"""

import json
import re
import shlex
import sys

# `<<` of `<<-`, gevolgd door een eventueel gequote delimiter. Een here-string
# (`<<<`) is geen heredoc, vandaar de twee uitsluitingen aan weerszijden.
HEREDOC = re.compile(r"""(?<!<)<<(?!<)(-?)\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\2""")


def zonder_heredocs(tekst):
    """Snijdt heredoc-bodies weg. Aparte pas, vóór het tokeniseren.

    De inhoud van een heredoc is data, geen shell-syntaxis: een regel die daar
    toevallig met `git` begint is geen commando. Deze pas draait bewust vóór de
    tokenizer en zonder enig quote-bewustzijn. Zou hij verweven raken met het
    bijhouden van aanhalingstekens, dan zou een losse apostrof in de body (denk
    aan "don't") de quote-stand voor al het volgende laten omslaan.

    De terminator moet de héle regel zijn (op leidende tabs na bij `<<-`). Een
    substring-match zou de body te vroeg laten eindigen, waardoor data alsnog als
    beoordeelbare syntaxis verschijnt — precies de fout die we hier dichten. Een
    niet-herkende terminator laat de rest juist wegvallen, en dat is de veilige
    kant op: hooguit een gemist geval, nooit een blokkade erbij.
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
            # Geen herkenbare terminator: de rest is body, of het commando is
            # afgekapt. Niet verder beoordelen.
            break

    return "\n".join(behouden)


def tokeniseer(tekst):
    """Quote-bewuste tokenisatie; scheidingstekens tellen alleen buiten quotes."""
    lexer = shlex.shlex(tekst, posix=True, punctuation_chars=";|&\n")
    lexer.whitespace_split = True
    # Newline uit de witruimte halen, zodat hij als scheidingsteken overblijft:
    # `git a\ngit b` zijn twee commando's, geen woorden van één.
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
        # Quoting die niet sluit. Niet gokken naar een lezing.
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

#!/usr/bin/env bash
# hooks/regels.sh — De regels die de PreToolUse-guard (hooks/git-guardrails)
# en de native git-hooks (W26, pre-commit/pre-push) delen: welke branch
# beschermd is en wat de melding zegt.
#
# Puur data, geen invoerlaag. Hoe elke hook zijn commando leest verschilt
# fundamenteel — de quote-bewuste tokenisatie uit lees-commando.py is per
# definitie PreToolUse-specifiek, een native git-hook krijgt nooit een
# commandostring — en hoort dus niet hier. Wat gedeeld kán worden is dít:
# welke branch beschermd is, en de tekst van de melding.
#
# Sourcen, niet uitvoeren.

HOOFDBRANCH="main"

REDEN_COMMIT_OP_MAIN="main krijgt zijn wijzigingen via een PR. Maak eerst een branch — je
       wijzigingen gaan gewoon mee, er raakt niets kwijt:

         git checkout -b feature/<naam>

       Daarna committen en pushen zoals gewoonlijk."

REDEN_PUSH_NAAR_MAIN="main krijgt zijn wijzigingen via een PR, niet via een directe push."

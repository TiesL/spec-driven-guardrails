#!/usr/bin/env bash
# Platform identity check (#422, A35b D1): are the tools this process resolves
# through PATH, and the locale it runs in, the ones the macOS CI leg is named
# for? BWK awk, BSD grep, bash 3.2 (on PATH and running), UTF-8 charmap.
#
# Interface: `bash test/platform-identity.sh`, no arguments. Inputs: PATH and
# the locale variables of the calling environment. On success prints one
# identity line each for awk, grep, bash (plus $BASH_VERSION), locale and
# locale charmap, exit 0. On failure prints the same lines, then one
# `FAIL: <tool or locale> ...` line naming the first mismatch, exit 1.
# Called by test/cases/s229_platform_identity_in_suite.sh. Bash 3.2 compatible.

awk_id="$(awk --version 2>&1)" || awk_id="awk --version failed"
grep_id="$(grep --version 2>&1)" || grep_id="grep --version failed"
bash_id="$(bash --version 2>&1)" || bash_id="bash --version failed"
locale_id="$(locale 2>&1)" || locale_id="locale failed"
charmap="$(locale charmap 2>&1)" || charmap="locale charmap failed"

echo "awk:    $(printf '%s\n' "$awk_id" | sed -n 1p)"
echo "grep:   $(printf '%s\n' "$grep_id" | sed -n 1p)"
echo "bash:   $(printf '%s\n' "$bash_id" | sed -n 1p) (running: $BASH_VERSION)"
echo "locale: $(printf '%s\n' "$locale_id" | tr '\n' ' ')"
echo "locale charmap: $charmap"

case "$awk_id" in
  "awk version "*) ;;
  *) echo "FAIL: awk is not BWK awk (expected 'awk version <date>')"; exit 1 ;;
esac
case "$grep_id" in
  *"BSD grep"*) ;;
  *) echo "FAIL: grep is not BSD grep"; exit 1 ;;
esac
case "$bash_id" in
  *"version 3.2."*) ;;
  *) echo "FAIL: bash on PATH is not bash 3.2"; exit 1 ;;
esac
case "$BASH_VERSION" in
  3.2.*) ;;
  *) echo "FAIL: the running bash is not bash 3.2 ($BASH_VERSION)"; exit 1 ;;
esac
case "$charmap" in
  UTF-8) ;;
  *) echo "FAIL: the UTF-8 locale is not in effect (locale charmap is '$charmap', not UTF-8)"; exit 1 ;;
esac

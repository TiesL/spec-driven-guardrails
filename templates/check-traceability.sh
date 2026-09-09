#!/usr/bin/env bash
# Link 1 of the traceability chain: every functionality has a scenario,
# and every coverage reference resolves.
#
# Called from the project's own `check`:
#
#   ./check-traceability.sh .
#
# Deliberately offline and without `gh`: this is the only link that needs
# no network, and a check that needs network doesn't belong in a local
# `check`. The scenario -> issue -> PR links live in `pre-merge-review` and
# in CI.
#
# No `eval`. This script reads text that isn't fully under its own control;
# an ID that accidentally is a command must never execute anything.

set -uo pipefail

project="${1:-.}"
prd="$project/PRD.md"
scenarios="$project/TEST-SCENARIOS.md"

fouten=0
melding() { echo "traceability: $1" >&2; fouten=$((fouten + 1)); }
waarschuwing() { echo "traceability: warning — $1" >&2; }

for bestand in "$prd" "$scenarios"; do
  if [ ! -f "$bestand" ]; then
    waarschuwing "${bestand#"$project"/} is missing — nothing to check"
    exit 0
  fi
done

# The IDs from a file's headings, one per line.
#
# Only headings count. An ID in running text is not a definition, and a
# spelling like "F13a" in a sentence would otherwise bring a non-existent
# item into being. The prefix isn't fixed: `F`/`S` is customary, but
# `R`/`A`/`B`/`P` and `OP` occur in existing projects, and a hardcoded list
# would make this script unusable there on day one.
ids_uit_koppen() {
  grep -oE '^#+[[:space:]]+[A-Z]{1,2}[0-9]+[a-z]?([[:space:]]|$)' "$1" \
    | sed 's/^#*[[:space:]]*//; s/[[:space:]]*$//'
}

# The raw content of the Dekt: fields, one comma-separated piece per line.
#
# Only the field counts, at the start of a line. That prevents false
# positives by construction: a sentence that happens to contain "S1" is
# not a reference.
dekt_ruw() {
  grep '^\*\*Dekt:\*\*' "$1" \
    | sed 's/^\*\*Dekt:\*\*[[:space:]]*//' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -v '^$'
}

# The valid IDs from the Dekt: fields.
#
# A placeholder between angle brackets is skipped: a freshly scaffolded
# project carries `**Dekt:** <F1>` from the template, and a check that
# fails on that immediately would be disabled by tomorrow.
dekt_tokens() {
  dekt_ruw "$1" | grep -E '^[A-Z]{1,2}[0-9]+[a-z]?$'
}

# Everything in a Dekt: field that's neither an ID nor a placeholder.
#
# Reporting this separately instead of silently filtering it out. A typo
# like `F-2`, a list with spaces instead of commas, or a field that runs
# across two lines would otherwise vanish without a trace — and then the
# check promises that every token resolves while it's exactly the broken
# tokens it doesn't see.
dekt_ongeldig() {
  dekt_ruw "$1" | grep -vE '^[A-Z]{1,2}[0-9]+[a-z]?$' | grep -v '<'
}

prd_ids="$(ids_uit_koppen "$prd")"
scenario_ids="$(ids_uit_koppen "$scenarios")"

# Duplicate IDs within one file. That's a real error, not a style issue: a
# reference to such an ID can no longer resolve unambiguously.
for paar in "PRD.md:$prd_ids" "TEST-SCENARIOS.md:$scenario_ids"; do
  naam="${paar%%:*}"
  dubbel="$(printf '%s\n' "${paar#*:}" | grep -v '^$' | sort | uniq -d)"
  if [ -n "$dubbel" ]; then
    for id in $dubbel; do
      melding "$naam contains $id more than once — a reference to it is ambiguous"
    done
  fi
done

# A PRD with no IDs is not an error but a warning. One of the four
# existing projects is exactly this case; failing hard there would disable
# the script immediately, and then it checks nothing anywhere.
if [ -z "$prd_ids" ]; then
  waarschuwing "PRD.md has no ID headings — link 1 can't be checked here"
  [ "$fouten" -eq 0 ] && exit 0
  exit 1
fi

# Every Dekt: token resolves in the IDs of the *other* file.
controleer_verwijzingen() {
  local bestand="$1" naam="$2" doelen="$3" doelnaam="$4" token
  for token in $(dekt_tokens "$bestand"); do
    printf '%s\n' "$doelen" | grep -qx "$token" \
      || melding "$naam refers to $token, but that ID doesn't exist in $doelnaam"
  done
}
# Reporting broken tokens, in both files.
for paar in "PRD.md:$prd" "TEST-SCENARIOS.md:$scenarios"; do
  naam="${paar%%:*}"
  while IFS= read -r stuk; do
    [ -n "$stuk" ] || continue
    melding "$naam: '$stuk' in a Dekt: field is not a valid ID — expected comma-separated tokens like F1, S2, or S2b"
  done <<EOF
$(dekt_ongeldig "${paar#*:}")
EOF
done

controleer_verwijzingen "$scenarios" "TEST-SCENARIOS.md" "$prd_ids" "PRD.md"
controleer_verwijzingen "$prd" "PRD.md" "$scenario_ids" "TEST-SCENARIOS.md"

# Link 1 itself: every functionality is covered by at least one scenario.
#
# If no scenario carries a Dekt: field at all, this project isn't using
# the convention yet. Then every functionality is by definition uncovered,
# and this script would complain about *all* items at once on introduction.
# That's exactly the retrofit the design avoids: the convention applies
# starting with the next piece of work. Hence a warning, and enforcement
# once the first reference appears.
gedekt="$(dekt_tokens "$scenarios" | sort -u)"
if [ -z "$gedekt" ]; then
  waarschuwing "TEST-SCENARIOS.md doesn't carry any Dekt: fields yet — link 1 is only enforced once the first reference appears"
  [ "$fouten" -eq 0 ] && exit 0
  exit 1
fi

for id in $prd_ids; do
  printf '%s\n' "$gedekt" | grep -qx "$id" \
    || melding "$id has no scenario covering it"
done

[ "$fouten" -eq 0 ] || exit 1
echo "traceability: in orde"

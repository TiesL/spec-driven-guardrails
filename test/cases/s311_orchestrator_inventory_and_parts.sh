#!/usr/bin/env bash
# S311 — every rule has one ID in one part, the parts stand alone, and the
# inventory matches the core (#499 AC2, AC3, AC7)
# Covers: F38
#
# Seam: the files ORCHESTRATOR.md, orchestrator-rules.tsv,
# test/behavior/orchestrator-scenarios.md and `agent-dispatch.py
# --list-checks`, read as data by the shared harness
# test/fixtures/orchestrator-core.py (which the AC14-amended scenarios use
# too). Each negative control breaks one thing in a copy and must fail by
# its own error name.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

R="$TEST_REPO_ROOT"
H="$R/test/fixtures/orchestrator-core.py"
ORCH="$R/skills/role-contracts/ORCHESTRATOR.md"
TSV="$R/skills/role-contracts/orchestrator-rules.tsv"
SCEN="$R/test/behavior/orchestrator-scenarios.md"
HOOK="$R/hooks/agent-dispatch.py"
PINS="$R/test/fixtures/orchestrator-core-pins.tsv"

for f in "$TSV" "$HOOK"; do
  [ -r "$f" ] || { fail "S311 — ${f#"$R"/} is missing"; test_done; }
done
checks="$(python3 -I "$HOOK" --list-checks 2>/dev/null | tr '\n' ' ')"
[ -n "$checks" ] || fail "S311 — agent-dispatch.py --list-checks printed nothing"

run_check() { # orch tsv scen [pins] -> harness output; status in $st
  out="$(python3 -I "$H" check --orch "$1" --tsv "$2" --scen "$3" --pins "${4:-$PINS}" --repo "$R" --list-checks "$checks" 2>&1)"
  st=$?
}
[ -r "$PINS" ] || fail "S311/pins — ${PINS#"$R"/} is missing"
run_check "$ORCH" "$TSV" "$SCEN"
[ "$st" = 0 ] || fail "S311/real — structure check failed:
$out"

# The part lists A41 fixes, from the inventory side.
p1="$(awk -F'\t' 'NR>1 && $4=="1"{print $1}' "$TSV" | sort -V | tr '\n' ' ')"
p2="$(awk -F'\t' 'NR>1 && $4=="2"{print $1}' "$TSV" | sort -V | tr '\n' ' ')"
[ "$p1" = "OR1 OR2 OR3 OR4 OR5 OR6 OR7 OR8 OR11 OR12 OR13 OR33 OR34 OR35 OR43 OR45 OR46 " ] \
  || fail "S311/part1 — inventory part 1 is '$p1'"
[ "$p2" = "OR9 OR10 OR14 OR15 OR16 OR17 OR18 OR19 OR20 OR21 OR22 OR23 OR24 OR25 OR26 OR27 OR28 OR29 OR30 OR31 OR32 OR36 OR37 OR38 OR39 OR40 OR41 OR42 OR44 OR47 OR48 " ] \
  || fail "S311/part2 — inventory part 2 is '$p2'"
grep -qxF '<!-- session-context: slot -->' "$ORCH" || fail "S311 — no marker line"
grep -E '^ *- .*<!-- session-context: slot -->' "$ORCH" >/dev/null && fail "S311 — the marker line is a list item"

# --- negative controls ----------------------------------------------------
neg() { # name expected-error orch tsv scen [pins [id-named]]
  run_check "$3" "$4" "$5" "${6:-}"
  if [ "$st" = 0 ]; then
    fail "S311/neg-$1 — the break passed"
  elif ! grep -q "^ERROR $2:" <<<"$out"; then
    fail "S311/neg-$1 — expected ERROR $2, got: $out"
  elif [ -n "${7:-}" ]; then
    for id in $7; do
      named="$(grep "^ERROR $2:" <<<"$out")"
      grep -qw "$id" <<<"$named" || fail "S311/neg-$1 — ERROR $2 does not name $id: $out"
    done
  fi
}
d="$SANDBOX"
grep -v '^- OR20 ' "$ORCH" > "$d/o-removed.md"
neg id-removed id-missing "$d/o-removed.md" "$TSV" "$SCEN"

awk -v l="$(grep '^- OR9 ' "$ORCH")" '{print} /^## Dispatch$/{print ""; print l}' "$ORCH" > "$d/o-dup.md"
neg id-duplicated id-not-once "$d/o-dup.md" "$TSV" "$SCEN"

awk -F'\t' -v OFS='\t' '$1=="OR9"{$4="1"} {print}' "$TSV" > "$d/t-part.tsv"
neg part-changed wrong-part "$ORCH" "$d/t-part.tsv" "$SCEN"

sed 's/^- OR15 Review round brief/- OR15 See above. Review round brief/' "$ORCH" > "$d/o-above.md"
neg see-above above-below "$d/o-above.md" "$TSV" "$SCEN"

grep -v '^Part 1 of 2 (fundamentals) also applies' "$ORCH" > "$d/o-header.md"
neg header-removed part-header "$d/o-header.md" "$TSV" "$SCEN"

awk -F'\t' -v OFS='\t' '$1=="OR20"{$5=""} {print}' "$TSV" > "$d/t-cov.tsv"
neg judgment-uncovered judgment-no-ob "$ORCH" "$d/t-cov.tsv" "$SCEN"

sed 's/^### OB21 · OR20$/### OB21 · OR20, OR99/' "$SCEN" > "$d/s-or99.md"
neg ob-cites-or99 ob-unknown-id "$ORCH" "$TSV" "$d/s-or99.md"

awk -F'\t' -v OFS='\t' '$3=="hook:no-fork"{$3="hook:no-forks"} {print}' "$TSV" > "$d/t-hook.tsv"
neg hook-renamed hook-checks "$ORCH" "$d/t-hook.tsv" "$SCEN"

sed 's/^- OR11 \(.*\)Any new commit that changes the work lapses the approval/- OR11 \1A new commit keeps the approval/' "$ORCH" > "$d/o-or11.md"
neg or11-weakened or11-wording "$d/o-or11.md" "$TSV" "$SCEN"

sed 's/in OR5 order, //' "$ORCH" > "$d/o-xref.md"
neg xref-dropped xref-or36 "$d/o-xref.md" "$TSV" "$SCEN"

awk -F'\t' -v OFS='\t' '$1=="OR29"{$2="Dispatch tool takes no effort"} {print}' "$TSV" > "$d/t-text.tsv"
neg rule-text-in-tsv row-name "$ORCH" "$d/t-text.tsv" "$SCEN"

# --- core-tier pins (A41 amendment 6ccad5c) -------------------------------
# A pin file computed here, independently of the harness, from the real
# core and inventory: SHA-256 of each `core` rule's item text, from `OR<n> `
# to the item's end, continuation lines joined by single spaces, trailing
# whitespace trimmed, prefixed by depth=<depth> and a newline. Header line `id<TAB>sha256`.
pin_make() { # orch tsv -> pin file on stdout
  python3 -I - "$1" "$2" <<'PY'
import hashlib, re, sys
orch, tsv = sys.argv[1:3]
core = [l.split("\t")[0] for l in open(tsv).read().split("\n")[1:]
        if len(l.split("\t")) > 2 and l.split("\t")[2] == "core"]
lines = open(orch).read().split("\n")
item = re.compile(r"^( *)- (OR\d+) ")
print("id\tsha256")
for rid in core:
    for i, l in enumerate(lines):
        m = item.match(l)
        if m and m.group(2) == rid:
            parts, j = [l[l.index(rid):].rstrip()], i + 1
            while (j < len(lines) and lines[j].strip() and lines[j].startswith(" ")
                   and not item.match(lines[j])):
                parts.append(lines[j].strip()); j += 1
            print("%s\t%s" % (rid, hashlib.sha256(("depth=%d\n" % (len(m.group(1)) // 2) + " ".join(parts).rstrip()).encode()).hexdigest()))
            break
PY
}
pin_make "$ORCH" "$TSV" > "$d/pins-base.tsv"
[ "$(wc -l < "$d/pins-base.tsv" | tr -d ' ')" = 8 ] || fail "S311/pins — expected 7 core rules plus a header, got: $(cat "$d/pins-base.tsv")"
pin_ids="$(cut -f1 "$d/pins-base.tsv" | tail -n +2 | tr '\n' ' ')"
[ "$pin_ids" = 'OR24 OR25 OR26 OR27 OR29 OR32 OR44 ' ] \
  || fail "S311/pins — core IDs are not OR24-27, OR29, OR32, OR44"
# Real tree: the committed pin file equals the independently computed one.
if [ -r "$PINS" ]; then
  cmp -s "$PINS" "$d/pins-base.tsv" || fail "S311/pins-real — committed pins differ from the hash definition:
$(diff "$PINS" "$d/pins-base.tsv")"
fi
# The base pins pass against the unbroken core (the controls below differ
# from it by exactly one break).
run_check "$ORCH" "$TSV" "$SCEN" "$d/pins-base.tsv"
[ "$st" = 0 ] || fail "S311/pins-base — computed pins fail the real core: $out"

# 2. OR26's negation inverted
sed 's/^  - OR26 No orchestrator-written issue comment carries/  - OR26 Every orchestrator-written issue comment carries/' "$ORCH" > "$d/o-or26.md"
neg pin-or26-inverted pin-mismatch "$d/o-or26.md" "$TSV" "$SCEN" "$d/pins-base.tsv" OR26
grep -q 'Every orchestrator-written issue comment carries' <<<"$out" \
  || fail "S311/neg-pin-or26-inverted — the error does not print the current item text: $out"
# 3. OR29 and OR44 changed by one character
sed -e 's/^- OR29 Dispatch tool takes no effort/- OR29 Dispatch tool takes no efforts/' \
    -e 's/one prose line: `<YYYY-MM-DD>/one prose line: `<YYYY-MM-DX>/' "$ORCH" > "$d/o-or2944.md"
neg pin-or29-or44-one-char pin-mismatch "$d/o-or2944.md" "$TSV" "$SCEN" "$d/pins-base.tsv" "OR29 OR44"
# 4. a pin row deleted
grep -v '^OR32	' "$d/pins-base.tsv" > "$d/p-del.tsv"
neg pin-row-deleted pin-missing "$ORCH" "$TSV" "$SCEN" "$d/p-del.tsv" OR32
# 5. a pin row for a non-core ID
{ cat "$d/pins-base.tsv"; printf 'OR20\t%s\n' "$(printf 'x' | shasum -a 256 | cut -d' ' -f1)"; } > "$d/p-extra.tsv"
neg pin-row-non-core pin-extra "$ORCH" "$TSV" "$SCEN" "$d/p-extra.tsv" OR20
# 6. a rule's tier set to core with no pin row
awk -F'\t' -v OFS='\t' '$1=="OR28"{$3="core"} {print}' "$TSV" > "$d/t-core.tsv"
neg tier-core-no-pin pin-missing "$ORCH" "$d/t-core.tsv" "$SCEN" "$d/pins-base.tsv" OR28
# 7. only the pin hash edited
awk -F'\t' -v OFS='\t' '$1=="OR24"{$2=substr($2,2) "0"} {print}' "$d/pins-base.tsv" > "$d/p-hash.tsv"
neg pin-hash-edited pin-mismatch "$ORCH" "$TSV" "$SCEN" "$d/p-hash.tsv" OR24
grep -q 'No design-class finding fixed without Architect step' <<<"$out" \
  || fail "S311/neg-pin-hash-edited — the error does not print the current item text: $out"
# 8. the rules' own tests stay (the pins do not replace them)
for t in s203 s218 s238 s240 s280; do
  ls "$R"/test/cases/${t}_*.sh >/dev/null 2>&1 || fail "S311/pins-own-tests — no test case $t"
done

# Duplicate IDs in a covered_by cell (finding tsv-duplicate-covered-by; red
# on dd3117a: the OR11 row lists S311 twice).
dups="$(awk -F'\t' 'NR>1{n=split($5,a,","); delete seen; for(i=1;i<=n;i++){if(a[i]!="" && seen[a[i]]++){print $1" repeats "a[i]}}}' "$TSV")"
[ -z "$dups" ] || fail "S311/tsv-duplicate-covered-by — $dups"

# #599: OR31 owns both checks, without dropping inventory equality checks.
row="$(awk -F '\t' '$1=="OR31"{print $3}' "$TSV")"
[ "$row" = 'hook:marker-command,role-stage' ] || fail "S311/#599 — OR31 hook tier must be hook:marker-command,role-stage"
for needle in '--role' OR5; do
  python3 -I - "$ORCH" "$d/o-or31.md" "$needle" <<'PYM'
from pathlib import Path
import sys
p,out,needle=sys.argv[1:]
s=Path(p).read_text();s='\n'.join(l.replace(needle,'REMOVED-599') if l.startswith('- OR31 ') else l for l in s.split('\n'));Path(out).write_text(s)
PYM
  neg "or31-$needle" xref-or31 "$d/o-or31.md" "$TSV" "$SCEN"
done
test_done

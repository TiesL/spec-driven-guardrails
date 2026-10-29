#!/usr/bin/env bash
# S380 — the Codex permission baseline document carries the pinned content, never a bypass flag, and INSTRUCTIONS.md points to it.
# Covers: F57
#
# Issue #590, AC0, AC1, AC4, AC5, AC6, AC9, AC14 (doc-text pins; live
# enforcement is manual evidence, AC11). Falsifiers: no baseline file, a
# profile without workspace-write or verified/assumed marking, a catch-all
# gh prompt rule or a gh allow, an automatic allow for pipeline-override.sh
# or epic-auto-close.sh, no merge-confirmation limits, no needs-list link,
# the bypass flag outside a prohibition, no INSTRUCTIONS.md pointer.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

doc="$TEST_REPO_ROOT/adapters/codex/permission-baseline.md"
instr="$TEST_REPO_ROOT/adapters/codex/INSTRUCTIONS.md"
flag="--dangerously-bypass-""approvals-and-sandbox"

pin() { # description, extended regex (case-insensitive), file
  grep -Eiq -- "$2" "$3" 2>/dev/null || fail "S380 — $1 (missing: $2)"
}

if [ ! -f "$doc" ]; then
  fail "S380 — adapters/codex/permission-baseline.md does not exist"
else
  pin "AC1 workspace-write profile" 'sandbox_mode = "workspace-write"' "$doc"
  pin "AC1 approvals to the user" 'approvals_reviewer = "user"' "$doc"
  pin "AC1 keys marked verified" '\bverified\b' "$doc"
  pin "AC1 keys marked assumed" '\bassumed\b' "$doc"
  pin "AC0 write confinement is not read secrecy" 'read secrecy' "$doc"
  pin "AC0 needs list" 'needs list' "$doc"
  pin "AC9 trade-off lines" 'trade-off' "$doc"
  pin "AC9 a section on what Codex cannot match" '^#+ .*cannot match' "$doc"
  pin "AC5 merge into main needs explicit confirmation" 'main.*explicit confirmation|explicit confirmation.*main' "$doc"
  pin "AC5 merge-preflight named" 'merge-preflight\.sh' "$doc"
  pin "AC5 prefix rule limit" 'prefix rule' "$doc"
  pin "AC14 explicit git actions tied to needs-list item 3" 'explicit actions.*item 3' "$doc"

  # AC4: the rules set. Every prefix_rule line in a fenced block, tagged
  # "conv" when the block sits under a heading or opens with a comment that
  # says "convenience widening", else "base". Output: <tag><TAB><line>.
  tagged="$(awk '
    /^#+ /{ head=tolower($0) }
    /^```/{ if (inb) { inb=0; next } inb=1; first=1; conv=(head ~ /convenience widening/); next }
    inb && first { first=0; if (tolower($0) ~ /convenience widening/) conv=1 }
    inb && /prefix_rule\(/ { print (conv ? "conv" : "base") "\t" $0 }
  ' "$doc")"
  conv_rules="$(awk -F'\t' '$1=="conv"' <<< "$tagged")"
  base_rules="$(awk -F'\t' '$1=="base"' <<< "$tagged")"

  # No allow in the baseline snippet (an allow runs outside the sandbox).
  if grep -q 'decision *= *"allow"' <<< "$base_rules"; then
    fail "S380 — AC4 the baseline rules snippet carries an allow that runs outside the sandbox"
  fi
  # A gh pr merge prompt rule is part of the baseline.
  merge_rule="$(grep -E 'pattern *= *\["gh", *"pr", *"merge"\]' <<< "$base_rules" || true)"
  if ! grep -q '"prompt"' <<< "$merge_rule"; then
    fail "S380 — AC4 no gh pr merge prompt rule in the baseline rules"
  fi
  # No catch-all gh prompt, no blanket gh allow, no script allowed by prefix, anywhere.
  all_rules="$(awk -F'\t' '{print $2}' <<< "$tagged")"
  gh_rules="$(grep -E 'pattern *= *\["gh"\]' <<< "$all_rules" || true)"
  if [ -n "$gh_rules" ]; then
    fail "S380 — AC4 blanket gh rule (allow or catch-all prompt): $gh_rules"
  fi
  script_rules="$(grep -E 'pipeline-override|epic-auto-close|wait-for-ci|merge-preflight|model-record-emit' <<< "$all_rules" || true)"
  if grep -q 'allow' <<< "$script_rules"; then
    fail "S380 — AC4 a script is allowed by prefix: $script_rules"
  fi
  # The optional convenience block exists; every line in it carries a trade-off note.
  if [ -z "$conv_rules" ]; then
    fail "S380 — AC4 no labelled optional convenience widening block with gh read allows"
  else
    if ! grep -q 'gh' <<< "$conv_rules"; then
      fail "S380 — AC4 the convenience block carries no gh read allow"
    fi
    thin="$(awk -F'\t' '{ n=index($2,"#"); c=(n ? substr($2,n+1) : ""); gsub(/^ +| +$/,"",c); if (length(c) < 15) print $2 }' <<< "$conv_rules")"
    if [ -n "$thin" ]; then
      fail "S380 — AC9 convenience line without a trade-off note: $thin"
    fi
    # #595 AC4 (L9): a comment names only flags the command really has. The
    # flag set comes from the local `gh <command> --help` (offline).
    if command -v gh >/dev/null 2>&1; then
      while IFS= read -r rule; do
        [ -n "$rule" ] || continue
        cmd="$(sed -E 's/^[^[]*\[("[^]]*")\].*$/\1/' <<< "$rule" | tr -d '",' | sed 's/^ *//')"
        comment="${rule#*#}"
        help_flags="$(gh ${cmd#gh } --help 2>&1 | grep -oE -- '--[a-z][a-z-]*' | sort -u || true)"
        [ -n "$help_flags" ] || { fail "S380 — AC4 no gh help flags for '$cmd'"; continue; }
        for cflag in $(grep -oE -- '--[a-z][a-z-]*' <<< "$comment" | sort -u); do
          grep -qx -- "$cflag" <<< "$help_flags" || fail "S380 — AC4 the comment for '$cmd' names $cflag, which that command does not have"
        done
      done <<< "$(awk -F'\t' '{print $2}' <<< "$conv_rules")"
    else
      echo "S380: gh not installed, AC4 flag comparison skipped" >&2
    fi
    pin "AC4 the block is optional" 'optional' "$doc"
    pin "AC4 the block is to be deleted after the proxy proof" 'delete[d]?.*(proof|proxy)|(proof|proxy).*delete' "$doc"
  fi

  # AC2: the Network section says the convenience block bypasses network_access = false.
  net="$(awk '/^#+ /{ s=($0 ~ /Network/) } s' "$doc")"
  if ! grep -Eiq 'convenience.*bypass|bypass.*convenience' <<< "$net"; then
    fail "S380 — AC2 the Network section does not say the convenience block bypasses network_access = false"
  fi

  # AC1: approvals_reviewer = "user" above the first [table] header, and the doc says so.
  toml="$(awk '/^```toml/{f=1; next} /^```/{f=0} f' "$doc")"
  first_table="$(grep -n '^\[' <<< "$toml" | head -n 1 | cut -d: -f1)"
  reviewer_line="$(grep -n '^approvals_reviewer *= *"user"' <<< "$toml" | head -n 1 | cut -d: -f1)"
  if [ -z "$reviewer_line" ] || { [ -n "$first_table" ] && [ "$reviewer_line" -gt "$first_table" ]; }; then
    fail "S380 — AC1 approvals_reviewer = \"user\" is not above the first [table] header"
  fi
  # #595 AC3 (L6): every key of the sandbox-config snippet (the first toml
  # block) carries a [V]/[A] mark on its own line or on its table header.
  # Presence only; whether a mark is true is not judged here.
  unmarked_keys() { # stdin: toml text; prints each key without a mark
    awk '
      /^\[/ { tmark = ($0 ~ /\[[VA]/); next }
      /^[A-Za-z_][A-Za-z0-9_.]* *=/ { if ($0 !~ /\[[VA]/ && !tmark) { k=$0; sub(/ *=.*/, "", k); print k } }
    '
  }
  missing_marks="$(unmarked_keys <<< "$(awk '/^```toml/{n++} n==1' "$doc" | sed '1d;/^```$/,$d')")"
  [ -z "$missing_marks" ] || fail "S380 — AC3 snippet key without a [V]/[A] mark: $missing_marks"
  # Mutation arm: the pin must see a mark removed from one key and name it.
  mutated="$(sed '/^exclude_slash_tmp/s/\[[VA][^#]*//' "$doc" | awk '/^```toml/{n++} n==1' | sed '1d;/^```$/,$d')"
  seen="$(unmarked_keys <<< "$mutated")"
  case "$seen" in
    *exclude_slash_tmp*) ;;
    *) fail "S380 — AC3 mutation arm: a snippet key with its mark removed was not named (got: '$seen')" ;;
  esac
  pin "AC1 the doc says the key goes above the first table header" 'above the first.*(table|header)' "$doc"

  # AC6: no line inside a fenced block carries the flag.
  fenced="$(awk '/^```/{f=!f; next} f' "$doc")"
  if grep -q -- "$flag" <<< "$fenced"; then
    fail "S380 — AC6 bypass flag inside a profile, rules or example block"
  fi
fi

# AC6: anywhere in the tree (not this test, not the scenario list), a line
# with the flag must also say never, not or do not.
hits="$(grep -rIn --exclude-dir=.git --exclude-dir=test --exclude=TEST-SCENARIOS.md -- "$flag" "$TEST_REPO_ROOT" 2>/dev/null || true)"
bad_hits="$(grep -viE 'never|not' <<< "$hits" || true)"
if [ -n "$hits" ] && [ -n "$bad_hits" ]; then
  fail "S380 — AC6 flag outside a prohibition: $bad_hits"
fi

# AC14: INSTRUCTIONS.md points to the baseline and keeps the automation statement.
pin "AC14 INSTRUCTIONS.md names the baseline document" 'permission-baseline\.md' "$instr"
pin "AC14 no SessionStart/PostToolUse/SessionEnd automation" 'no SessionStart/PostToolUse/SessionEnd automation' "$instr"

test_done

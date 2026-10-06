#!/usr/bin/env bash
# S235 — the locale guard is structural: every script that reads GitHub text exports LC_ALL=C first, and every external text command in the two text-reading libs carries the LC_ALL=C prefix; the lint is itself mutation-checked.
# Covers: F34, F42
#
# Issue #423 AC7 (A32c, round 3 of PR #443). Rounds 1 and 2 each found the
# next unprefixed text command, one site at a time, because the only oracle
# was one behavioural test per site. This test is the single oracle for the
# whole class (A32a promised "a lint in T1 checks the prefix"):
#   L1  each of model-record-gate.sh, compliance-evidence.sh,
#       role-label-staleness.sh and review-rounds.sh has `export LC_ALL=C` as
#       its first statement (after the shebang, comments, blank lines and
#       `set` lines), and nowhere else assigns LC_ALL to something other than
#       C or unsets it;
#   L2  in lib/markdown.sh and lib/model-record.sh every command-position
#       awk, grep, sed, tr, cut, sort and uniq is directly preceded by
#       `LC_ALL=C ` (and grep is always `grep -a`), unless its line carries
#       `# locale-exempt: <reason>`. The number of sites checked is printed
#       and must be above zero (a lint that scans nothing is red);
#   L3  the lint is red on a scratch copy with one export removed from each
#       script in turn, with the export weakened (a non-C value, an unset), and
#       with one lib prefix removed (effort_rank's tr, normalize_model's first
#       sed, a markdown.sh awk, a parser awk).
#
# The lint lives in test/fixtures/locale-lint.sh (test code). Its own
# recognizing power is proven first on synthetic text and a synthetic tree
# (every one of the seven commands, in every command position, flagged when
# bare; quoted text and `command -v awk` not flagged), so L3 does not depend on
# the repo's current content. The L3 mutants on the REAL tree need a green real
# baseline, and are reported once as "not run" while L1/L2 are red.
#
# ALLOW-LIST (locale-exempt): empty today. A line may carry
# `# locale-exempt: <reason>` only when the command provably never sees text
# that came from GitHub (name what it reads, in the reason). An exemption with
# no reason is itself a violation, and an exempt site still counts as a site.
# Accepted limits of the lint (a tripwire, not a parser): `${...}` is skipped
# to its first `}`; a grep whose flags continue on a backslash-continued line
# is not checked for -a; heredoc bodies are read as code. The three
# libs that do not read GitHub text (changes.sh, git-env.sh, nfr.sh) and every
# script outside the four are out of scope (A32c threat model).
#
# Seam: test/fixtures/locale-lint.sh over the file tree; bash 3.2, BWK awk,
# BSD tools. No network, no locale needed.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/locale-lint.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/locale-lint.sh"
sandbox_create
trap sandbox_destroy EXIT

NL=$'\n'
ROOT="${LL_ROOT:-$TEST_REPO_ROOT}"

# violations <root>: every L1 and L2 violation line, one per line (empty = green).
violations() {
  { ll_l1 "$1"; ll_l2 "$1"; } | LC_ALL=C grep -a '^V' || true
}
sites_of() { # root: the number of L2 sites checked, summed over the libs
  ll_l2 "$1" | LC_ALL=C awk -F '\t' '$1 == "S" { n += $3 } END { print n + 0 }'
}
# red <label> <root>: the lint must report at least one violation for the tree.
expect_red() {
  local label="$1" v
  v="$(violations "$2")"
  [ -n "$v" ] || fail "S235 L3 — $label: the lint stayed GREEN (the mutant survives)"
}
expect_green() {
  local label="$1" v
  v="$(violations "$2")"
  [ -z "$v" ] || fail "S235 $label — expected no violation, got: $(printf '%s' "$v" | LC_ALL=C tr '\n' '|' | LC_ALL=C head -c 700)"
}

# =========================================================================
# 0. the lint recognizes what it must (synthetic text, independent of the repo)
# =========================================================================
snip() { # label want-violations text
  local out got
  out="$(ll_l2_text snippet "$3")"
  got="$(printf '%s\n' "$out" | LC_ALL=C grep -a -c '^V' || true)"
  [ "$got" = "$2" ] || fail "S235 lint/$1 — expected $2 violation(s), got $got: $(printf '%s' "$out" | LC_ALL=C tr '\n' '|')"
}
for cmd in awk grep sed tr cut sort uniq; do
  extra=""
  [ "$cmd" = grep ] && extra="-a "
  snip "bare $cmd at the line start" 1 "$cmd ${extra}x file"
  snip "bare $cmd after a pipe" 1 "cat f | $cmd ${extra}x"
  snip "bare $cmd after a pipe at a line end" 1 "cat f |${NL}  $cmd ${extra}x"
  snip "bare $cmd inside \$( )" 1 "x=\$($cmd ${extra}x f)"
  snip "bare $cmd inside \"\$( )\"" 1 "case \"\$(printf x | $cmd ${extra}x)\" in a) :;; esac"
  snip "bare $cmd after ;" 1 "a; $cmd ${extra}x"
  snip "bare $cmd after &&" 1 "a && $cmd ${extra}x"
  snip "bare $cmd after ||" 1 "a || $cmd ${extra}x"
  snip "bare $cmd in a subshell" 1 "( $cmd ${extra}x )"
  snip "bare $cmd after then" 1 "if a; then $cmd ${extra}x; fi"
  snip "bare $cmd after if" 1 "if $cmd ${extra}x f; then :; fi"
  snip "bare $cmd after a backtick" 1 "x=\`$cmd ${extra}x f\`"
  snip "bare $cmd after another env assignment" 1 "FOO=1 $cmd ${extra}x"
  snip "bare $cmd after a case arm" 1 "case a in a) $cmd ${extra}x ;; esac"
  snip "prefixed $cmd" 0 "LC_ALL=C $cmd ${extra}x f"
  snip "prefixed $cmd after a pipe" 0 "cat f | LC_ALL=C $cmd ${extra}x"
  snip "prefixed $cmd inside \$( )" 0 "x=\"\$(LC_ALL=C $cmd ${extra}x f)\""
  snip "prefixed $cmd after another assignment" 0 "FOO=1 LC_ALL=C $cmd ${extra}x"
  snip "$cmd named only as an argument" 0 "command -v $cmd >/dev/null"
  snip "$cmd in a string" 0 "echo \"see ($cmd) and $cmd\""
  snip "$cmd in single quotes" 0 "echo 'a | $cmd x'"
  snip "$cmd in a comment" 0 "# a | $cmd x"
  snip "$cmd in a multi-line single-quoted program" 0 "p='${NL}$cmd x${NL}  | $cmd y${NL}'"
  snip "exempt $cmd with a reason" 0 "$cmd ${extra}x # locale-exempt: reads only the repo's own file names"
  snip "exempt $cmd with no reason" 2 "$cmd ${extra}x # locale-exempt:"
done
snip "grep -a is required" 1 "LC_ALL=C grep -E x f"
snip "grep -a accepted" 0 "LC_ALL=C grep -a -E x f"
snip "grep -aE accepted" 0 "LC_ALL=C grep -aE x f"
snip "grep -qa accepted" 0 "LC_ALL=C grep -qa x f"
snip "grep -a after a pipe, the pipe ends the check" 1 "LC_ALL=C grep -E x f | cat -a"
snip "a prefix on the wrong command does not cover the next one" 1 "LC_ALL=C cat f | awk 1"
snip "export on its own is not a prefix" 2 "export LC_ALL=C; awk 1 f | sort -u"
n_sites="$(ll_l2_text snippet "LC_ALL=C awk 1 f | LC_ALL=C sort -u
x=\"\$(LC_ALL=C tr a b)\"
echo \"(awk)\"" | LC_ALL=C awk -F '\t' '$1 == "S" { print $2 }')"
[ "$n_sites" = "3" ] || fail "S235 lint — the site count of a 3-site snippet is '$n_sites', expected 3"

# =========================================================================
# 0b. a synthetic good tree is green, and each mutant of it is red
# =========================================================================
SYN="$SANDBOX/syn"
mk_syn() { # root
  local r="$1" f
  mkdir -p "$r/skills/pre-merge-review" "$r/lib"
  for f in $LL_SCRIPTS; do
    mkdir -p "$r/$(dirname "$f")"
    printf '#!/usr/bin/env bash\n# header: mentions export LC_ALL=C in a comment\nset -uo pipefail\nexport LC_ALL=C\nx=1\n' > "$r/$f"
  done
  cat > "$r/lib/markdown.sh" <<'EOF'
#!/usr/bin/env bash
live_text() { printf '%s\n' "$1" | LC_ALL=C awk -v mode=live "$P"; }
strip() { out="$(LC_ALL=C grep -a -E x <<<"$1")" || return 1; }
EOF
  cat > "$r/lib/model-record.sh" <<'EOF'
#!/usr/bin/env bash
norm() {
  printf '%s' "$1" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -E 's/a/b/' \
    | LC_ALL=C cut -c1-3 \
    | LC_ALL=C sort -u \
    | LC_ALL=C uniq
  case "$(printf x | LC_ALL=C tr a b)" in a) echo "see (awk) and grep" ;; esac
}
EOF
}
mk_syn "$SYN"
expect_green "synthetic tree" "$SYN"
syn_sites="$(sites_of "$SYN")"
[ "$syn_sites" = "8" ] || fail "S235 lint — the synthetic tree has 8 sites, the lint counted '$syn_sites'"

mutant_of() { # root-to-copy name file old new: a fresh copy with one literal replaced; sets MUT_ROOT
  local src="$1" name="$2" file="$3" old="$4" new="$5"
  MUT_ROOT="$SANDBOX/mut.$name"
  rm -rf "$MUT_ROOT"
  mkdir -p "$MUT_ROOT/skills/pre-merge-review" "$MUT_ROOT/lib"
  local f
  for f in $LL_SCRIPTS $LL_LIBS; do
    mkdir -p "$MUT_ROOT/$(dirname "$f")"
    cp "$src/$f" "$MUT_ROOT/$f"
  done
  if ! ll_mutate "$MUT_ROOT/$file" "$old" "$new"; then
    fail "S235 L3 — mutant '$name' did not apply: '$old' is not in $file (the mutant is vacuous; update the test)"
    return 1
  fi
}
kill_mutant() { # src name file old new
  mutant_of "$1" "$2" "$3" "$4" "$5" || return 0
  expect_red "$2" "$MUT_ROOT"
}

for f in $LL_SCRIPTS; do
  kill_mutant "$SYN" "syn:no-export:$f" "$f" "${NL}export LC_ALL=C" "${NL}:"
  kill_mutant "$SYN" "syn:non-C-export:$f" "$f" "${NL}export LC_ALL=C" "${NL}export LC_ALL=en_US.UTF-8"
  kill_mutant "$SYN" "syn:export-late:$f" "$f" "${NL}export LC_ALL=C${NL}x=1" "${NL}x=1${NL}export LC_ALL=C"
  kill_mutant "$SYN" "syn:unset:$f" "$f" "x=1" "x=1${NL}unset LC_ALL"
  kill_mutant "$SYN" "syn:later-non-C:$f" "$f" "x=1" "x=1${NL}LC_ALL=de_DE.UTF-8 true"
done
kill_mutant "$SYN" "syn:awk" lib/markdown.sh "LC_ALL=C awk" "awk"
kill_mutant "$SYN" "syn:grep-prefix" lib/markdown.sh "LC_ALL=C grep" "grep"
kill_mutant "$SYN" "syn:grep-a" lib/markdown.sh "grep -a -E" "grep -E"
kill_mutant "$SYN" "syn:tr" lib/model-record.sh "| LC_ALL=C tr '[:upper:]'" "| tr '[:upper:]'"
kill_mutant "$SYN" "syn:sed" lib/model-record.sh "LC_ALL=C sed" "sed"
kill_mutant "$SYN" "syn:cut" lib/model-record.sh "LC_ALL=C cut" "cut"
kill_mutant "$SYN" "syn:sort" lib/model-record.sh "LC_ALL=C sort" "sort"
kill_mutant "$SYN" "syn:uniq" lib/model-record.sh "LC_ALL=C uniq" "uniq"
kill_mutant "$SYN" "syn:tr-in-subst" lib/model-record.sh "| LC_ALL=C tr a b" "| tr a b"

# =========================================================================
# 1. the real tree: L1 and L2
# =========================================================================
v_real="$(violations "$ROOT")"
if [ -n "$v_real" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    fail "S235 L1/L2 — $(printf '%s' "$line" | LC_ALL=C awk -F '\t' '{ print $2 ": " $3 }')"
  done <<<"$v_real"
fi
real_sites="$(sites_of "$ROOT")"
echo "    S235: the lint checked $real_sites external text-command sites in $LL_LIBS" >&2
[ "$real_sites" -gt 0 ] || fail "S235 L2 — the lint checked 0 sites in the libs (a lint that scans nothing is red)"
# the two libs have, together, at least the 11 sites known at head 5ea3a5b
[ "$real_sites" -ge 11 ] || fail "S235 L2 — the lint checked only $real_sites sites; head 5ea3a5b has 11 (a tokenizer regression, or a lib shrank: update this floor on purpose)"

# =========================================================================
# 2. L3 on the REAL tree (needs a green real baseline)
# =========================================================================
if [ -n "$v_real" ]; then
  fail "S235 L3 — the mutants on the real tree were NOT run: the real baseline is red (above). They run, and must each be red, once L1 and L2 are green"
else
  expect_green "real tree copy" "$ROOT"
  for f in $LL_SCRIPTS; do
    kill_mutant "$ROOT" "real:no-export:$f" "$f" "${NL}export LC_ALL=C" "${NL}:"
    kill_mutant "$ROOT" "real:non-C-export:$f" "$f" "${NL}export LC_ALL=C" "${NL}export LC_ALL=en_US.UTF-8"
  done
  # effort_rank's tr (lib/model-record.sh:57, lib-normalize-locale round 2)
  kill_mutant "$ROOT" "real:effort_rank-tr" lib/model-record.sh "\"\$1\" | LC_ALL=C tr '[:upper:]' '[:lower:]')\" in" "\"\$1\" | tr '[:upper:]' '[:lower:]')\" in"
  # normalize_model's first sed (normalize-sed1-untested, round 2)
  kill_mutant "$ROOT" "real:normalize_model-sed1" lib/model-record.sh "LC_ALL=C sed -E 's/^[[:space:]]*claude" "sed -E 's/^[[:space:]]*claude"
  kill_mutant "$ROOT" "real:normalize_model-tr" lib/model-record.sh "LC_ALL=C tr '[:upper:]' '[:lower:]' \\" "tr '[:upper:]' '[:lower:]' \\"
  kill_mutant "$ROOT" "real:markdown-strip-awk" lib/markdown.sh "LC_ALL=C awk -v mode=strip" "awk -v mode=strip"
  kill_mutant "$ROOT" "real:markdown-live-awk" lib/markdown.sh "LC_ALL=C awk -v mode=live" "awk -v mode=live"
  kill_mutant "$ROOT" "real:parser-find-awk" lib/model-record.sh "LC_ALL=C awk -v want=\"\$1\" -v mode=find" "awk -v want=\"\$1\" -v mode=find"
  kill_mutant "$ROOT" "real:parser-scan-awk" lib/model-record.sh "LC_ALL=C awk -v want= -v mode=scan" "awk -v want= -v mode=scan"
fi

test_done

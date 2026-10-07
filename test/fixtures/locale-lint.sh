#!/usr/bin/env bash
# test/fixtures/locale-lint.sh — the static locale lint behind S235 (#423 AC7,
# A32c). Source it; it is not a test case. Test code only: nothing here ships.
#
# The rule it checks (A32c, "Amended rule"):
#   L1  each of the five scripts that read text from GitHub (#426 added the carry-forward gate) has
#       `export LC_ALL=C` as its first statement (after the shebang,
#       comments, blank lines and `set ...` lines), and nowhere else assigns
#       LC_ALL to something other than C or unsets it.
#   L2  in lib/markdown.sh, lib/model-record.sh and lib/review-rounds.sh every command-position
#       awk, grep, sed, tr, cut, sort and uniq carries the per-command prefix
#       `LC_ALL=C `, and grep is always `grep -a`.
#
# Allow-list: a line that carries `# locale-exempt: <reason>` (a NON-EMPTY
# reason) is not a violation. It is still counted as a site (and as an
# exemption), so an exemption can never make the site count zero. An exempt
# marker with no reason is itself a violation. Today the allow-list is empty:
# no site in the two libs needs an exemption. Add one only for a command that
# provably never sees GitHub text (say what, in the reason).
#
# Command position = line start, or after `|`, `$(`, `;`, `&`, `&&`, `||`,
# `(`, a backtick, `then`/`else`/`do`/`!`/`{`, a case-arm `)`, and after
# leading `NAME=value` words (so `LC_ALL=C awk` and `x=1 awk` are both read as
# a command). Quoted text (single, double) is skipped, except that a `$(`
# inside double quotes opens command position again. Known limits (accepted,
# the lint is a tripwire, not a parser): a `${...}` expansion is skipped
# to its first `}`; a grep whose flags continue on the next line after a
# backslash is not checked for `-a`; heredoc bodies are read as code.
#
# Bash 3.2, BWK awk, BSD tools: the one awk program below uses no gawk-only
# feature and runs under LC_ALL=C itself.

# #426 (V5 of #411): the carry-forward gate now reads GitHub text through rr_rounds, and
# lib/review-rounds.sh is the third lib that does
LL_SCRIPTS="skills/pre-merge-review/model-record-gate.sh compliance-evidence.sh role-label-staleness.sh review-rounds.sh skills/pre-merge-review/finding-carryforward-gate.sh"
LL_LIBS="lib/markdown.sh lib/model-record.sh lib/review-rounds.sh"

# ll_l1 <root>: prints one "V<TAB>file<TAB>message" line per L1 violation.
ll_l1() {
  local root="$1" f
  for f in $LL_SCRIPTS; do
    if [ ! -r "$root/$f" ]; then
      printf 'V\t%s\t%s\n' "$f" "missing or unreadable"
      continue
    fi
    LC_ALL=C awk -v name="$f" '
      BEGIN { seen = 0 }
      {
        line = $0
        if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) next
        if (!seen) {
          if (line ~ /^[[:space:]]*set([[:space:]]|$)/) next
          seen = 1
          if (line !~ /^export LC_ALL=C[[:space:]]*(#.*)?$/)
            printf "V\t%s\tfirst statement (line %d) is not `export LC_ALL=C`: %s\n", name, NR, line
          next
        }
        if (line ~ /(^|[^A-Za-z0-9_])unset[[:space:]].*LC_ALL/)
          printf "V\t%s\tline %d unsets LC_ALL: %s\n", name, NR, line
        if (line ~ /export[[:space:]]+-n[[:space:]].*LC_ALL/)
          printf "V\t%s\tline %d un-exports LC_ALL: %s\n", name, NR, line
        rest = line
        while (match(rest, /LC_ALL=/)) {
          after = substr(rest, RSTART + RLENGTH)
          if (after !~ /^C($|[^A-Za-z0-9_])/)
            printf "V\t%s\tline %d assigns LC_ALL to something other than C: %s\n", name, NR, line
          rest = after
        }
      }
      END { if (!seen) printf "V\t%s\tno statement at all\n", name }
    ' "$root/$f"
  done
}

# The L2 tokenizer. Prints "V<TAB>file:line<TAB>message" per violation and a
# final "S<TAB>sites<TAB>exempt" line.
# shellcheck disable=SC2016  # an awk program, not shell
_LL_L2_AWK='
function top() { return stk[sp] }
function push(k) { sp++; stk[sp] = k }
function pop() { if (sp > 0) sp-- }
function watched(w) { return w ~ /^(awk|grep|sed|tr|cut|sort|uniq)$/ }
function keyword(w) { return w ~ /^(if|then|else|elif|do|while|until|!|\{|time|exec|command)$/ }
function flush(   rest) {
  if (w == "") return
  if (cmd) {
    if (w == "LC_ALL=C") { pre = 1 }
    else if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { }
    else if (keyword(w)) { }
    else if (watched(w)) {
      sites++
      if (exempt) { exemptn++ }
      else if (!pre) { printf "V\t%s:%d\t%s without the LC_ALL=C prefix: %s\n", name, NR, w, line }
      else if (w == "grep") {
        rest = substr(line, i)
        sub(/[|;&)].*/, "", rest)
        if (rest !~ /(^|[[:space:]])-[A-Za-z]*a[A-Za-z]*([[:space:]]|$)/ && rest !~ /--text/)
          printf "V\t%s:%d\tgrep without -a: %s\n", name, NR, line
      }
      cmd = 0; pre = 0
    }
    else { cmd = 0; pre = 0 }
  }
  w = ""
}
BEGIN { sp = 1; stk[1] = "c"; cmd = 1; pre = 0; cont = 0; sites = 0; exemptn = 0 }
{
  line = $0; n = length(line); i = 1; w = ""
  exempt = 0
  if (index(line, "# locale-exempt:") > 0) {
    if (line ~ /# locale-exempt:[[:space:]]*[^[:space:]]/) exempt = 1
    else printf "V\t%s:%d\tlocale-exempt marker without a reason: %s\n", name, NR, line
  }
  if (!cont && (top() == "c" || top() == "p")) { cmd = 1; pre = 0 }
  cont = 0
  while (i <= n) {
    ch = substr(line, i, 1); t = top()
    if (t == "s") { if (ch == "\047") pop(); i++; continue }
    if (t == "d") {
      if (ch == "\\") { i += 2; continue }
      if (ch == "\"") { pop(); i++; continue }
      if (ch == "$" && substr(line, i + 1, 1) == "(") { push("p"); cmd = 1; pre = 0; i += 2; continue }
      if (ch == "$" && substr(line, i + 1, 1) == "{") { k = index(substr(line, i), "}"); i += (k > 0 ? k : 2); continue }
      i++; continue
    }
    if (ch == "\\") { if (i == n) cont = 1; else w = w substr(line, i, 2); i += 2; continue }
    if (ch == "#" && w == "") break
    if (ch == "$" && substr(line, i + 1, 1) == "(") { flush(); push("p"); cmd = 1; pre = 0; i += 2; continue }
    if (ch == "$" && substr(line, i + 1, 1) == "{") { k = index(substr(line, i), "}"); w = w "${}"; i += (k > 0 ? k : 2); continue }
    if (ch == "\047") { flush(); push("s"); i++; continue }
    if (ch == "\"") { flush(); push("d"); i++; continue }
    if (ch == " " || ch == "\t") { flush(); i++; continue }
    if (ch == "|" || ch == ";" || ch == "&") { flush(); cmd = 1; pre = 0; i++; continue }
    if (ch == "`") { flush(); cmd = 1; pre = 0; i++; continue }
    if (ch == "(") { flush(); push("p"); cmd = 1; pre = 0; i++; continue }
    if (ch == ")") { flush(); if (top() == "p") { pop(); cmd = 0 } else { cmd = 1; pre = 0 } i++; continue }
    if (ch == "<" || ch == ">") { flush(); i++; continue }
    w = w ch; i++
  }
  flush()
}
END { printf "S\t%d\t%d\n", sites, exemptn }
'

# ll_l2 <root>: for each lib, the violations; then one "S<TAB>file<TAB>sites<TAB>exempt" line per lib.
ll_l2() {
  local root="$1" f out
  for f in $LL_LIBS; do
    if [ ! -r "$root/$f" ]; then
      printf 'V\t%s\t%s\n' "$f" "missing or unreadable"
      continue
    fi
    out="$(LC_ALL=C awk -v name="$f" "$_LL_L2_AWK" "$root/$f")"
    printf '%s\n' "$out" | LC_ALL=C awk -F '\t' -v f="$f" '$1 == "V" { print } $1 == "S" { printf "S\t%s\t%s\t%s\n", f, $2, $3 }'
  done
}

# ll_l2_text <name> <text>: the tokenizer on a snippet (self-test of the lint itself).
ll_l2_text() {
  printf '%s\n' "$2" | LC_ALL=C awk -v name="$1" "$_LL_L2_AWK"
}

# ll_mutate <file> <old> <new>: replace the first literal occurrence of <old>
# by <new> in <file> (no regex, no escapes). Returns 1 when <old> is absent,
# so a mutant that did not apply is never counted as a kill.
ll_mutate() {
  local file="$1" tmp
  tmp="$file.mut.$$"
  if ! OLD="$2" NEW="$3" LC_ALL=C awk '
    BEGIN { RS = "\001"; old = ENVIRON["OLD"]; new = ENVIRON["NEW"]; done = 0 }
    { p = index($0, old)
      if (p > 0) { $0 = substr($0, 1, p - 1) new substr($0, p + length(old)); done = 1 }
      printf "%s", $0 }
    END { exit done ? 0 : 1 }
  ' "$file" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

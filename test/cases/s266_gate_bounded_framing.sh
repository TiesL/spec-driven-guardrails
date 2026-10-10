#!/usr/bin/env bash
# S266 — gate_bounded_framing; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F27, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

RS=$'\036'; NL=$'\n'
# Already-green ingestion/locale controls are regressions; strict chronology
# and CR handling are new behavior. Fixed seven arms, no random oracle.
for source in description comment review issue; do
 for arm in a d; do
  v2_base; r="$(mr Planning)"
  if [ "$arm" = a ]; then r="$RS$r$RS"; else r="<!-- model-record: stage=Planning model=\"m${RS}m\" -->"; fi
  case "$source" in
   description) v2_pr 'Fix #239' "$r";; comment) v2_comments comments-246.json "$r" "$(mr Test)" "$(mr Implementation)";;
   review) v2_comments reviews-246.json "$(mr Review)" "$r";; issue) v2_comments comments-239.json "$(mr Discovery)" "$r";; esac
  v2_run "$v2_yes"; clean
  # Same source path with injected basis.
  r="<!-- model-record: stage=Review model=\"m${RS}m\" floor-basis=\"ade${RS}quate\" -->"
  case "$source" in description) v2_pr 'Fix #239' "$r";; comment) v2_comments comments-246.json "$(mr Planning)" "$(mr Test)" "$(mr Implementation)" "$r";; review) v2_comments reviews-246.json "$r";; issue) v2_comments comments-239.json "$(mr Discovery)" "$r";; esac
  v2_run "$v2_yes"; clean
 done
done
utf="$(locale -a | grep -iE '^(en_US\.UTF-?8|C\.UTF-?8)$' | head -1)"
[ -n "$utf" ] || { fail 'required UTF-8 locale missing'; test_done; }
for loc in C "$utf" unset; do
 for ending in LF CRLF CR; do
  case "$ending" in LF) e=$'\n';; CRLF) e=$'\r\n';; CR) e=$'\r';; esac
  v2_base; v2_comments comments-239.json; v2_comments reviews-246.json
  five="$(mr Discovery)$RS$e$(mr Planning)$RS$e$(mr Test)$RS$e$(mr Implementation)$RS$e$(mr Review)"
  v2_comments comments-246.json "$five"
  if [ "$loc" = unset ]; then unset LC_ALL; export LANG="$utf"; else export LC_ALL="$loc"; fi
  v2_run "$v2_yes"; count 'stages in one text: Discovery, Planning, Test, Implementation, Review' 1; absent 'no record found'; absent 'near-miss'
  v2_comments comments-246.json "$RS$(mr Discovery)$RS$e" "$RS$(mr Planning)$RS$e" "$RS$(mr Test)$RS$e" "$RS$(mr Implementation)$RS$e" "$RS$(mr Review)$RS$e"
  v2_run "$v2_yes"; clean
 done
done
export LC_ALL=C
unc="<!-- model-record: stage=Review model=\"m$RS"
good='<!-- model-record: stage=Review model="m" note=" first value starts with a space" -->'
v2_base; v2_times reviews-246.json "$early" "$unc" "$late" "$good"; v2_run
count 'near-miss' 1; count 'has no floor-basis' 1; absent 'latest stage=Review record is unreadable'; absent 'no record found for stage Review'
v2_times reviews-246.json "$late" "$unc" "$early" "$good"; v2_run
count 'near-miss' 1; has 'latest stage=Review record is unreadable'; absent 'has no floor-basis'; absent 'no record found for stage Review'
v2_base; v2_comments comments-246.json $'```\n'"$RS" "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"; v2_run "$v2_yes"; clean
# Invalid UTF-8 enters jq as escapes which decode into bytes? JSON permits
# Unicode, not arbitrary byte strings: jq replaces malformed input with U+FFFD.
# Exercise literal invalid-byte output at the gh CLI seam for those two arms.
for bytes in $'\377' $'\342\200'; do
 rawbin="$SANDBOX/raw-gh"; mkdir -p "$rawbin"
 cat > "$rawbin/gh" <<EOF
#!/usr/bin/env bash
if [ "\${2:-}" = 'repos/{owner}/{repo}/issues/246/comments' ]; then printf '%s' "\$INVALID_PROSE"; fi
exec "$v2_bin/gh" "\$@"
EOF
 chmod +x "$rawbin/gh"; export INVALID_PROSE="$bytes"$'\n'
 v2_base; v2_path="$rawbin:$v2_bin:$PATH"; v2_run "$v2_yes"; clean
done
unset v2_path
v2_base; v2_comments comments-246.json $'<!-- model-record: stage=Planning model="m\rm" -->' "$(mr Test)" "$(mr Implementation)"; v2_run
has 'no record found for stage Planning'; count 'near-miss' 1

test_done

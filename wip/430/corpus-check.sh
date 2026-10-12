#!/usr/bin/env bash
# wip/430/corpus-check.sh — #430 AC1 adopter corpus check (A36a). Evidence
# tooling on wip/430-acceptance; never merged into the release branch.
#
# Usage: wip/430/corpus-check.sh <guardrails-release-checkout> <work-dir> <owner/repo>...
#
# Runs the shipped rec_scan_bundle from <guardrails-release-checkout>/lib, read
# only, over every issue body, PR body, issue/PR comment and PR review body of
# each repository (GitHub REST via gh). Per repository and record kind
# (model-record, pipeline-override) it prints the counts of ok, near-miss and
# quoted rows, then the inline near-miss rows ("not on a line of its own") as
# URL, stage and reason only, never the line text (private adopters). A
# repository that cannot be fully read is printed as "unverified", never left
# out and never counted as zero.
#
# Writes only under <work-dir>. Read-only on GitHub (gh api GET only).
set -u
[ $# -ge 3 ] || { echo "usage: $0 <guardrails-checkout> <work-dir> <owner/repo>..." >&2; exit 2; }
G="$1"; W="$2"; shift 2
# shellcheck source=/dev/null
. "$G/lib/model-record.sh" || { echo "cannot source $G/lib/model-record.sh" >&2; exit 2; }
mkdir -p "$W"
echo "guardrails: $(git -C "$G" rev-parse HEAD) ($(git -C "$G" rev-parse --abbrev-ref HEAD))"

fetch() { # <repo> <out.jsonl>: one {url, body} object per line; non-zero on any failure
  local r="$1" out="$2" n
  : >"$out"
  gh api --paginate "repos/$r/issues?state=all&per_page=100" \
    --jq '.[]|{url:.html_url,body:(.body//"")}' >>"$out" || return 1
  gh api --paginate "repos/$r/issues/comments?per_page=100" \
    --jq '.[]|{url:.html_url,body:(.body//"")}' >>"$out" || return 1
  for n in $(gh api --paginate "repos/$r/pulls?state=all&per_page=100" --jq '.[].number') ; do
    gh api --paginate "repos/$r/pulls/$n/reviews?per_page=100" \
      --jq '.[]|{url:.html_url,body:(.body//"")}' >>"$out" || return 1
  done
}

for r in "$@"; do
  d="$W/$(tr '/' '_' <<<"$r")"; mkdir -p "$d"
  echo
  echo "## $r"
  if ! fetch "$r" "$d/bodies.jsonl" 2>"$d/fetch.err"; then
    echo "unverified: fetch failed ($(head -1 "$d/fetch.err"))"; continue
  fi
  jq -r '.url' "$d/bodies.jsonl" >"$d/urls"
  bundle="$(jq -j '(.body|gsub("\u001e";"")) + "\u001e"' "$d/bodies.jsonl")"
  echo "bodies: $(wc -l <"$d/urls" | tr -d ' ')"
  for kind in model-record pipeline-override; do
    if ! rows="$(rec_scan_bundle "$kind" "$bundle" 2>"$d/$kind.err")"; then
      echo "$kind: unverified (rec_scan_bundle failed: $(head -1 "$d/$kind.err"))"; continue
    fi
    printf '%s\n' "$rows" >"$d/$kind.rows"
    ok=0; nm=0; qt=0
    [ -n "$rows" ] && {
      ok=$(awk -F'\t' '$2=="ok"' <<<"$rows" | wc -l | tr -d ' ')
      nm=$(awk -F'\t' '$2=="near-miss"' <<<"$rows" | wc -l | tr -d ' ')
      qt=$(awk -F'\t' '$2=="quoted"' <<<"$rows" | wc -l | tr -d ' ')
    }
    echo "$kind: ok=$ok near-miss=$nm quoted=$qt"
    [ -n "$rows" ] || continue
    awk -F'\t' '$2=="near-miss" && index($4,"not on a line of its own")==1 {print $1"\t"$3}' <<<"$rows" |
      while IFS=$'\t' read -r idx stage; do
        echo "  inline: $(sed -n "${idx}p" "$d/urls") stage=$stage"
      done
    awk -F'\t' '$2=="near-miss" {r=$4; sub(/: ".*/,"",r); print r}' <<<"$rows" | sort | uniq -c |
      while read -r c reason; do echo "  near-miss reason: $c × $reason"; done
  done
done

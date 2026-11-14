#!/usr/bin/env bash
# merge-risk-evidence.sh — A60 (+ addenda 1-2) read-only collection/evaluation. Never merges,
# dispatches, posts or repairs. Outputs fixed diagnostics only.
# Bash 3.2-compatible.
set -uo pipefail
usage() { echo 'usage: merge-risk-evidence.sh [--phase prepare|class|final] PR | --prepare PR --out NEW_DIR | --queue' >&2; }
phase=final pr='' destination='' mode=collect
if [ "$#" -eq 1 ] && [ "$1" = --queue ]; then
  mode=collect-queue
elif [ "$#" -eq 4 ] && [ "$1" = --prepare ] && [ "$3" = --out ]; then
  mode=export pr="$2" destination="$4"
elif [ "$#" -eq 3 ] && [ "$1" = --phase ]; then
  phase="$2" pr="$3"
  case "$phase" in prepare | class | final) : ;; *) usage; exit 2 ;; esac
elif [ "$#" -eq 1 ]; then
  pr="$1"
else
  usage; exit 2
fi
if [ "$mode" != collect-queue ]; then
  case "$pr" in '' | *[!0-9]* | 0*) usage; exit 2 ;; esac
fi
unresolved() { printf 'merge-risk: unresolved pr=- head=- base=- diff=- config=-\nreason: %s\n' "$1"; exit 4; }
command -v python3 >/dev/null 2>&1 || unresolved python3-missing
command -v gh >/dev/null 2>&1 || unresolved gh-missing
command -v git >/dev/null 2>&1 || unresolved git-missing
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || unresolved verifier-missing
# Capture before exposing anything to the credentialed consumer. Neither child
# stderr nor an unknown stdout protocol is forwarded.
# The argument list is chosen outside the substitution: Bash 3.2 cannot parse
# a case statement inside $(...).
case "$mode" in
  collect-queue) set -- collect-queue ;;
  export) set -- export "$pr" "$script_dir" "$destination" ;;
  collect) set -- collect --phase "$phase" "$pr" "$script_dir" ;;
esac
output="$(python3 -I "$script_dir/lib/merge-risk.py" "$@" 2>/dev/null)"
rc=$?
case "$rc" in 0 | 1 | 3 | 4) : ;; *) unresolved verifier-crash ;; esac
first="${output%%$'\n'*}"
sha40='[0-9a-f]{40}'
sha256='[0-9a-f]{64}'
number='([1-9][0-9]*|-)'
case "$mode" in
  collect)
    case "$rc" in 0) verdict=eligible ;; 1) verdict=held ;; 3) verdict=referred ;; 4) verdict=unresolved ;; esac
    header="^merge-risk: $verdict pr=$number head=($sha40|-) base=($sha40|-) diff=($sha256|-) config=($sha256|-)\$"
    [[ "$first" =~ $header ]] || unresolved collector-output-invalid
    if [ "$rc" -eq 0 ]; then
      [ "$phase" = final ] || unresolved collector-output-invalid
      strict="^merge-risk: eligible pr=[1-9][0-9]* head=$sha40 base=$sha40 diff=$sha256 config=$sha256\$"
      [[ "$first" =~ $strict ]] || unresolved collector-output-invalid
    fi
    ;;
  export)
    if [ "$rc" -eq 0 ]; then
      header="^merge-risk-export: prepared manifest=$sha256\$"
      [[ "$first" =~ $header ]] || unresolved collector-output-invalid
    else
      header='^merge-risk: unresolved pr=- head=- base=- diff=- config=-$'
      [[ "$first" =~ $header ]] || unresolved collector-output-invalid
    fi
    ;;
  collect-queue)
    case "$rc" in 0) verdict='read' ;; 3) verdict=referred ;; 4) verdict=unresolved ;; *) unresolved collector-output-invalid ;; esac
    header="^merge-risk-queue: $verdict open=[0-9]+\$"
    [[ "$first" =~ $header ]] || unresolved collector-output-invalid
    ;;
esac
seen_first=0
while IFS= read -r line; do
  if [ "$seen_first" -eq 0 ]; then seen_first=1; continue; fi
  case "$line" in
    'reason: '*)
      code="${line#reason: }"
      case "$code" in
        artifact-identity | autonomy-disabled | base-not-main | base-unreadable | behind-base | cap-files | cap-lines | capability-below-author | capability-effort-no-gain | capability-effort-unavailable | capability-entry-missing | capability-exception-invalid | capability-identity-missing | capability-profile-mismatch | capability-table-invalid | changes-requested | classification-unresolved | closing-issues | completion-invalid | config-absent | config-date-unreadable | config-invalid | config-malformed | config-repository | control-closed | control-unreadable | corpus-invalid | diff | duplicate-json-key | evidence-incomplete | evidence-schema | executor-invalid | finding-provenance | gate-check | gate-escape-hatch | gate-preflight | gate-preflight-stream | gate-preflight-warning | gate-quality | gate-review-marker | git-identity | git-unreadable | gitlink | guard-invalid | hard-stop | hold-release-missing | hold-release-stale | hold-release-target | hold-release-words | hold-window | identity-binding | instruction-load-invalid | inventory | issue-unreadable | label-hold | label-off | label-off-control | labels-unreadable | lfs-unavailable | manifest-schema | narrative-invalid | nonfinite-json | now-unreadable | off-since-config | open-findings | path-unsafe | phase-invalid | pr-not-open | pr-unreadable | preparation-only | project-unconfigured | protection-invalid | qualification-unavailable | queue-edited | queue-key-repeated | queue-outcome-unknown | queue-unreadable | raw-identity | read-only | record-duplicate | record-edited | record-id | record-label | record-selection | record-time | records-unreadable | release-head | remote-identity | repository-identity | reserved-authority | reviews-unreadable | risk-attempt-invalid | risk-binding | risk-deadline | risk-expired | risk-independence | risk-pair-required | risk-referral | risk-result-invalid | risk-unavailable | runtime-invalid | self-delegation | timeline-unreadable | tree-collision | unsafe-json-string | verifier-crash | verifier-not-at-base | void-after-announcement | working-kind) : ;;
        *) unresolved collector-output-invalid ;;
      esac
      if [ "$mode" = collect ] && [ "$rc" -eq 0 ]; then unresolved collector-output-invalid; fi
      ;;
    'note: no hold or risk label is dormant, never evidence of safety' | \
    'note: hold release account/hash consistency does not authenticate human authorship' | \
    'note: preparation only; no merge authority' | \
    'note: capability-score-pass' | 'note: capability-maintainer-exception' | \
    'note: capability-correlation same-vendor' | 'note: capability-correlation no-codex' | \
    'note: capability-correlation author-vendor' | 'note: capability-correlation author-model') : ;;
    'note: earliest-merge='*)
      time_line='^note: earliest-merge=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
      [[ "$line" =~ $time_line ]] || unresolved collector-output-invalid
      ;;
    'entry: '*)
      entry_line='^entry: id=MR-[0-9]+-[0-9a-f]{7}-[1-9][0-9]* pr=[1-9][0-9]* head=[0-9a-f]{40} state=(pending|executing|merged|failed) action=(record-completion|evaluate|refer|stop-refer)$'
      [ "$mode" = collect-queue ] && [[ "$line" =~ $entry_line ]] || unresolved collector-output-invalid
      ;;
    *) unresolved collector-output-invalid ;;
  esac
done <<<"$output"
printf '%s\n' "$output"
exit "$rc"

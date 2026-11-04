#!/usr/bin/env bash
# model-record-gate.sh <pr-number> — A31a/A32a/A34a/A37, #427.
#
# REST-only, Bash 3.2. Each fetched body is sanitized before transport framing;
# rec_scan_bundle owns quoting and grammar. One cached scan per record kind.
# Only ok records supply presence. Timestamp-latest candidates (including
# near-misses) decide; no fallback to an older ok. PR description edits are
# not tracked: its timestamp is created_at. Source ties: issue, description,
# comments, reviews; within a body the later candidate line wins.
#
# Findings are stdout, exit 0. In projects answering process-multi-agent-roles
# yes, only `role-played: ` blocks a merge. Every incomplete check emits
# `role-play-unchecked: ` and fails open. A closing-reference HTTP 404 gives
# a note and is ignored, except on an eligible epic release PR (A52), where
# it is `role-play-unchecked: `. The guard shows near-misses as context.
#
# Limits: cannot verify emitter provenance, model identity/capability, agent
# identity, basis honesty, override authorship or work-item attribution.
# A session forging five separate stage comments is not detected. Effort is
# neither chosen nor checked. The merge guard prints the warning; in the
# #430 AC3 run it was seen in the transcript only, not by the agent as
# command output.
set -uo pipefail
export LC_ALL=C
pr_number="${1:?usage: model-record-gate.sh <pr-number>}"
own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(git rev-parse --show-toplevel 2>/dev/null)" || project_root="$(pwd)"
opted_in=0
if [ -r "$own_dir/../../lib/changes.sh" ]; then
  # shellcheck source=../../lib/changes.sh
  . "$own_dir/../../lib/changes.sh"
  answered_yes "$project_root" process-multi-agent-roles && opted_in=1
fi
unchecked() {
  echo "warning: model-record-gate $1; skipping the incomplete check." >&2
  [ "$opted_in" -eq 0 ] || echo "role-play-unchecked: $1"
}
reader_failed() {
  [ "${epic_mode:-0}" -eq 0 ] || exit 1
  echo 'model-record: the record reader failed, so no records were read and dependent checks were skipped'
  unchecked 'record reader failed'
  exit 0
}
if ! command -v gh >/dev/null 2>&1; then
  unchecked "can't find gh"
  exit 0
fi
if [ ! -r "$own_dir/../../lib/model-record.sh" ]; then reader_failed; fi
# shellcheck source=../../lib/model-record.sh
. "$own_dir/../../lib/model-record.sh"

# Dependency-failure acquisition has its own Bash deadline. Ruby supplies
# native child enumeration on macOS, where sandboxed ps/pgrep cannot do it;
# it is used only on this exceptional path, never for healthy recognition.
fallback_detail() {
  local buffer="$1" worker watchdog rc
  command -v ruby >/dev/null 2>&1 || return 1
  set -m
  ruby - "$buffer" "repos/{owner}/{repo}/pulls/$pr_number" "$pr_jq$metadata_jq" <<'RUBY' >"$buffer/worker-out" 2>"$buffer/worker-error" &
require 'fiddle'
require 'set'
# Track descendants even when they create a new session. Freeze parents
# before the final enumeration so termination cannot orphan an unseen child.
if RUBY_PLATFORM.include?('darwin')
  lib = Fiddle.dlopen('/usr/lib/libproc.dylib')
  listing = Fiddle::Function.new(lib['proc_listchildpids'],
    [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
  children = lambda do |pid|
    size = 32
    loop do
      bytes = "\0" * (size * 4)
      count = listing.call(pid, bytes, bytes.bytesize)
      raise 'child enumeration failed' if count < 0
      break bytes.unpack('i*').take(count).reject { |id| id == 0 } if count < size
      size *= 2
    end
  end
else
  children = lambda do |pid|
    Dir.glob("/proc/#{pid}/task/*/children").flat_map do |path|
      begin File.read(path).split.map(&:to_i); rescue Errno::ENOENT; []; end
    end.uniq
  end
end
buffer, endpoint, query = ARGV
owned = Set.new
signal = lambda do |kind, pid|
  begin Process.kill(kind, pid); rescue Errno::ESRCH; end
end
scan = lambda do |freeze|
  pending = [Process.pid] + owned.to_a
  seen = Set.new
  until pending.empty?
    pid = pending.shift
    next unless seen.add?(pid)
    signal.call('STOP', pid) if freeze && pid != Process.pid
    children.call(pid).each do |child|
      owned.add(child)
      pending << child
    end
  end
end
pipes = []
status = nil
begin
  # Prove native enumeration works before starting any external read.
  children.call(Process.pid)
  trap('TERM') { raise 'Bash watchdog expired' }
  out_r, out_w = IO.pipe; err_r, err_w = IO.pipe
  pipes = [out_r, out_w, err_r, err_w]
  pid = Process.spawn('gh', 'api', endpoint, '--jq', query,
                      :out => out_w, :err => err_w)
  owned.add(pid)
  out_w.close; err_w.close
  streams = {out_r => File.open(buffer + '/out', 'wb'),
             err_r => File.open(buffer + '/err', 'wb')}
  counts = Hash.new(0)
  until streams.empty? && status
    scan.call(false)
    ready = streams.empty? ? nil : IO.select(streams.keys, nil, nil, 0.05)
    (ready ? ready[0] : []).each do |io|
      data = io.read_nonblock(65536, :exception => false)
      next if data == :wait_readable
      if data.nil?
        streams.delete(io).close; io.close
      else
        counts[io] += data.bytesize
        raise 'response stream exceeded 8 MiB' if counts[io] > 8 * 1024 * 1024
        streams[io].write(data)
      end
    end
    status ||= Process.waitpid2(pid, Process::WNOHANG)
    sleep 0.05 if streams.empty? && !status
  end
  File.write(buffer + '/status', status[1].exitstatus || 1)
rescue StandardError => error
  File.write(buffer + '/failed', error.message)
ensure
  trap('TERM', 'IGNORE')
  scan.call(true)
  owned.each { |id| signal.call('KILL', id) }
  pipes.each { |io| io.close unless io.closed? }
  begin Process.waitall; rescue Errno::ECHILD; end
end
RUBY
  worker=$!
  ( sleep 10 || { : > "$buffer/failed"; kill -TERM "$worker"; exit 1; }
    : > "$buffer/timed-out"
    kill -TERM "$worker"
    sleep 2
    kill -KILL -- "-$worker" ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$worker" 2>/dev/null
  rc=$?
  kill -KILL -- "-$worker" >/dev/null 2>&1
  kill -TERM -- "-$watchdog" >/dev/null 2>&1
  wait "$watchdog" 2>/dev/null
  set +m
  [ "$rc" -eq 0 ] && [ ! -e "$buffer/timed-out" ] && [ ! -e "$buffer/failed" ] && [ -r "$buffer/status" ]
}

# Whole evaluation is buffered by the private supervisor, including these
# shell scans. The watchdog is independent of the per-REST read deadline.
# The helper returns ordered, attributed rows; the worker only prints them.
if [ "$pr_number" = --epic-worker ]; then
  epic_tmp="$2"; number="$3"; remaining="$4"
  helper="$own_dir/../../lib/model-record-epic.py"
  python3 -I "$helper" collect "$own_dir/model-record-gate.sh" "$number" "$epic_tmp" "$remaining" || exit 1
  python3 -I "$helper" manifest "$epic_tmp" > "$epic_tmp/rows" || exit 1
  first="$(head -n 1 "$epic_tmp/rows")"
  case "$first" in
    'fetch-error|'*)
      suffix="${first#fetch-error|}"
      issue="${suffix#*|}"; suffix="${suffix%%|*}"
      cat "$epic_tmp/fetch-error" >&2
      if [ "$suffix" = issue ]; then
        unchecked "couldn't consult closing issue #$issue"
      else
        unchecked "couldn't consult PR #$number's $suffix"
      fi
      exit 0;;
  esac
  while IFS= read -r row; do
    case "$row" in
      $'out\t'*) printf '%s\n' "${row#out$'\t'}";;
      $'unchecked\t'*) unchecked "${row#unchecked$'\t'}";;
      *) exit 1;;
    esac
  done < "$epic_tmp/rows"
  exit 0
fi
# Batched private modes: bodies framed by the record separator byte (removed
# from bodies by the helper), one framed result per body, in order.
if [ "$pr_number" = --epic-closing ]; then
  closing_keyword_ere='\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#[0-9]+\b'
  while IFS= read -r -d $'\036' input; do
    # No-match is a complete empty set, whereas parser errors are failures.
    matches="$(LC_ALL=C grep -oiE "$closing_keyword_ere" <<<"$input")"
    rc=$?
    [ "$rc" -le 1 ] || exit 1
    if [ -n "$matches" ]; then
      numbers="$(LC_ALL=C grep -oE '[0-9]+' <<<"$matches" | LC_ALL=C sort -un)" || exit 1
      printf '%s' "${numbers//$'\n'/ }"
    fi
    printf '\036'
  done
  exit 0
fi
# Private A52 modes are called only by the bounded traversal worker.
if [ "$pr_number" = --epic-live ]; then
  while IFS= read -r -d $'\036' input; do
    live_text "$input" || exit 1
    printf '\036'
  done
  exit 0
fi
if [ "$pr_number" = --epic-overrides ]; then
  input="$(cat)" || exit 1
  scan="$(rec_scan_bundle pipeline-override "$input")" || exit 1
  while IFS=$'\t' read -r idx cls stage line; do
    [ "$cls" = ok ] || continue
    who="$(rec_field "$line" decided-by)" && reason="$(rec_field "$line" reason)" && scope="$(rec_field "$line" scope)" || exit 1
    case "$who" in *[![:space:]]*) :;; *) continue;; esac
    case "$reason" in *[![:space:]]*) :;; *) continue;; esac
    case "$scope" in single-session|skip=Discovery|skip=Planning|skip=Test|skip=Implementation|skip=Review) printf '%s\n' "$scope";; esac
  done <<<"$scan"
  exit 0
fi
# Transport: time TAB body, with body LF encoded as SOH. Remove injected
# framing bytes BEFORE adding separators. Preserve tabs/CR in values for
# the reader to classify; only the first tab is the metadata delimiter.
body_filter='(.body // "" | gsub("\u001e"; "") | gsub("\u0001"; " ") | gsub("\n"; "\u0001"))'
comments_jq=".[] | (.created_at // \"\") + \"\t\" + $body_filter"
reviews_jq=".[] | (.submitted_at // \"\") + \"\t\" + $body_filter"
pr_jq="((.title // \"\") | gsub(\"[\\u0000-\\u001f]\"; \" \")), ((.created_at // \"\") + \"\\t\" + $body_filter)"
metadata_jq=', ("__EPIC_META__" + ([.head.ref, .head.repo.full_name, .base.ref, .base.repo.full_name, .updated_at, .state, .merged_at, .head.sha, .base.sha] | @json))'
epic_mode=0
if [ "$pr_number" = --epic-evaluate ]; then
  epic_mode=1
  context="$2"
  kind="$(cat "$context/kind")"
  pr="$(cat "$context/detail")"
  comments="$(cat "$context/comments")"
  reviews="$(cat "$context/reviews")"
  issue_numbers=''
  opted_in=1
else
  detail_error="$(mktemp)" || { unchecked 'could not capture PR detail'; exit 0; }
  helper="$own_dir/../../lib/model-record-epic.py"
  helper_available=0
  if [ -r "$helper" ] && command -v python3 >/dev/null 2>&1 && python3 -I -c 'pass' >/dev/null 2>&1; then
    helper_available=1
  fi
  if [ "$helper_available" -eq 0 ]; then
    detail_buffer="$(mktemp -d)" || { rm -f "$detail_error"; unchecked 'could not buffer PR detail'; exit 0; }
    if ! fallback_detail "$detail_buffer"; then
      rm -rf "$detail_buffer"; rm -f "$detail_error"
      unchecked 'initial PR detail incomplete (dependency unavailable, stream cap or timeout)'; exit 0
    fi
    pr="$(cat "$detail_buffer/out")"
    detail_rc="$(cat "$detail_buffer/status")"
    cat "$detail_buffer/err" > "$detail_error"
    rm -rf "$detail_buffer"
  else
    pr="$(gh api "repos/{owner}/{repo}/pulls/$pr_number" --jq "$pr_jq$metadata_jq" 2>"$detail_error")"
    detail_rc=$?
  fi
  metadata="${pr##*$'\n'}"
  case "$metadata" in
    __EPIC_META__*) pr="${pr%$'\n'*}";;
    *) metadata='';;
  esac
  # Old fixtures lack metadata. Only release-shaped heads need the helper.
  if [ "$opted_in" -eq 1 ] && [ "$detail_rc" -eq 0 ] && [[ "$metadata" == '__EPIC_META__["release/'* ]]; then
    helper="$own_dir/../../lib/model-record-epic.py"
    if [ "$helper_available" -eq 0 ]; then
      rm -f "$detail_error"
      unchecked 'epic inheritance helper or Python unavailable'; exit 0
    fi
    epic_tmp="$(mktemp -d)" || { unchecked 'could not buffer epic evaluation'; exit 0; }
    printf '%s' "${metadata#__EPIC_META__}" > "$epic_tmp/metadata"
    printf '%s' "$pr" > "$epic_tmp/detail"
    # Compatibility recognition has no new wall-clock deadline. Only a
    # recognized epic enters the bounded traversal, with these reads cached.
    python3 -I "$helper" recognize "$own_dir/model-record-gate.sh" "$pr_number" "$epic_tmp" > "$epic_tmp/recognition-output" 2> "$epic_tmp/error"
    recognition_rc=$?
    if [ "$recognition_rc" -ne 2 ]; then
      first="$(head -n 1 "$epic_tmp/recognition-output")"
      if [ "$recognition_rc" -ne 0 ]; then
        unchecked 'epic recognition incomplete'
      else
        case "$first" in
          'fetch-error|'*)
            suffix="${first#fetch-error|}"; issue="${suffix#*|}"; suffix="${suffix%%|*}"
            cat "$epic_tmp/fetch-error" >&2
            if [ "$suffix" = issue ]; then unchecked "couldn't consult closing issue #$issue"
            else unchecked "couldn't consult PR #$pr_number's $suffix"; fi;;
          $'unchecked\t'*) unchecked "${first#unchecked$'\t'}";;
          *) cat "$epic_tmp/recognition-output"; cat "$detail_error" >&2;;
        esac
      fi
      rm -rf "$epic_tmp"; rm -f "$detail_error"; exit 0
    fi
    started=$SECONDS
    remaining=$((120 - SECONDS + started))
    set -m
    python3 -I "$helper" supervise "$own_dir/model-record-gate.sh" "$pr_number" "$epic_tmp" "$remaining" > "$epic_tmp/output" 2> "$epic_tmp/error" &
    epic_pid=$!
    ( sleep "$remaining" || { : > "$epic_tmp/watchdog-failed"; kill -TERM "$epic_pid"; exit 1; }
      : > "$epic_tmp/timed-out"
      kill -TERM "$epic_pid"
      sleep 2
      kill -KILL -- "-$epic_pid" ) >/dev/null 2>&1 &
    epic_watchdog=$!
    wait "$epic_pid" 2>/dev/null
    epic_rc=$?
    kill -TERM -- "-$epic_watchdog" >/dev/null 2>&1
    wait "$epic_watchdog" 2>/dev/null
    set +m
    if [ -e "$epic_tmp/watchdog-failed" ] || [ -e "$epic_tmp/timed-out" ]; then epic_rc=1; fi
    rm -f "$detail_error"
    if [ "$epic_rc" -eq 0 ]; then
      cat "$epic_tmp/output"; cat "$epic_tmp/error" >&2
    else
      unchecked 'epic inheritance incomplete (retrieval, reader, cap, snapshot or timeout)'
    fi
    rm -rf "$epic_tmp"
    exit 0
  fi
  comments="$(gh api "repos/{owner}/{repo}/issues/$pr_number/comments" --paginate --jq "$comments_jq")" || { rm -f "$detail_error"; unchecked "couldn't consult PR #$pr_number's comments"; exit 0; }
  reviews="$(gh api "repos/{owner}/{repo}/pulls/$pr_number/reviews" --paginate --jq "$reviews_jq")" || { rm -f "$detail_error"; unchecked "couldn't consult PR #$pr_number's reviews"; exit 0; }
  if [ "$detail_rc" -ne 0 ]; then
    cat "$detail_error" >&2; rm -f "$detail_error"
    unchecked "couldn't consult PR #$pr_number's description"; exit 0
  fi
  cat "$detail_error" >&2
  rm -f "$detail_error"
fi
# A blank title is still a first line (command substitution strips only final LF).
title="${pr%%$'\n'*}"
description="${pr#*$'\n'}"
[ "$description" != "$pr" ] || { unchecked 'unreadable PR description response'; exit 0; }
description_body="${description#*$'\t'}"
closing_keyword_ere='\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#[0-9]+\b'
[ "$epic_mode" -eq 1 ] || issue_numbers="$(LC_ALL=C grep -oiE "$closing_keyword_ere" <<<"$title ${description_body//$'\001'/$'\n'}" | LC_ALL=C grep -oE '[0-9]+' | LC_ALL=C sort -un)"

# Private implementation arrays: raw bodies never participate in a sort key.
# Numeric sequence preserves order within equal-time sources.
tab=$'\t'
seq=0
bodies=()
labels=()
keyed=''
add_bodies() { # rank, source label, time<TAB>encoded-body rows
  local rank="$1" label="$2" row ts body
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    case "$row" in *"$tab"*) :;; *) return 1;; esac
    ts="${row%%"$tab"*}"
    [ -n "$ts" ] || return 1
    body="${row#*"$tab"}"
    seq=$((seq + 1))
    bodies[$seq]="${body//$'\001'/$'\n'}"
    labels[$seq]="$label"
    keyed="$keyed$ts$tab$rank$tab$seq"$'\n'
  done <<<"$3"
}
notes=''
issue_error_file="$(mktemp)" || { unchecked 'could not capture closing-issue status'; exit 0; }
trap 'rm -f "$issue_error_file"' EXIT
if [ "$epic_mode" -eq 1 ]; then
  issue_rows="$(cat "$context/issues")"
  add_bodies 0 'issue comment' "$issue_rows" || exit 1
fi
while IFS= read -r issue; do
  [ -n "$issue" ] || continue
  issue_rows="$(gh api "repos/{owner}/{repo}/issues/$issue/comments" --paginate --jq "$comments_jq" 2>"$issue_error_file")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    # The CLI reports an HTTP status alongside its message. Never classify
    # a transport/authorization/server failure merely from 'Not Found' prose.
    issue_error="$(cat "$issue_error_file")"
    case "$issue_error" in
      *'(HTTP 404)'*) notes="$notes""model-record: closing reference #$issue does not exist and was ignored"$'\n'; continue;;
      *) echo "$issue_error" >&2; unchecked "couldn't consult closing issue #$issue"; exit 0;;
    esac
  fi
  add_bodies 0 'issue comment' "$issue_rows" || { unchecked "unreadable closing issue #$issue response"; exit 0; }
done <<<"$issue_numbers"
if [ "$epic_mode" -eq 1 ] && [ -f "$context/descriptions" ]; then
  add_bodies 1 'PR description' "$(cat "$context/descriptions")" || exit 1
fi
add_bodies 1 'PR description' "$description" && add_bodies 2 'PR comment' "$comments" && add_bodies 3 'PR review' "$reviews" || { unchecked 'unreadable fetched body timestamps'; exit 0; }
ordered="$(LC_ALL=C sort -t "$tab" -k1,1 -k2,2n -k3,3n <<<"$keyed")" || reader_failed
[ -n "$ordered" ] || reader_failed
bundle=''
body_labels=()
body_count=0
while IFS="$tab" read -r _ _ original; do
  [ -n "$original" ] || continue
  body_count=$((body_count + 1))
  bundle="$bundle${bodies[$original]}$MARKER_SEP"
  body_labels[$body_count]="${labels[$original]}"
done <<<"$ordered"
scan="$(rec_scan_bundle model-record "$bundle")" || reader_failed
po_scan=''
if [ "$opted_in" -eq 1 ]; then
  po_scan="$(rec_scan_bundle pipeline-override "$bundle")" || reader_failed
fi

stages=(Discovery Planning Test Implementation Review)
present=(0 0 0 0 0)
latest_class=('' '' '' '' '')
latest_line=('' '' '' '' '')
body_present=()
findings="$notes"
# No record patterns here: classification/stage/fields come only from lib.
stage_index() {
  case "$1" in Discovery) echo 0;; Planning) echo 1;; Test) echo 2;; Implementation) echo 3;; Review) echo 4;; *) return 1;; esac
}
while IFS= read -r row; do
  [ -n "$row" ] || continue
  idx="${row%%"$tab"*}"; rest="${row#*"$tab"}"
  cls="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
  stage="${rest%%"$tab"*}"; line="${rest#*"$tab"}"
  [ "$cls" != quoted ] || continue
  if [ "$epic_mode" -eq 1 ] && [ "$kind" = release ] && [ "${body_labels[$idx]}" = 'issue comment' ]; then continue; fi
  if [ "$cls" = near-miss ]; then
    findings="$findings""model-record: a stage=$stage record is a near-miss ($line)"$'\n'
  fi
  s="$(stage_index "$stage")" || continue
  latest_class[$s]="$cls"
  latest_line[$s]="$line"
  if [ "$cls" = ok ]; then
    present[$s]=1
    body_present[$((idx * 5 + s))]=1
  fi
done <<<"$scan"
# Inheritance contexts (A52) print no "no record found" line: an absent
# stage is named once, by the attributed role-played stages-missing line.
names_absence() {
  [ "$epic_mode" -eq 0 ] || [ "$kind" = legacy ]
}
child_context=0
if [ "$epic_mode" -eq 1 ]; then
  case "$kind" in child|disposition) child_context=1;; esac
fi
for s in 0 1 2 3 4; do
  stage="${stages[$s]}"
  if [ "${present[$s]}" -eq 0 ] && names_absence; then
    findings="$findings""model-record: no record found for stage $stage (missing model-choice marker)"$'\n'
  fi
  if [ "${latest_class[$s]}" = near-miss ]; then
    findings="$findings""model-record: the latest stage=$stage record is unreadable, so no earlier record is used"$'\n'
  fi
done
# Review's own basis is required even without Implementation. Different
# models cannot be ranked by the gate; same-model legacy effort is ignored.
if [ "${latest_class[4]}" = ok ] && [ "$child_context" -eq 0 ]; then
  basis="$(rec_field "${latest_line[4]}" floor-basis)" || reader_failed
  case "$basis" in *[![:space:]]*) :;; *) findings="$findings""model-record: stage=Review marker has no floor-basis (why Review's model clears Implementation's)"$'\n';; esac
fi

waive_all=0
skipped=' '
while IFS= read -r row; do
  [ -n "$row" ] || continue
  idx="${row%%"$tab"*}"
  rest="${row#*"$tab"}"; cls="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; line="${rest#*"$tab"}"
  [ "$cls" != quoted ] || continue
  if [ "$epic_mode" -eq 1 ] && [ "$kind" != release ] && [ "$kind" != legacy ] && [ "${body_labels[$idx]}" != 'issue comment' ]; then continue; fi
  if [ "$cls" = ok ]; then
    who="$(rec_field "$line" decided-by)" && reason="$(rec_field "$line" reason)" && scope="$(rec_field "$line" scope)" || reader_failed
    valid=1
    case "$who" in *[![:space:]]*) :;; *) valid=0;; esac
    case "$reason" in *[![:space:]]*) :;; *) valid=0;; esac
    case "$scope" in single-session|skip=Discovery|skip=Planning|skip=Test|skip=Implementation|skip=Review) :;; *) valid=0;; esac
    if [ "$valid" -eq 1 ]; then
      if [ "$scope" = single-session ]; then waive_all=1; else skipped="$skipped${scope#skip=} "; fi
      continue
    fi
    line="non-blank decided-by and reason, and a valid scope are required: $line"
  fi
  findings="$findings""model-record: a pipeline-override near-miss ($line)"$'\n'
done <<<"$po_scan"
if [ "$epic_mode" -eq 1 ] && [ "$kind" != legacy ]; then
  # Contexts have isolated bodies and overrides. No-PR children require
  # actual issue skips, rather than stage records. Review is release-local.
  kind="$(cat "$context/kind")"
  if [ "$kind" = release ]; then
    for s in 0 1 2 3; do present[$s]=1; done
  else
    present[4]=1
    if [ "$kind" = disposition ]; then
      for s in 0 1 2 3; do present[$s]=0; done
    fi
    # Single-session never supplies a child's missing stage coverage.
    child_single="$waive_all"
    waive_all=0
    skipped="$skipped $(cat "$context/release-skips") "
  fi
fi
printf '%s' "$findings"
[ "$opted_in" -eq 1 ] || exit 0

in_one_text=''
for ((idx=1; idx<=body_count; idx++)); do
  names=''; n=0
  for s in 0 1 2 3 4; do
    [ "${body_present[$((idx * 5 + s))]:-0}" -eq 1 ] || continue
    names="$names${names:+, }${stages[$s]}"; n=$((n + 1))
  done
  if [ "$n" -ge 2 ]; then in_one_text="$in_one_text$names (${body_labels[$idx]})"$'\n'; fi
done
if [ "$child_context" -eq 1 ] && [ "${child_single:-0}" -eq 1 ] && [ -n "$in_one_text" ]; then
  echo 'model-record: a pipeline-override (scope=single-session) waived the role-play findings'
  in_one_text=''
fi
missing=''; waived=''
for s in 0 1 2 3 4; do
  [ "${present[$s]}" -eq 0 ] || continue
  stage="${stages[$s]}"
  case "$skipped" in *" $stage "*) waived="$waived skip=$stage";; *) missing="$missing${missing:+, }$stage";; esac
done
if [ "$waive_all" -eq 1 ]; then
  if [ -n "$in_one_text$missing$waived" ]; then echo 'model-record: a pipeline-override (scope=single-session) waived the role-play findings'; fi
  exit 0
fi
while IFS= read -r text; do
  [ -z "$text" ] || echo "role-played: stages in one text: $text"
done <<<"$in_one_text"
[ -z "$missing" ] || echo "role-played: stages missing: $missing"
[ -z "$waived" ] || [ "$child_context" -eq 1 ] || echo "model-record: a pipeline-override waived stage absence:$waived"
exit 0

#!/usr/bin/env bash
# On-request, advisory backlog snapshot. gh on PATH is the read-only Seam.
# No write mode: REST GETs and GraphQL queries only; no raw server diagnostics.
set -uo pipefail
export LC_ALL=C
own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$own_dir/lib/markdown.sh"
usage() {
  echo 'Usage: backlog-drift.sh [--repo OWNER/REPO] [--project-owner OWNER --project N]'
}
repo='' project_owner='' project=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo|--project-owner|--project)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      case "$1" in --repo) repo="$2";; --project-owner) project_owner="$2";; --project) project="$2";; esac
      shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
if { [ -n "$repo" ] && ! [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; } ||
   { [ -n "$project_owner" ] && ! [[ "$project_owner" =~ ^[A-Za-z0-9_.-]+$ ]]; } ||
   { [ -n "$project" ] && ! [[ "$project" =~ ^[1-9][0-9]*$ ]]; } ||
   { [ -n "$project_owner" ] && [ -z "$project" ]; } ||
   { [ -n "$project" ] && [ -z "$project_owner" ]; }; then usage >&2; exit 2; fi
printf 'Backlog snapshot repo=%s project=%s time=%s\n' "${repo:-current}" "${project_owner:+$project_owner/}${project:-not-applicable}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ -n "$project" ] || echo 'Board checks: not-applicable (no configured board arguments)'
for prerequisite in gh jq; do
  if ! command -v "$prerequisite" >/dev/null 2>&1; then
    printf 'unchecked: %s unavailable; repository/native/project scope unread\nresult=incomplete\n' "$prerequisite"
    exit 0
  fi
done
box="$(mktemp -d)" || exit 1
trap 'rm -rf "$box"' EXIT
: > "$box/unchecked"
printf '[]' > "$box/records"
printf '[]' > "$box/items"
printf '[]' > "$box/fields"
uncheck() { printf 'unchecked: %s\n' "$*" >> "$box/unchecked"; }
# Nonzero exit, invalid JSON, and incomplete page streams never establish absence.
rest() {
  local endpoint="$1" list="$2" rc=0
  if [ "$list" = yes ]; then
    gh api --method GET "$endpoint" --paginate --slurp > "$box/raw" 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ] || ! jq -e 'type=="array" and length>0 and all(.[]; type=="array")' "$box/raw" >/dev/null 2>&1; then
      uncheck "gh REST $endpoint (all pages)"
      # gh may already have emitted complete early pages before a later failure.
      # Retain those objects for known findings, while the unchecked flag forbids clean.
      if jq -se 'length>0 and all(.[]; type=="array" and all(.[]; type=="object"))' "$box/raw" >/dev/null 2>&1; then
        jq -s 'add' "$box/raw"
      else printf 'null'; fi
      return
    fi
    jq 'add // []' "$box/raw"
  else
    gh api --method GET "$endpoint" > "$box/raw" 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ] || ! jq -e 'type=="object" or type=="null"' "$box/raw" >/dev/null 2>&1; then
      uncheck "gh REST $endpoint"; printf '{"_unchecked":true}'; return
    fi
    cat "$box/raw"
  fi
}
if [ -z "$repo" ]; then
  repo_data="$(rest 'repos/{owner}/{repo}' no)"
  repo="$(printf '%s' "$repo_data" | jq -r '.full_name // empty')"
  if ! [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    uncheck 'gh repository identity'; cat "$box/unchecked"; echo 'result=incomplete'; exit 0
  fi
  printf 'Resolved repository: %s\n' "$repo"
fi
prefix="repos/$repo/issues"
issues="$(rest "$prefix?state=all&per_page=100" yes)"
if ! printf '%s' "$issues" | jq -e 'type=="array" and all(.[]; type=="object" and (.number|type=="number"))' >/dev/null; then
  uncheck "$prefix issues inventory"; issues='[]'
fi
# Read current objects rather than relying on possibly stale list bodies.
for n in $(printf '%s' "$issues" | jq -r '.[] | select(.pull_request==null) | .number' | sort -nu); do
  issue="$(rest "$prefix/$n" no)"
  if ! printf '%s' "$issue" | jq -e --argjson n "$n" '
    type=="object" and .number==$n and (.id|type=="number") and
    (.node_id|type=="string") and (.html_url|type=="string") and
    (.body|type=="string") and (.state=="open" or .state=="closed") and
    (.labels|type=="array" and all(.[]; (.name|type=="string")))' >/dev/null; then
    uncheck "$prefix/$n issue fields/body/labels"; continue
  fi
  body="$(printf '%s' "$issue" | jq -r '.body')"
  # Keep lib/markdown's fence/span/quote semantics; also exclude indented code.
  live="$(live_text "$body" | awk '/^(    |\t)/ {print ""; next} {print}')" || { uncheck "$prefix/$n live body"; live=''; }
  comments="$(rest "$prefix/$n/comments?per_page=100" yes)"
  printf '[]' > "$box/notes"
  if printf '%s' "$comments" | jq -e 'type=="array" and all(.[]; (.body|type=="string") and (.html_url|type=="string"))' >/dev/null; then
    printf '%s' "$comments" | jq -c '.[]' > "$box/comments"
    while IFS= read -r comment; do
      cbody="$(printf '%s' "$comment" | jq -r '.body')"
      clive="$(live_text "$cbody" | awk '/^(    |\t)/ {print ""; next} {print}')" || { uncheck "$prefix/$n live comment"; clive=''; }
      jq --arg text "$clive" '. + [$text]' "$box/notes" > "$box/next" && mv "$box/next" "$box/notes" || exit 1
    done < "$box/comments"
  else uncheck "$prefix/$n comments"; fi
  # A successful explicit null response (e.g. supported 204) means no parent.
  # An ambiguous 404/unsupported relation is recorded by rest(), never absence.
  parent="$(rest "$prefix/$n/parent" no)"
  if ! printf '%s' "$parent" | jq -e '.==null or (type=="object" and (.number|type=="number"))' >/dev/null; then
    uncheck "$prefix/$n parent object"; parent='{"_unchecked":true}'
  fi
  for relation in sub_issues dependencies/blocked_by dependencies/blocking; do
    value="$(rest "$prefix/$n/$relation?per_page=100" yes)"
    if ! printf '%s' "$value" | jq -e 'type=="array" and all(.[]; type=="object" and (.number|type=="number"))' >/dev/null; then
      uncheck "$prefix/$n/$relation objects"; value=null
    fi
    case "$relation" in sub_issues) children="$value";; dependencies/blocked_by) blocked_by="$value";; dependencies/blocking) blocking="$value";; esac
  done
  jq --argjson issue "$issue" --arg live "$live" --slurpfile notes "$box/notes" \
     --argjson parent "$parent" --argjson children "$children" --argjson blocked_by "$blocked_by" --argjson blocking "$blocking" \
     '. + [{issue:$issue, live:$live, notes:([$live]+$notes[0]), parent:$parent, children:$children, blocked_by:$blocked_by, blocking:$blocking}]' \
     "$box/records" > "$box/next" && mv "$box/next" "$box/records" || exit 1
done
# GraphQL connection traversal validates every terminal page and each cursor.
graphql() {
  gh api graphql -f "query=$1" > "$box/graphql" 2>/dev/null || { uncheck "gh project $project_owner/$project $2"; printf 'null'; return; }
  if ! jq -e 'type=="object" and (.errors==null or .errors==[]) and (.data|type=="object")' "$box/graphql" >/dev/null 2>&1; then
    uncheck "project $project_owner/$project $2 GraphQL response/errors"; printf 'null'; return
  fi
  cat "$box/graphql"
}
# Values and field declarations must carry their types, field IDs and names.
field_selection='__typename ... on ProjectV2Field { id name dataType } ... on ProjectV2SingleSelectField { id name dataType options { id name } } ... on ProjectV2IterationField { id name dataType }'
value_selection='__typename ... on ProjectV2ItemFieldNumberValue { number field { ... on ProjectV2FieldCommon { id name } } } ... on ProjectV2ItemFieldSingleSelectValue { name optionId field { ... on ProjectV2FieldCommon { id name } } }'
connection_page() {
  local connection="$1" cursor='' seen='|' after='' envelope query response page next has_next nodes
  printf '[]' > "$box/connection"
  while :; do
    after=''
    [ -z "$cursor" ] || after=", after: $(jq -Rn --arg c "$cursor" '$c')"
    if [ "$connection" = fieldValues ]; then
      envelope="node(id: $(jq -Rn --arg id "$2" '$id')) { ... on ProjectV2Item { fieldValues(first: 100$after) { nodes { $value_selection } pageInfo { hasNextPage endCursor } } } }"
    else
      if [ "$connection" = fields ]; then nodes="$field_selection"; else
        nodes="id type isArchived content { __typename ... on Issue { number url state repository { nameWithOwner } } } fieldValues(first: 100) { nodes { $value_selection } pageInfo { hasNextPage endCursor } }"
      fi
      envelope="repositoryOwner(login: $(jq -Rn --arg o "$project_owner" '$o')) { ... on Organization { projectV2(number: $project) { id $connection(first: 100$after) { nodes { $nodes } pageInfo { hasNextPage endCursor } } } } ... on User { projectV2(number: $project) { id $connection(first: 100$after) { nodes { $nodes } pageInfo { hasNextPage endCursor } } } } }"
    fi
    query="query { $envelope }"
    response="$(graphql "$query" "$connection ${2:-}")"
    if [ "$connection" = fieldValues ]; then
      page="$(printf '%s' "$response" | jq '.data.node.fieldValues // null')"
    else
      page="$(printf '%s' "$response" | jq --arg c "$connection" '[.. | objects | .projectV2? // empty | .[$c] // empty][0] // null')"
    fi
    if ! printf '%s' "$page" | jq -e 'type=="object" and (.nodes|type=="array") and (.pageInfo|type=="object" and (.hasNextPage|type=="boolean") and (has("endCursor")))' >/dev/null; then
      uncheck "project $project_owner/$project $connection ${2:-} pageInfo/nodes"; break
    fi
    if ! printf '%s' "$page" | jq -e 'all(.nodes[]; type=="object")' >/dev/null 2>&1; then
      uncheck "project $project_owner/$project $connection malformed nodes"
    fi
    jq --argjson p "$page" '. + [$p.nodes[]|select(type=="object")]' "$box/connection" > "$box/next" && mv "$box/next" "$box/connection" || exit 1
    has_next="$(printf '%s' "$page" | jq -r '.pageInfo.hasNextPage')"
    [ "$has_next" = true ] || break
    next="$(printf '%s' "$page" | jq -r '.pageInfo.endCursor | select(type=="string" and length>0)')"
    if [ -z "$next" ]; then uncheck "project $project_owner/$project $connection missing cursor"; break; fi
    case "$seen" in *"|$next|"*) uncheck "project $project_owner/$project $connection cursor cycle"; break;; esac
    seen="$seen$next|"; cursor="$next"
  done
}
if [ -n "$project" ]; then
  connection_page fields
  cp "$box/connection" "$box/fields"
  connection_page items
  cp "$box/connection" "$box/item-pages"
  jq -c '.[]' "$box/item-pages" > "$box/item-lines"
  while IFS= read -r item; do
    if ! printf '%s' "$item" | jq -e '(.id|type=="string") and (.content==null or (.content|type=="object" and (.__typename|type=="string")))' >/dev/null; then
      uncheck 'project items identity/content'; continue
    fi
    # Pull requests and other-repository items are outside this report's scope.
    if ! printf '%s' "$item" | jq -e --arg r "$repo" '.content.__typename=="Issue" and .content.repository.nameWithOwner==$r' >/dev/null; then continue; fi
    if ! printf '%s' "$item" | jq -e '(.content.number|type=="number") and (.content.url|type=="string") and (.content.state=="OPEN" or .content.state=="CLOSED")' >/dev/null; then
      uncheck 'project issue content fields'; continue
    fi
    item_id="$(printf '%s' "$item" | jq -r '.id')"
    connection_page fieldValues "$item_id"
    jq --argjson item "$item" --slurpfile values "$box/connection" '. + [$item | .fieldValues=$values[0]]' "$box/items" > "$box/next" && mv "$box/next" "$box/items" || exit 1
  done < "$box/item-lines"
fi
cat > "$box/compare.jq" <<'JQ'
def incomplete($s): {kind:"incomplete", text:("unchecked: "+$s)};
def finding($url;$field;$actual;$expected):
  {kind:"drift",text:($url+" "+$field+" observed="+($actual|tojson)+" expected="+($expected|tojson))};
def refs: [scan("#([1-9][0-9]*)") | .[0]|tonumber] | unique | sort;
def declaration($text;$name;$required):
  [$text|split("\n")[]|select(test("^\\*\\*"+$name+":\\*\\*"))] as $lines |
  if ($lines|length)==0 and ($required|not) then {ok:true, values:[]}
  elif ($lines|length)!=1 then {ok:false, values:[]}
  else ($lines[0]|sub("^\\*\\*"+$name+":\\*\\*\\s*";"")|gsub("^\\s+|\\s+$";"")) as $s |
    if $s=="none" then {ok:true,values:[]}
    elif ($s|test("^#[1-9][0-9]*(\\s*,?\\s+#[1-9][0-9]*|,\\s*#[1-9][0-9]*)*$"))
    then {ok:true,values:($s|refs)} else {ok:false,values:[]} end
  end;
def bodies:
  . as $r | (.issue.labels|map(.name)|index("epic")!=null) as $epic |
  . + {decl: {
    parent:declaration(.live;"Epic";($epic|not)),
    blocked_by:declaration(.live;"Blocked by";true),
    blocking:declaration(.live;"Blocks";true),
    children: {ok: (if $epic then (.live|test("(?m)^## Work items\\s*$")) else true end),
      values:(if $epic then
        (.live|split("\n")|reduce .[] as $line ({inside:false, lines:[]};
          if $line|test("^## Work items\\s*$") then .inside=true
          elif $line|test("^## ") then .inside=false
          elif .inside then .lines += [$line] else . end)|.lines|join("\n")|refs)
        else [] end)}
  }};
def coverage:
  [.live|split("\n")[]|select(startswith("**Covers:**"))] as $lines |
  ($lines|length)==1 and ($lines[0]|test("^\\*\\*Covers:\\*\\*\\s*[A-Z]{1,2}[0-9]+[a-z]?(\\s*,\\s*[A-Z]{1,2}[0-9]+[a-z]?)*\\s*$"));
def native($x): if $x==null then null else [$x[].number]|unique|sort end;
def notes($field): [.notes[]|split("\n")[]|select(startswith("|"))|split("|")|.[1:-1]|map(gsub("^\\s+|\\s+$";""))|
  select(length==5 and .[0]==$field and .[1]!="" and .[2]!="" and (.[3]=="awaiting-maintainer" or .[3]=="parked") and (.[4]|test("^https://")))] | unique;
def fieldvalue($item;$name): [$item.fieldValues[] | select(.field.name==$name)] | if length==1 then .[0].number // .[0].name else null end;
def lifecycle:
  (.issue.labels|map(.name)) as $l |
  if .issue.state=="closed" then "Done"
  elif ($l|index("role:reviewer"))!=null then "In review"
  elif ($l|index("status:backlog"))!=null then "Backlog"
  elif ($l|index("status:in-progress"))!=null or any($l[]; test("^role:(product|architect|qa|dev)$")) then "In progress"
  else null end;
($records[0]|map(bodies)) as $rs | ($items[0]) as $is | ($fields[0]) as $fs |
[
  (if $board then
    ["Backlog rank","Horizon","Status"][] as $name |
    ([$fs[]|select(.name==$name)]) as $matched |
    if ($matched|length)!=1 then incomplete("project required field "+$name)
    elif ($matched[0].id|type)!="string" or
      ($name=="Backlog rank" and $matched[0].dataType!="NUMBER") or
      ($name!="Backlog rank" and ($matched[0].dataType!="SINGLE_SELECT" or ($matched[0].options|type)!="array"))
    then incomplete("project field type/options "+$name) else empty end
  else empty end),
  (if $board then $is[] as $item |
    if ([$rs[].issue.number]|index($item.content.number))==null then
      incomplete($item.content.url+" project item has no verified repository issue object") else empty end
  else empty end),
  ($rs[] as $r | $r.issue.html_url as $url | $r.issue.number as $n |
    (if ($r|coverage|not) then incomplete($url+" Covers missing/duplicate/malformed") else empty end),
    (["parent","blocked_by","blocking","children"][] as $edge |
      $r.decl[$edge] as $d |
      (if $edge=="parent" then (if $r.parent._unchecked==true then null elif $r.parent==null then [] else [$r.parent.number] end)
       else native($r[$edge]) end) as $actual |
      if ($d.ok|not) or ($edge=="parent" and (($d.values|length)>1 or (($d.values|length)==0 and ($r.issue.labels|map(.name)|index("epic"))==null))) then incomplete($url+" body "+({parent:"Epic",blocked_by:"Blocked by",blocking:"Blocks",children:"Work items"}[$edge])+" missing/duplicate/malformed")
      elif $actual!=null and $actual!=$d.values then finding($url;("native "+$edge);$actual;$d.values) else empty end),
    ($r.decl as $d |
      if $d.parent.ok then $d.parent.values[] as $p |
        ([$rs[]|select(.issue.number==$p)][0]) as $parent |
        if $parent==null then incomplete($url+" referenced parent #"+($p|tostring)+" unread")
        elif $parent.decl.children.ok and ($parent.decl.children.values|index($n))==null then finding($url;"parent reciprocal child list";$parent.decl.children.values;[$n]) else empty end else empty end),
    ([{from:"blocked_by",to:"blocking"},{from:"blocking",to:"blocked_by"},{from:"children",to:"parent"}][] as $pair |
      if $r.decl[$pair.from].ok then $r.decl[$pair.from].values[] as $target |
        ([$rs[]|select(.issue.number==$target)][0]) as $other |
        if $other==null then incomplete($url+" referenced "+$pair.from+" #"+($target|tostring)+" unread")
        elif $other.decl[$pair.to].ok and ($other.decl[$pair.to].values|index($n))==null then finding($url;("body reciprocal "+$pair.from+" #"+($target|tostring));$other.decl[$pair.to].values;[$n]) else empty end else empty end),
    ($r.issue.labels|map(.name)) as $labels |
    (if (["bug","documentation","enhancement","process"]|map(. as $t|$labels|index($t))|map(select(.!=null))|length)!=1 then finding($url;"type labels";$labels;"one existing type") else empty end),
    (if $r.issue.state=="closed" and any($labels[];test("^(status:|role:)")) then finding($url;"closed status/role labels";$labels;"no active status/role labels") else empty end),
    (if $r.issue.state=="open" and ([$labels[]|select(startswith("status:"))]|length)!=1 then finding($url;"status labels";$labels;"one existing lifecycle status") else empty end),
    (if ([$labels[]|select(startswith("role:"))]|length)>1 or any($labels[];test("^role:") and (test("^role:(product|architect|qa|dev|reviewer)$")|not)) then incomplete($url+" ambiguous/unrecognized active role label") else empty end),
    (if $board then
      ([$is[]|select(.content.number==$n)]) as $matches |
      if ($matches|length)==0 then finding($url;"membership";"missing";"project item")
      elif ($matches|length)>1 then incomplete($url+" duplicate project membership")
      else $matches[0] as $item |
        ($item.fieldValues[] as $v |
          if ($v.field.id|type)!="string" or ($v.field.name|type)!="string" then incomplete($url+" project fieldValues identity")
          elif ($v.field.name=="Backlog rank" and ($v.__typename!="ProjectV2ItemFieldNumberValue" or ($v.number|type)!="number")) or
            (($v.field.name=="Status" or $v.field.name=="Horizon") and ($v.__typename!="ProjectV2ItemFieldSingleSelectValue" or ($v.name|type)!="string" or ($v.optionId|type)!="string")) then incomplete($url+" project fieldValues type/value "+$v.field.name)
          else empty end),
        (["Backlog rank","Horizon","Status"][] as $name |
          if ([$item.fieldValues[]|select(.field.name==$name)]|length)>1 then incomplete($url+" duplicate project fieldValues "+$name) else empty end),
        (if ($r|lifecycle)!=null and
          ([$fs[]|select(.name=="Status")|.options[]?.name]|index($r|lifecycle))==null then incomplete($url+" project Status mapping/option unavailable") else empty end),
        (if ($r|lifecycle)!=null and fieldvalue($item;"Status")!=($r|lifecycle) then finding($url;"Status";fieldvalue($item;"Status");($r|lifecycle)) else empty end),
        (["Backlog rank","Horizon"][] as $name | if fieldvalue($item;$name)==null then
          ($r|notes($name)) as $notes |
          if ($notes|length)==1 then {kind:"exception",text:($url+" "+$name+" exception "+($notes[0]|join(" | ")))}
          elif ($notes|length)>1 then incomplete($url+" contradictory unresolved "+$name+" notes")
          else finding($url;$name;null;"value or field-specific durable awaiting-maintainer/parked decision") end
        else empty end)
      end else empty end)
  )
] | sort_by(.text) | .[] | [.kind,.text] | @tsv
JQ
jq -r --slurpfile records "$box/records" --slurpfile items "$box/items" --slurpfile fields "$box/fields" \
  --argjson board "$([ -n "$project" ] && echo true || echo false)" -n -f "$box/compare.jq" > "$box/findings" || exit 1
cat "$box/unchecked"
cut -f2- "$box/findings"
printf 'Counts: issues=%s project-items=%s\n' "$(jq length "$box/records")" "$(jq length "$box/items")"
if [ -s "$box/unchecked" ] || awk -F '\t' '$1=="incomplete" {found=1} END {exit !found}' "$box/findings"; then echo 'result=incomplete'
elif awk -F '\t' '$1=="drift" {found=1} END {exit !found}' "$box/findings"; then echo 'result=drift'
else echo 'result=clean'; fi

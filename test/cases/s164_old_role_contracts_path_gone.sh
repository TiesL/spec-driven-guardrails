#!/usr/bin/env bash
# S164 — No live reference to role-contracts' old wip/ location remains in this repo.
# Covers: F37
#
# Issue #369, AC9 (the reference half; "./check passes" is what S5, S39,
# S40, S92, S93, S112, S121 and S124 already assert). Seam: the repo's own
# files as a reader follows them: a path to role-contracts must lead to a
# file that exists. Historical records (CHANGELOG.md, CHANGES-ARCHIEF.md)
# may keep the old path; everything else may not.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Built in two parts so this file never contains the string it searches for.
old_dir="wip/multi-agent-development"
old_path="$old_dir/role-contracts"

# Then: no file outside the historical records names the old path.
(cd "$repo" && grep -rnF "$old_path" . \
  --exclude=CHANGELOG.md --exclude=CHANGES-ARCHIEF.md) > "$SANDBOX/old-path.txt"
if [ -s "$SANDBOX/old-path.txt" ]; then
  fail "S164 — the old role-contracts location is still referenced:"
  cat "$SANDBOX/old-path.txt" >&2
fi

# And: every relative path to role-contracts/SKILL.md (../...) resolves
# from the file that contains it.
(cd "$repo" && grep -rnoE '(\.\./)+([A-Za-z0-9_.-]+/)*role-contracts/SKILL\.md' . \
  --exclude=CHANGELOG.md --exclude=CHANGES-ARCHIEF.md) > "$SANDBOX/relative.txt"
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"
  rel="${hit##*:}"
  dir="$(dirname "$repo/${file#./}")"
  if [ ! -e "$dir/$rel" ]; then
    fail "S164 — ${file#./} links to '$rel', which does not exist from there"
  fi
done < "$SANDBOX/relative.txt"

# And: the skill exists where every live reference now points.
[ -f "$repo/skills/role-contracts/SKILL.md" ] \
  || fail "S164 — skills/role-contracts/SKILL.md does not exist"

test_done

#!/usr/bin/env bash
# S48 — The CI template validates pull requests and `main`.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# The `on:` block: everything between `on:` and the next key at column 0,
# without comments. That last part is not a detail: without that filtering, a
# commented-out trigger would simply make the check below pass — the word is
# after all still in the block. Exactly the regression this scenario must
# catch, for instance if someone temporarily disables a trigger.
on_blok() {
  awk '/^on:/ { in_blok = 1; next } /^[a-zA-Z]/ { in_blok = 0 } in_blok' "$1" \
    | grep -v '^[[:space:]]*#'
}

# Is this a real key in the block, i.e. a line that, after indentation, is exactly
# `<name>:` or `<name>: <value>`?
heeft_sleutel() {
  printf '%s\n' "$2" | grep -qE "^[[:space:]]*$1:([[:space:]]|\$)"
}

# The workflow of this repo itself should meet the same requirement as the
# template — a rule you impose on others but dodge yourself is not a rule.
for file in templates/ci.yml .github/workflows/ci.yml; do
  pad="$TEST_REPO_ROOT/$file"

  if [ ! -f "$pad" ]; then
    fail "S48 — $file is missing"
    continue
  fi

  blok="$(on_blok "$pad")"

  # Then: pull requests are validated. That is not the same as a push on the
  # branch: `pull_request` judges the merged result, and that is exactly the
  # case that two individually-green branches can break together.
  heeft_sleutel pull_request "$blok" \
    || fail "S48 — $file has no pull_request trigger"

  # And: pushes to main are validated. `branches-ignore` is filtered out first,
  # otherwise the very line that excludes main would make the check pass —
  # after all it also contains the word `main`.
  positief="$(printf '%s\n' "$blok" | grep -v 'branches-ignore')"
  heeft_sleutel push "$positief" \
    || fail "S48 — $file has no push trigger"
  case "$positief" in
    *main*) ;;
    *) fail "S48 — $file does not mention main in its triggers" ;;
  esac

  # And: not via branches-ignore. That form excludes main — the bug this
  # scenario must catch.
  case "$blok" in
    *branches-ignore*) fail "S48 — $file uses branches-ignore and thus skips main" ;;
  esac

  # And: the CI convention itself does not change. The workflow exclusively
  # invokes `check`; separate lint, test, or build steps belong in the script.
  while IFS= read -r line; do
    case "$line" in
      *check*|*"npm ci"*) ;;
      *) fail "S48 — $file runs its own step instead of only check: $line" ;;
    esac
  done < <(grep -E '^\s+- run:' "$pad")
done

test_done

#!/usr/bin/env bash
# test/ci-workflow-lib.sh — Reads job and step blocks out of a CI workflow
# file without a YAML parser (#422). Source, don't execute.
#
# The workflow under test is $CI_YML_UNDER_TEST when set (the mutation
# proofs point it at a scratch candidate), else this repo's own ci.yml.
# Comment lines are dropped first, so a comment can never satisfy or hide
# an assertion. POSIX awk only (these tests run on BWK, mawk and gawk).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

ci_yml_path() {
  printf '%s\n' "${CI_YML_UNDER_TEST:-$TEST_REPO_ROOT/.github/workflows/ci.yml}"
}

# The job block whose runs-on is $1 (default macos-latest), comments removed.
ci_job_block() {
  local runner="${1:-macos-latest}"
  grep -v '^[[:space:]]*#' "$(ci_yml_path)" | awk -v runner="$runner" '
    function flush() { if (buf ~ ("\n    runs-on:[ \t]*" runner "[ \t]*(\n|$)")) printf "%s", buf; buf = "" }
    /^[A-Za-z]/ { flush(); next }
    /^  [A-Za-z0-9_-]+:[ \t]*$/ { flush() }
    { buf = buf $0 "\n" }
    END { flush() }'
}

# Number of job blocks whose runs-on is $1.
ci_job_count() {
  grep -c "^    runs-on:[[:space:]]*$1[[:space:]]*$" "$(ci_yml_path)"
}

# Steps of a job block on stdin: prints "<n><TAB><text>" per step with
# newlines in the text replaced by U+0001-free "\n" markers is overkill;
# instead steps are selected by index with ci_step_text.
ci_step_text() {
  awk -v want="$1" '
    /^      - / { n++ }
    n == want { print }'
}

ci_step_count() {
  grep -c '^      - '
}

# 1-based index of the first step whose text matches ERE $1 (case-
# insensitive); with a second argument "name", only the step's name: line
# is matched. Prints nothing when there is none.
ci_step_find() {
  awk -v pat="$1" -v mode="${2:-all}" '
    function check() {
      if (n > 0 && !done && match(tolower(text), pat)) { print n; done = 1 }
    }
    /^      - / { check(); n++; text = ""; nameline = "" }
    {
      if (mode == "name") { if ($0 ~ /^ +(- )?name:/ && nameline == "") { nameline = $0; text = $0 } }
      else text = text "\n" $0
    }
    END { check() }'
}

# The shell script of a step on stdin (its run: value), dedented.
ci_step_script() {
  awk '
    !inrun && /^ *(- )?run:/ {
      k = index($0, "run:"); base = k - 1
      rest = substr($0, k + 4); sub(/^[ \t]+/, "", rest)
      if (rest ~ /^[|>][-+]?[ \t]*$/) { inrun = 1; next }
      print rest; exit
    }
    inrun {
      if ($0 ~ /^[ \t]*$/) { print ""; next }
      match($0, /^ */)
      if (RLENGTH <= base) exit
      if (strip == 0) strip = RLENGTH
      print substr($0, strip + 1)
    }'
}

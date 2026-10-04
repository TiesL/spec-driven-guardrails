#!/usr/bin/env bash
# S208 — the README says the release-branch tier IS adoptable (asked, and
# the skill installed), and model-choice says the recorded effort is
# self-reported.
# Covers: F37, F39
#
# Issue #369 (holistic review of the release): B4, README.md said "the
# release-branch tier is not [adoptable]" and listed it under what an adopted
# project does NOT get, while `pending-changes.sh` asks the
# `release-branch-workflow` question and `adopt.sh` symlinks the skill, and a
# later README paragraph says "every adopted project too ... unlike the
# five-role pipeline above". Effort honesty: the effort in a `model-record`
# marker is whatever the role or orchestrator says; the dispatch tool has no
# effort setting, so unless the platform set it, the value is self-reported and
# unverified. Seam: the text of README.md and model-choice, plus the registry
# facts the README must agree with (adopt.sh into a fresh project).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

readme="$TEST_REPO_ROOT/README.md"
mc="$TEST_REPO_ROOT/skills/model-choice/SKILL.md"
[ -f "$readme" ] && [ -f "$mc" ] || { fail "S208 — README.md or model-choice is missing"; test_done; }
flat="$(tr '\n' ' ' < "$readme")"

# --- the facts the README must agree with (green controls) -------------------
sandbox_create
trap sandbox_destroy EXIT
clone="$(sandbox_copy_repo clone)"
project="$(fresh_project adopter)"
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >/dev/null 2>&1
[ -e "$project/.claude/skills/release-branch-workflow" ] || fail "S208 control — adopt.sh no longer installs the release-branch-workflow skill"
pending="$(cd "$project" && "$clone/pending-changes.sh" "$project" 2>&1)"
grep -q 'release-branch-workflow' <<<"$pending" || fail "S208 control — pending-changes.sh no longer asks the release-branch-workflow question"

# --- B4: no statement that the tier is not adoptable ------------------------------
if grep -qiE 'release-branch tier[^.]{0,20}(is|are) not|release-branch tier is not\.' <<<"$flat"; then
  fail "S208/B4 — README.md still says the release-branch tier is not adoptable: $(grep -oiE '.{40}release-branch tier[^.]{0,20}(is|are) not.{0,40}' <<<"$flat" | head -1)"
fi
if grep -qiE 'does \*\*not\*\* get.{0,250}release-branch tier' <<<"$flat"; then
  fail "S208/B4 — README.md still lists the release-branch tier under what an adopted project does NOT get"
fi
if grep -qiE 'unlike the five-role pipeline' <<<"$flat"; then
  fail "S208/B4 — README.md still contrasts the release-branch tier with the five-role pipeline as 'unlike' (both are asked about and installed for adopters)"
fi
# the true statement: adopters are asked (WORKFLOW-ADOPTION.md answer) and get the skill
para_has_all "$readme" 'release-branch-workflow' '(adopted|adopt)' '(asked|question|answer|opt-in|opt in)' '(skill)' \
  || fail "S208/B4 — README.md must say an adopted project is asked about the release-branch tier (its WORKFLOW-ADOPTION.md answer) and gets the release-branch-workflow skill"
# the 'Everything above is what an adopted project gets' paragraph says both tiers are opt-ins
para_has_all "$readme" 'Everything above is what an adopted project gets' '(opt-in|asked|opt in)' 'release-branch' \
  || fail "S208/B4 — the paragraph 'Everything above is what an adopted project gets' must note that the five-role pipeline and the release-branch tier are both opt-ins an adopter is asked about"

# --- effort honesty ---------------------------------------------------------------------
para_has_all "$mc" 'effort' '(self-reported|self-declared|unverified|not verified|can.t be verified|cannot be verified|nothing verifies)' '(platform|unless|not set|unset)' \
  || fail "S208/effort — model-choice must say in one clear sentence that the effort in a marker is self-reported and unverified unless the platform set it (the dispatch tool has no effort setting)"
if para_has_all "$mc" 'effort' '(self-reported|self-declared|unverified|not verified)' '(platform|unless|not set|unset)'; then
  sent="$(tr '\n' ' ' < "$mc" | sed -E 's/\. +/.\
/g' | grep -iE 'effort' | grep -iE 'self-reported|self-declared|unverified|not verified' | grep -iE 'platform|unless|not set|unset' | head -1)"
  [ -n "$sent" ] || fail "S208/effort — the statement must be ONE sentence naming effort, that it is self-reported/unverified, and the platform exception"
fi

test_done

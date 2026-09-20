#!/usr/bin/env bash
# S127-S129 — model-choice never names a model or tier for a floor;
# covers every pipeline stage, with the first floored on task demands;
# pre-merge-review cross-references it instead of restating it.
# Covers: F26
#
# Documentation-content assertions, not behavior: these scenarios verify
# prose in skills/model-choice/SKILL.md and skills/pre-merge-review/
# SKILL.md, found unclaimed by any test file while resolving #272's
# orphan headings.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

model_choice="$TEST_REPO_ROOT/skills/model-choice/SKILL.md"
[ -f "$model_choice" ] || { fail "S127 — skills/model-choice/SKILL.md is missing"; test_done; }
mc_content="$(cat "$model_choice")"

# S127: no model name or tier appears as part of a floor instruction.
assert_contains "S127 — states floors as what output must survive, not a model" "never as a" "$mc_content"
case "$mc_content" in
  *"## Never name a model or tier"*) : ;;
  *) fail "S127 — no section states the never-name-a-model rule, got section headings: $(grep '^##' "$model_choice")" ;;
esac
# The per-stage floor table itself must not smuggle in a concrete model
# name or a bare tier label as a floor.
floor_table="$(awk '/^## Per-stage floors/{p=1} p; /^## The first stage/{exit}' "$model_choice")"
case "$floor_table" in
  *"mid-tier"*|*"flagship"*) fail "S127 — the floor table names a tier label directly: $floor_table" ;;
  *) : ;;
esac

# S128: all five pipeline stages named, each with its own floor; the
# first stage floors on task demands, not a predecessor.
for stage in Discovery Planning Test Implementation Review; do
  assert_contains "S128 — names stage $stage" "$stage" "$mc_content"
done
assert_contains "S128 — every later stage anchors to its predecessor" "the stage before it" "$mc_content"
assert_contains "S128 — the first stage has no predecessor" "no predecessor" "$mc_content"

# S129: pre-merge-review's Model choice section cross-references
# model-choice instead of restating the principle, while still stating
# its own stage's floor and always-record requirement.
pmr="$TEST_REPO_ROOT/skills/pre-merge-review/SKILL.md"
[ -f "$pmr" ] || { fail "S129 — skills/pre-merge-review/SKILL.md is missing"; test_done; }
model_choice_section="$(awk '/^## Model choice/{p=1; print; next} p && /^## /{exit} p' "$pmr")"
[ -n "$model_choice_section" ] || fail "S129 — pre-merge-review/SKILL.md has no 'Model choice' section"
assert_contains "S129 — refers to the model-choice skill" "model-choice" "$model_choice_section"
assert_contains "S129 — states the reviewer floor" "different from" "$model_choice_section"
assert_contains "S129 — states the always-record requirement" "not only when" "$model_choice_section"

test_done

# Architecture decision — Install model for a second user (W37, #79)

This document records *why* the system is the way it is. `PRD.md` describes
what it must do; this is where the structural choices underneath that live,
which alternatives were weighed, and when a choice should be revisited.

Not every decision belongs here. Yes: platform choices, the split into
layers or components, who owns which data, and adding a substantial
dependency. No: how one function is written.

---

## The decision

**Decided on 2026-09-09: a new, git-only entrypoint `install.sh` pins a
checkout to a tagged release, separate from `adopt.sh`.**

`install.sh` runs after a manual `git clone`, from inside that clone
itself. It validates a clean working directory, checks out a given (or
otherwise the latest) tag, and reports the `SPEC_DRIVEN_GUARDRAILS_DIR`
line the user puts in their shell profile. It doesn't adopt a project —
that stays `adopt.sh`'s job. Ties' own multi-machine usage (clone, always
follow `main`) doesn't change: this is a second, explicitly chosen path,
not a replacement.

---

## Evaluation criteria

| Criterion | Why it counts |
|---|---|
| Auditability | This repo's whole style is readable-through bash with no surprises (no `eval`, fail-open when in doubt). An install mechanism that undermines that would undercut exactly the trust the rest of the repo builds. |
| Reuse over building new | W29/#53 decision 5 was explicit: build on W22's existing tag/`CHANGELOG.md` mechanism, don't reinvent anything. |
| Separation of concerns | "Pin this checkout to version X" and "link this project to that checkout" are two different questions with different failure modes (a wrong tag vs. a wrong project) — mixing them makes both harder to reason about. |
| Fits the audience | W37's "second user" is someone already using Claude Code and git (the same workflow is being adopted) — no need for an install mechanism for someone without git. |

---

## Options weighed

### Option 1 — Documentation only, no new script
The consumer reads a new README section and carries out the clone, checkout,
and env-var steps manually. Smallest footprint, zero new code to maintain.
Downside: three manual steps are three places to mistype a tag name or
forget the env var, with no validation at all (for example a dirty working
directory silently overwritten by `git checkout`).

### Option 2 — Convenience entrypoint `install.sh` (chosen)
Automates checkout + validation right after the user has already cloned.
Adds exactly two new, testable guarantees option 1 doesn't give: a dirty
working directory is refused instead of overwritten, and an unknown tag
fails with a clear message instead of a cryptic git error.

### Option 3 — `curl | bash` self-install
One command, no prior clone needed. Rejected: runs external code without
the user reading it first — exactly the pattern this repo's own guardrails
(no `eval`, explicit failure paths) fight elsewhere. Would also solve a
separate, small hosting problem (where does the script live before the
clone) that the other options don't have.

### Option 4 — Packaged release artifacts (tarball/zip without git)
GitHub's automatic source archive per tag would give this partly for free.
But the audience already has git (see the criterion above), and
maintaining a separate artifact format for a need that doesn't exist yet is
exactly the kind of speculative building this repo's own `rule-of-three`
principle rejects elsewhere.

---

## Comparison and choice

Option 2 wins: it solves the two concrete failure modes option 1 leaves
open (silent data loss on a dirty working directory, unclear errors on a
wrong tag), without giving up option 3's auditability or introducing option
4's speculative complexity. What you give up for it: one extra script to
maintain, and the consumer still needs to be able to run `git clone`
themselves — accepted deliberately, see the audience assumption above.

---

## Architecture requirements that follow from this

### A1 — Never write to a dirty working directory
`install.sh` checks `git status --porcelain` before every `git checkout`
and refuses on uncommitted changes. This is visibly violated the moment a
future change puts the checkout step before the dirty check.

### A2 — `install.sh` never calls `adopt.sh`
The two scripts each have their own failure mode and their own target
directory (the shared checkout itself, versus an adopted project). Merging
them would make a bug in one step unrecognizable in the other.

### A3 — No externally fetched code execution
`install.sh` never fetches code only to then run it (no `curl | bash`, no
`eval` of fetched content). Everything that runs already lives in the
cloned checkout and is therefore readable by the user before it runs.

---

## System boundaries and ownership

- **`install.sh`** owns "which version is *this* checkout on" — it only
  changes git state within its own directory (`git fetch --tags`,
  `git checkout <tag>`).
- **`adopt.sh`** stays the owner of "which project is linked to which
  checkout" — unchanged by this decision.
- The two communicate only via `SPEC_DRIVEN_GUARDRAILS_DIR`, an environment
  variable the user sets themselves — no direct call between the scripts
  (see A2).

---

## Dependencies

None new. `install.sh` uses only `git`, already a requirement for any
checkout of this repo.

---

## When we would revisit this choice

- If W35 (#59) describes an audience without git — then option 4 (or a
  variant) becomes needed after all, not as a replacement but as an
  addition.
- If the number of manual steps before `install.sh` (clone, `cd`, run the
  script) itself proves to be a demonstrable source of errors — then option
  3 (with an explicit, readable intermediate step, not a blind
  `curl | bash`) is worth reconsidering.

---

## Still open after this document

- **Decided (2026-09-09): no formal GitHub Release for the existing tag
  before epic #52 itself is done.** `install.sh` and the bare git tag work
  no less well for it — a release now would only make a version
  discoverable that isn't yet what epic #52 promises (not yet translated,
  not yet condensed, no front page yet). A `gh release create` per future
  tag, with notes, therefore stays open until the last work items under
  #52 (W33-W35) land — only then is there something a second user should
  actually want to pin.

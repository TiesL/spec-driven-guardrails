# Attribution

Source: [`mattpocock/skills`](https://github.com/mattpocock/skills), path
`skills/engineering/codebase-design/`, commit `321658273cb1d20b76026717d027d505790106d4`
(2026-08-19). MIT licensed — `LICENSE` in this folder is the original,
unmodified. Copied verbatim, not paraphrased, as a static vendored copy —
not a live dependency (no submodule, no package reference), so upstream
changes to that repo never reach this one without a deliberate edit here.

Files: `SKILL.md` (glossary and principles), `DEEPENING.md` (dependency
categories, seam discipline), `DESIGN-IT-TWICE.md` (parallel sub-agent
interface exploration).

**"Seam" is used two ways in this repo — not a conflict, but worth naming.**
This skill defines seam as Michael Feathers did originally: *where* a
module's interface lives, a design decision distinct from what's behind it.
`tdd-seams` (this repo's own skill) defines it operationally, for test-first
work specifically: "the public boundary a test may act on." Same root
concept (Feathers), different altitude — this skill is about deciding where
to put a seam when designing a module; `tdd-seams` is about using an
already-agreed seam to write a test. Read both if you're doing both jobs.

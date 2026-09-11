# Test scenarios — <Project name>

Purpose: these scenarios describe the intended/observed behavior (see
`PRD.md`). They're independent of the chosen technical solution and
describe only observable behavior.

Notation: **Given / When / Then**.

Every scenario carries a `**Covers:**` field directly under its heading,
with the functionality from `PRD.md` that the scenario describes.
Comma-separated for more than one, e.g. `F3, F4`.

Every token matches `^[A-Z]{1,2}[0-9]+[a-z]?$`. That trailing letter isn't
sloppiness but existing usage — a project in production has an `S2b`
between `S2` and `S3` — and two leading letters occur too (`OP4`). A grammar
that doesn't account for that rejects valid IDs on day one.

The prefix isn't fixed. `F` for functionality and `S` for scenario is
customary, but a project that numbers its scenarios `R`/`A`/`B`/`P` works
unchanged: the check verifies that a token resolves to an existing heading,
not which letter comes before it. Only the field counts — an ID in running
text is not a reference.

Every functionality item from `PRD.md` gets at least one scenario for the
expected behavior, and at least one for what goes wrong: unexpected input,
missing data, or a dependency dropping out. Describing only happy paths is
the fastest way to get surprised by production.

---

## <Feature area 1>

### S1 — <title: the expected behavior>
**Covers:** <F<n>>
- Given: ...
- When: ...
- Then: ...

### S2 — <title: what goes wrong>
**Covers:** <F<n>>
- Given: <unexpected input, missing data, or a dependency that fails>
- When: ...
- Then: <the observable behavior — a readable message, a skipped action, a
  recoverable state; not "something unclear happens">
- And: <what does *not* happen: no partial write, no silent failure>

# AGENTS.md — yxl

This is the **tool-agnostic contributor & AI-agent guide** for `yxl`
(Claude Code, Codex, Cursor, OpenCode, …). It is a [MoonBit](https://docs.moonbitlang.com)
project: a **YAML-driven Excel (`.xlsx`) compiler and CLI**.

> `CLAUDE.md` is a **symlink to this file**, so Claude Code loads it
> automatically and there is exactly one guide to maintain. `ROADMAP.md` holds
> the project direction; this file holds *how we work*.

Extra MoonBit skills to browse/install: <https://github.com/moonbitlang/skills>

---

## 1. Single source of truth: ROADMAP.md

`ROADMAP.md` is the **single source of truth** for direction, phase scope, ADRs,
open questions, risks, and the living changelog. Before any non-trivial work you
MUST:

1. Read the active phase in `ROADMAP.md §6` (the first phase with an unchecked
   box).
2. Confirm the task is on that phase's checklist.
3. If it isn't, **stop and discuss scope** — do not silently widen it.

After completing work, **update `ROADMAP.md` in the same change**: tick the
box(es), add any newly discovered work to the right phase, append an ADR (§7) if
you made an architectural decision (never rewrite an accepted ADR — supersede
it), and add a §11 changelog entry for user-visible changes.

**"開発を進めて下さい" / "continue development"** = follow `ROADMAP.md §10`: find
the active phase, take the next unchecked item, implement it end-to-end, verify,
tick + changelog.

**Do not** create separate planning / decision / analysis docs. Everything goes
into `ROADMAP.md`.

*User-facing* documentation is the exception, and there are exactly three homes
for it: `README.md` (what yxl is, install, a taste), `docs/spec.md` (the spec
format reference), and `examples/` (the worked cookbook, compiled by CI — §6).
Keep them in step with the code in the same change; a doc that lies is worse
than a missing one. `docs/yxl.schema.json` is not a fourth home: it is
*generated* from `docs/spec.md` (ADR-019) — edit the reference and regenerate,
never the JSON.

## 2. MoonBit skills

This project relies on the **MoonBit official skills** (`moonbit-orientation`,
`moonbit-refactoring`, `moonbit-agent-guide`, spec-test workflows), enabled via
the `moonbit-skills@moonbit-code-plugins` plugin (see `.claude/settings.json`).
One-time setup per contributor in Claude Code:

```text
1. Run `/plugin`.
2. "Add Marketplace" → moonbitlang/skills
3. Install the `moonbit-skills` plugin.
```

They auto-engage in `.mbt` files. If `/plugin` is unavailable:

```bash
git clone --recurse-submodules https://github.com/moonbitlang/skills.git \
  ~/.claude/plugins/moonbit-skills
```

## 3. Project structure

- `yxl` **compiles a YAML workbook spec into a `.xlsx` file**. It is *not* a
  spreadsheet engine: Excel evaluates formulas on open; `yxl` only emits them.
- The Excel bytes are produced by the **`bobzhang/mbtexcel`** library (a MoonBit
  port of Go's excelize); `yxl` sits on top of it (see ADR-001, ADR-002).
- MoonBit packages are per directory; each has a `moon.pkg` listing
  dependencies, its source files, blackbox tests (`*_test.mbt`), and whitebox
  tests (`*_wbtest.mbt`). The top-level `moon.mod` holds module metadata.
- MoonBit code is organized in **block style** — each block separated by `///|`,
  order irrelevant. Refactor block-by-block independently.
- Keep deprecated blocks in a `deprecated.mbt` file per directory.
- See `ROADMAP.md §4` for the target package map (`model`, `yaml`, `loader`,
  `resolve`, `emit`, `cli`, …). Phase 1 restructures the `moon new` scaffold into
  it.

## 4. Workflow

### Branching and releases
`main` is **protected — never commit or push to it directly.** Work on a branch
and open a pull request; CI must be green before merge.

```bash
git switch -c <kind>/<short-description>   # feat/, fix/, chore/, docs/, refactor/
# … work, commit …
git push -u origin HEAD
gh pr create --fill
```

A release is a **tag push**, not a merge: tagging a commit on `main` as
`vX.Y.Z` runs `.github/workflows/release.yml`, which refuses to build unless the
tag, `moon.mod`'s `version`, and the constant `yxl version` prints all agree —
so bumping a version means editing both files in the PR *before* tagging.

### Before starting
1. Read the relevant `ROADMAP.md` phase and any ADR you're about to touch.
2. If the task isn't in the active phase, confirm with the user first.
3. Track multi-step work (TaskCreate / TaskUpdate).

### While working
- Run `moon check` after every meaningful edit — fast, catches most mistakes.
- Prefer `moon ide doc <name>` over guessing an API signature (the
  `moonbit-orientation` freshness gate). Never present a guessed API as fact —
  this is doubly important for `bobzhang/mbtexcel`'s surface, which is large and
  versioned (pin the version; verify against `.mooncakes/` source).
- Edit existing files; don't create new files unless a `ROADMAP.md` task or the
  user asks.

### Before reporting complete — validation loop
```bash
moon check              # typecheck
moon test               # run tests
moon fmt                # format
moon info               # regenerate .mbti
moon build --target native   # the CLI must build native (ADR-003)
```
A `.mbti` diff means the public API surface changed — review it and reflect it
in `ROADMAP.md` if it affects a roadmap item.

A change to `docs/spec.md` adds one step, since the JSON Schema is generated
from it (ADR-019) and CI fails when the two disagree:
```bash
python3 tools/spec-schema/generate.py            # rewrite docs/yxl.schema.json
python3 tools/spec-schema/generate.py --selftest # it still refuses what it must
```
The generator refuses to run when the reference documents a key it cannot shape;
teach it the shape in `tools/spec-schema/generate.py` and commit both files.

## 5. Commands reference

| Purpose | Command |
|---|---|
| Type check | `moon check` (`--deny-warn` when refactoring) |
| Build (native CLI) | `moon build --target native` |
| Run the CLI | `moon run src/cmd/main --target native -- <args>` |
| Test | `moon test` |
| Single test | `moon test --filter "<glob>"` |
| Update snapshots | `moon test --update` |
| Format | `moon fmt` |
| Regenerate `.mbti` | `moon info` |
| Benchmark the pipeline | `moon bench src/cli` |
| Coverage | `moon test --enable-coverage && moon coverage report` |
| Add dependency | `moon add <user>/<module>` |
| Regenerate the JSON Schema | `python3 tools/spec-schema/generate.py` |

## 6. Testing conventions

- Every `pub fn` gets ≥1 direct test; every error path (`raise`, `None`) is
  covered.
- **Golden / round-trip tests are mandatory at the compile boundary.** A YAML
  spec compiles to bytes; re-open those bytes (via `mbtexcel`'s reader or an
  external check) and assert the cells/styles/formulas match the spec. Property
  tests belong at every parse↔model↔emit seam.
- Keep the **compiler core I/O-free**: `model`, `loader`, `resolve`, and `emit`
  operate on in-memory strings/bytes so they test without touching the disk.
  Filesystem access lives only in the `cli` layer (ADR-003).
- Prefer `assert_eq` (or `assert_true(x is Pattern(...))` for error variants)
  over snapshots for stable results. For structured debug output, derive `Debug`
  and use `debug_inspect` rather than deriving `Show`. `moon test --update`
  refreshes snapshots when outputs legitimately change.
- A test that only re-runs the type checker (`let _ = …`) duplicates
  `moon check` — delete it.
- Keep example specs runnable: `examples/*.yxl.yaml` should compile in an
  integration test, so the cookbook never drifts from the code.

## 7. Project-specific conventions

These override the generic MoonBit conventions above. Rationale lives in the
`ROADMAP.md §7` ADRs.

- **Backend behind a seam.** Model → bytes goes through one emitter interface so
  the Excel backend (`bobzhang/mbtexcel`) is swappable and the core stays
  testable. Never sprinkle `@xlsx` calls across the pipeline. (ADR-002)
- **Reuse is first-class ("compression").** A value, formula, or style named
  once and referenced many times compiles to Excel's *native* sharing
  mechanisms — shared strings, defined names, shared formulas, a single
  `cellXfs` style id. Never emit N copies of something the spec declared once.
  (ADR-004)
- **Flexible layout.** A spec may inline data and formatting in one file, or
  split them across files via includes/references; both resolve to the same
  model. (ADR-005)
- **Fail fast, explain well.** Validate the schema; an unknown key, dangling
  reference, or type error is a *diagnostic with file/line context*, never a
  silently dropped or guessed value. (ADR-006)
- **Errors:** subdomain suberrors (`YamlError`, `SchemaError`, `ResolveError`,
  `EmitError`, `CliError`), never raw `String` failures.
- **Type-safe boundaries:** no bare `Int`/`String` for cell refs, colors, or
  dimensions in internal APIs — use newtypes (or the backend's typed values).
- **Not a spreadsheet engine.** Formula *evaluation*, macros/VBA, and rendering
  are out of scope — `yxl` emits; Excel computes. (ROADMAP §2)

## 8. Refactoring checklist

When the user says **"リファクタリング" / "refactor" / "tidy up" / "clean up"**,
walk these lenses **in order**, writing a concrete findings list **before**
changing code. Applies whether the trigger is one file or the whole tree.
(Consider invoking the `moonbit-refactoring` skill.)

### 8.1 Constants management
Promote magic numbers / repeated string literals that name a concept to a
`pub let` in the owning package. Domain constants (schema key names, default
column widths, built-in number-format ids, namespace/content-type strings) and
CLI exit codes are defined exactly once and reused.

### 8.2 Duplicate / dead code
Consolidate identical helpers to one location and re-export. Delete `moon new`
stub files (3-line comment-only `.mbt`) unless they hold real API. Delete
smoke/sanity tests superseded by integration tests. Drop unused imports
(`unused_package` warnings). Make `pub` functions called from nowhere private,
or delete them.

### 8.3 File splitting
A `.mbt` over ~500 lines is a *smell*, not a rule — split only at a **logical**
boundary (e.g. YAML tokenizer vs. parser vs. schema mapping), never to hit a
line count. One `_test.mbt` per source file is a good default. Keep blackbox
(`*_test.mbt`) and whitebox (`*_wbtest.mbt`) tests separate.

### 8.4 Test adequacy
Every `pub fn` has ≥1 positive test; every error path is covered; golden /
round-trip tests exist at the compile boundary; tests assert on values, not just
shapes (`assert_eq` over `assert_true` where possible).

### 8.5 Documentation freshness
`ROADMAP.md §6` checkboxes match actual code state; the §11 changelog has an
entry for this change. Public APIs have `///` doc comments. ADRs supersede
rather than mutate. `.mbti` is regenerated (`moon info`) and the diff is the
intended public-API change.

### 8.6 Comment hygiene
**The default is no comment.** A comment is justified only when a reader of the
code *cannot* recover the intent from the code itself; write one there and
nowhere else. Every comment is a line that can go stale independently of the
thing it describes, so each one has to earn its keep. Comments must also make
sense to someone who never read `ROADMAP.md` and wasn't there when the code
landed.

Apply these in order — the first three delete, the last one keeps:

- **Delete what the code already says.** If the comment is a paraphrase of the
  line, the block, or the function name below it, it carries nothing: delete it,
  and if the code really was unreadable, fix the *code* — a better name, a named
  intermediate, a smaller function — rather than annotating it.
- **Delete documentation that wandered into the source.** Format reference,
  schema semantics, rationale for the design, the tour of how a package fits
  together: that is `docs/spec.md`, `README.md`, `examples/`, or a `ROADMAP.md`
  ADR. Written in both places it is duplicated, and the copy in the source is
  the one that rots. Say it once, in the doc; the source may point at it
  (`ADR-004`, `docs/spec.md §10`) but must not restate it. File-header essays
  and section banners (`// ---- helpers ----`) are this failure mode — delete
  them; `///|` already separates blocks and the file name already names the
  subject.
- **Delete narration of the past.** What used to happen, what a commit changed,
  why a reviewer should be convinced — noise once merged. If a *bug* is the
  reason for a non-obvious line, keep the reason and cite the issue (`#52`) in
  one clause; drop the story.
- **Keep the constraint the code can't show** — a spec rule (`ECMA-376
  §18.8.30`), an invariant the compiler doesn't enforce, a deliberate deviation,
  a *why* that is genuinely surprising. One or two lines, at the line it governs.
  `///` doc comments on public APIs stay mandatory: they are API documentation,
  not commentary, and are exempt from the delete rules above.
- **No roadmap/phase codes in comments** (`Phase 3`, `roadmap §6.2`) — name the
  *thing* instead ("the shared-string table", "the dangling-reference check").
  ADR-nnn, ECMA-376 §, and issue #N references are fine — they're stable,
  findable.

**Struct fields carry no `///` of their own.** A field doc does not reach the
generated `.mbti` — only item-level docs do — so it is commentary, not API
documentation, and the exemption above does not cover it. Annotating some
fields and not others is the worst case: the reader can no longer scan the type
at all. Say what a field needs said in the **type's own doc**, in one place
(`model/decorations.mbt`'s `SheetRange` is the pattern), and leave the field
list bare. Conventions that hold across the whole type — "`None` keeps Excel's
default" — are stated once there, never per field.

`enum` variants are the exception, and a narrow one: a one-word constructor can
genuinely fail to say what it selects, so a single line naming the OOXML term or
the Excel dialog wording earns its place. Two lines does not.

Tests are code and get the same treatment. A test's name says what it asserts;
a comment restating that is noise. Keep only the surprising *why* — why this
value and not the obvious one, which past defect the case pins down.

### 8.7 Validation loop after refactoring
```bash
moon check --deny-warn
moon test
moon fmt
moon info                    # commit any .mbti diffs alongside code
moon build --target native   # the CLI still builds
```
Push only when all are clean.

### 8.8 Latest MoonBit language-spec conformance
The toolchain evolves fast; stale idioms accrue debt (ADR-007). During any
refactor, also:
- **Clear deprecation warnings.** Anything the compiler flags deprecated gets
  migrated to the current construct; don't suppress it. Keep migrated-away
  blocks in `deprecated.mbt` only while callers still need them.
- **Verify against ground truth, not memory.** Use `moon ide doc`, the
  `moonbit-orientation` skill, and the local `.mooncakes/` source to confirm a
  construct is current — never assume from an older MoonBit version.
- **Adopt current idioms** where they improve clarity: error handling
  (`raise`/`try`/`?`), pattern-match views, labelled/optional args, method
  syntax over free functions, iterators, and derive macros. Prefer the idiom the
  standard library itself uses now.
- **Keep tooling current.** Regenerate `.mbti` after language upgrades; if a
  `moon` version bump changes formatting or generated output, land that diff on
  its own so it's reviewable.

## 9. Things to avoid

- ❌ Planning/decision docs outside `ROADMAP.md`.
- ❌ Adding a dependency without an ADR in `ROADMAP.md §7`.
- ❌ Silently dropping or guessing unknown/invalid spec input — fail with a
  diagnostic instead.
- ❌ Emitting duplicate content the spec declared once (bypassing the reuse
  machinery).
- ❌ Bare `Int`/`String` for cell refs, colors, or dimensions in internal APIs.
- ❌ Filesystem access outside the `cli` layer.
- ❌ Implementing formula *evaluation* (out of scope — Excel computes on open).
- ❌ Comments that restate the code, or documentation duplicated from
  `docs/`/`ROADMAP.md` into source comments (see §8.6).
- ❌ Skipping `moon fmt` / `moon info` before committing.
- ❌ Using `--no-verify` to bypass the pre-commit hook.
- ❌ Suppressing deprecation warnings instead of migrating (see §8.8).

## 10. When in doubt

- **MoonBit language / API:** rely on the `moonbit-orientation` skill's
  verification tiers; use `moon ide doc` and `.mooncakes/` as ground truth.
  Never present guessed APIs as facts.
- **`bobzhang/mbtexcel` API:** verify against its `.mooncakes/` source and
  `.mbti`; pin the version in `moon.mod`.
- **Project direction:** re-read the relevant `ROADMAP.md` phase; if unclear,
  ask the user.
- **Excel / OOXML semantics:** consult ECMA-376; cite section numbers in commit
  messages / comments when implementing non-obvious parts.

# ROADMAP.md — yxl

> **This file is the single source of truth** for direction, phase scope,
> architecture decisions (ADRs), open questions, risks, and the living
> changelog. Every change that touches scope, design, or status also touches
> this file (see `AGENTS.md §1`). Contributor & agent *workflow* lives in
> `AGENTS.md`; *direction* lives here.

---

## 1. Vision

`yxl` lets you **manage Excel spreadsheets as version-controllable YAML**. You
write a declarative `*.yxl.yaml` spec; `yxl build` compiles it into a real,
Excel-compatible `.xlsx`.

Spreadsheets-as-code, with the properties code has:

- **Diffable & reviewable.** A workbook is text under Git — meaningful diffs,
  code review, blame, CI.
- **DRY / single-source-of-truth ("compression").** A value, formula, or style
  written **once** and referenced many times is managed in one place — and
  compiles down to Excel's *native* sharing (shared strings, defined names,
  shared formulas, a single style id). Change it once, it changes everywhere.
- **Flexible structure.** Keep data and formatting in separate files for large
  workbooks, or inline everything in one file for simple ones — same result.
- **A single native command.** `yxl build report.yxl.yaml -o report.xlsx`.

The engine that writes the actual `.xlsx` bytes is
[`bobzhang/mbtexcel`](https://mooncakes.io/docs/bobzhang/mbtexcel) (a mature
MoonBit port of Go's excelize). `yxl` is the **compiler and CLI on top** — it
owns the language, the reuse/dedup model, validation, and ergonomics.

It is not another spreadsheet *library* (that is `mbtexcel`); it is a different
product category — declarative authoring for people who'd rather edit YAML than
write code.

## 2. Non-goals

- **Formula evaluation.** `yxl` *emits* formulas; Excel computes them on open.
  No built-in calculation engine.
- **Macros / VBA.** Out of scope (can be passed through verbatim at most).
- **Rendering / printing / a GUI.** Text in, `.xlsx` out. (Print *settings* —
  page setup, margins, print area, headers/footers — are still emittable config;
  `yxl` just never renders or prints anything itself.)
- **Imperative editing.** A spec declares the *final* grid; there are no
  insert/delete/move/duplicate operations for rows, columns, or cells (that is
  `mbtexcel`'s editing API — `yxl` emits the end state directly). Sheet order,
  visibility, and the active sheet are still declarative and in scope.
- **Being a general xlsx library.** That is `mbtexcel`; `yxl` depends on it.
- **xlsx → YAML round-tripping.** Reverse import is a post-v1 stretch (§8 Q5),
  not a v1 promise.

## 3. Design principles

1. **Declarative & deterministic.** The same spec always produces the same
   workbook; no hidden state, stable ordering.
2. **Reuse is first-class.** Named definitions compile to Excel's native sharing
   mechanisms — never N copies of one declared thing. (ADR-004)
3. **Fail fast, explain well.** Invalid or ambiguous input is a diagnostic with
   file/line context, never a silent drop or a guess. (ADR-006)
4. **Backend behind a seam.** Model → bytes goes through one emitter interface,
   so the Excel backend is swappable and the core stays testable. (ADR-002)
5. **Core is I/O-free; the CLI does I/O.** `model` / `loader` / `resolve` /
   `emit` work on strings and bytes; filesystem access lives only in `cli`.
   (ADR-003)
6. **Type-safe boundaries.** No bare `Int`/`String` for cell refs, colors, or
   dimensions in internal APIs.

## 4. Package architecture

Target layout under `src/` (Phase 1 restructures the flat `moon new` scaffold —
ADR-008). Dependencies point *downward*; lower packages never import higher.

| Package | Purpose |
|---|---|
| `diag` | Diagnostics + subdomain errors (`YamlError`, `SchemaError`, `ResolveError`, `EmitError`, `CliError`), with source spans (file/line/col) |
| `units` | Type-safe values: cell references, colors, dimensions (or thin wrappers over the backend's typed values) |
| `yaml` | YAML source → a generic document tree (adopt or vendor a parser — §8 Q1); the parser sits behind a seam too |
| `model` | The typed intermediate representation: workbook / sheet / cell / value / style / named definitions |
| `loader` | Document tree → `model`; schema validation with diagnostics; resolves includes / external data (`!include`, data files) |
| `resolve` | Resolve named references & anchors; **intern** shared values / formulas / styles (the reuse/dedup engine) |
| `emit` | `model` → `.xlsx` bytes through the emitter seam; the `mbtexcel`-backed implementation lives here |
| `cli` (`cmd/main`) | Argument parsing, file read/write, `--check` / `--watch`, exit codes, help |

## 5. Verification tiers

- **Tier 1 — In-repo MoonBit tests** (native). Unit + golden + round-trip tests.
  The bar for every phase. The compiler core is I/O-free so it tests on strings
  and bytes.
- **Tier 2 — Example specs** (CI). Every `examples/*.yxl.yaml` compiles, and its
  output is re-opened (via `mbtexcel`'s reader or an external validator) and
  asserted against expectations.
- **Tier 3 — Real applications** (manual, at the v1.0 gate). Open `yxl` output in
  Microsoft Excel, LibreOffice Calc, and Google Sheets.

---

## 6. Phase roadmap

Legend: `[ ]` not started · `[~]` in progress · `[x]` done.
The **active phase** is the first phase with any unchecked box.

### Phase 0 — Bootstrap
- [x] `moon new` scaffold (`t-ujiie-g/yxl`), Apache-2.0 license, README, `cmd/main`
- [x] `.githooks/` (`moon check && moon fmt`), `.claude/` plugin config
- [x] `ROADMAP.md` (this file) + `AGENTS.md` + `CLAUDE.md`→`AGENTS.md` symlink
- [x] Add `bobzhang/mbtexcel` dependency (`moon add bobzhang/mbtexcel@0.1.8`) — ADR-001
- [x] `.github/workflows/ci.yml`: `check` + `fmt --check` + `info` drift +
      `test --target native` + `build --target native`
- [x] Smoke test: `mbtexcel` builds a workbook and emits `.xlsx` bytes
      (asserts the `PK` ZIP magic), proving the toolchain end-to-end

### Phase 1 — Foundations (seam, model, diagnostics)
- [x] Restructure into the `src/` package map (ADR-008)
- [x] `diag`: source spans + subdomain error types
- [x] The **emitter seam** (ADR-002): a trait `model → bytes`, plus a minimal
      `mbtexcel` implementation (new workbook, one sheet, string/number cell,
      write)
- [x] Minimal `model`: workbook / sheet / cell / value
- [x] `units`: type-safe `CellRef` (needed by the model; §4 package)
- [x] Pick the YAML parser (§8 Q1) — record the decision as an ADR (ADR-009)

### Phase 2 — YAML → a sheet of values (walking skeleton)
- [x] Parse a minimal spec: `workbook › sheets › cells` (text / number / bool)
      — the `yaml` seam: source → a `Node` document tree (ADR-010)
- [x] `loader` maps it to `model`; `emit` produces `.xlsx` (incl. `bool` cells)
- [x] `cli`: `yxl build <in.yaml> -o <out.xlsx>` (native), exit codes (ADR-011)
- [x] Golden test: spec → bytes → re-open → assert cells

### Phase 3 — Rich cell values
- [x] Number formats (built-in + custom): the expanded cell form
      `{ value:, format: }`; equal format codes intern to one style id (ADR-004)
- [x] Dates / date-times (with a date system): `{ value:, type: date }`, the 1900
      (default) and 1904 systems via top-level `date1904`, serial conversion in `units`
- [x] Formulas (emit `<f>`; Excel computes on open) with optional cached value:
      `{ formula: "SUM(A1:A2)", value: <cached> }` (a leading `=` is accepted)
- [x] Booleans (Phase 2), error literals (`type: error`, validated), and explicit
      typing (`type: text | number | bool` coercion)

### Phase 4 — Styling
- [x] Named styles: font (bold/italic/size/name/color), fill, border, alignment
- [x] Number format as part of a style
- [x] Style **reuse** → a single interned style id per distinct style
- [x] Rich text: mixed fonts/colours within a single cell (`set_cell_rich_text`)
- [x] Column/row default styles and the workbook default font
      (`set_col_style` / `set_row_style` / `set_default_font`)

### Phase 5 — Reuse / dedup engine ("compression") — the differentiator
- [x] Named definitions for values, formulas, and styles (declare once) — the
      top-level `defs:` block (ADR-012)
- [x] Reference syntax: bareword name for styles, `{ $ref: name }` for values
      and formulas — explicit definitions, not YAML anchors (ADR-012 resolves Q3)
- [x] Compile references to Excel-native sharing: shared strings and shared
      style ids (already native — string dedup + style interning), and **defined
      names** for named values/formulas, referenced as `=name` (ADR-013). Shared
      *formulas* (fill-down grouping) await a range-formula construct — nothing
      references them, so not part of reference compilation.
- [x] Diagnostics for **dangling** references — every undefined style/value/
      formula reference is a fail-fast `@diag.SchemaError` (ADR-006), landed with
      the references above. *Cyclic*-reference detection is **not applicable
      yet**: definitions cannot reference one another (values are scalars,
      formulas are opaque strings, styles are self-contained), so no cycle can
      form. It belongs with whatever first lets a definition reference another
      (e.g. templating, §Phase 7) and will land there.

### Phase 6 — Layout & structure
- [x] Merged cells, column widths, row heights — a sheet `merges:` list of
      `A1:B2` ranges; `width:` on a column band and `height:` on a row band
- [x] Column/row visibility (hide/show) and **outline grouping** — collapsible
      row/column groups via outline levels (`set_{col,row}_outline_level`); a
      band takes `hidden:` and `group:` (level 0–7, validated in the loader)
- [x] Multiple sheets: order (declaration order is the tab order), active sheet
      (top-level `active: <name>`), sheet visibility (per-sheet
      `visibility: visible | hidden | very_hidden`)
- [x] Freeze / split panes, gridlines, tab color — per-sheet `freeze: <cell>`,
      `split: { x, y }` (points), `gridlines: false`, `tab_color: "RRGGBB"`
- [x] Page setup for print: orientation, margins, scaling, print area,
      headers/footers, page breaks (`set_page_layout` / `set_page_margins` /
      `set_header_footer` / `insert_page_break`) — a per-sheet `print:` block

### Phase 7 — Modular specs
- [ ] Includes / data–format separation (`!include`, external data files)
- [ ] External data sources (CSV/JSON tables feeding a sheet region)
- [ ] Lightweight templating / parameterization — the first construct that can
      let one definition reference another, so **cyclic-reference detection**
      (deferred from Phase 5) lands here

### Phase 8 — CLI UX
- [ ] Rich diagnostics rendered with file/line/col and carets
- [ ] `--check` (validate only), `--watch`, stdin/stdout, `--version`, help
- [ ] Stable exit codes; native binary packaging + install docs

### Phase 9 — Richer Excel features (leverage mbtexcel, additive)
- [ ] Charts, images, **Excel tables** (structured tables / ListObjects,
      `add_table`)
- [ ] **Pivot tables** (`add_pivot_table`) — the heaviest item here (source data,
      cache, field layout); may land late or as a stretch
- [ ] Data validation, conditional formatting, hyperlinks, comments
- [ ] Auto filter (`set_auto_filter`)
- [ ] Sheet / workbook protection, incl. password-based encryption
      (`protect_sheet` / `write_with_password`)
- [ ] Workbook metadata: document properties (title/author/company/custom) and
      calculation mode (`set_core_properties` / `set_calc_props`)
- [ ] Further additive extras as demand warrants: sparklines, shapes, form
      controls, slicers, sheet backgrounds, duration cells

### Phase 10 — Performance & scale (and stretch: reverse import)
- [ ] Large-spec performance; streaming where `mbtexcel` supports it
- [ ] Benchmarks + regression guardrails in CI
- [ ] Stretch: `xlsx → yxl.yaml` reverse import (§8 Q5)

### v1.0 — Stability gate
- [ ] Schema freeze (breaking budget spent here); documented spec reference
- [ ] Tier-2 green across the example corpus
- [ ] Tier-3 manual: Excel / LibreOffice / Google Sheets open cleanly
- [ ] Cookbook + CLI docs complete
- [ ] Release policy: v1.0.0 ships when the schema + CLI are stable

---

## 7. Architecture Decision Records (ADRs)

ADRs are append-only. When a decision changes, add a new ADR and mark the old
one **Superseded** — never rewrite an accepted ADR.

### ADR-001 — Build on `bobzhang/mbtexcel` as the Excel backend
**Status:** Accepted.
**Context:** Two credible bases exist: the official, comprehensive
`bobzhang/mbtexcel` (a Go-excelize port: read/write, styles, charts, images,
pivots, formulas, data validation) and `t-ujiie-g/moon-xlsx` (a leaner, pure,
type-safe from-scratch writer).
**Decision:** Depend on `bobzhang/mbtexcel`. A test drive confirmed it is
consumable as a library (`@bobzhang/mbtexcel/xlsx`: `Workbook::new`,
`new_sheet`, `set_cell_*`, `new_style(Style) -> Int`, `write(Workbook) ->
Bytes`), **builds and runs on native**, and produces valid files (verified with
openpyxl). Its breadth and maturity outweigh reimplementing a writer.
**Trade-offs:** heavier transitive deps (`moonbitlang/async` incl. `async/fs`,
`x/time`, `crypto`, `zip`); the package is native-oriented (`preferred_target =
native`), so wasm/js portability is not guaranteed; young semver (0.1.x) implies
API churn — **pin the version**. These are mitigated by ADR-002 (seam).

### ADR-002 — Emitter seam; the backend is swappable
**Status:** Accepted.
**Decision:** `model → bytes` goes through a single emitter interface. The
`mbtexcel` implementation lives behind it. This isolates backend API churn,
keeps the pipeline testable without the backend, and preserves the option to add
a lighter/portable backend later (e.g. `moon-xlsx` for a wasm CLI — §8 Q6).

### ADR-003 — Native CLI; core is I/O-free
**Status:** Accepted.
**Decision:** `preferred_target = native`; the CLI (`cmd/main`) is the only
place that touches the filesystem. `model` / `loader` / `resolve` / `emit`
operate on in-memory strings and bytes so they unit-test without disk I/O.

### ADR-004 — Reuse compiles to native Excel sharing
**Status:** Accepted.
**Decision:** A named-once, used-many value/formula/style compiles to Excel's
own sharing mechanisms — shared strings, defined names, shared formulas, a
single `cellXfs` id — not to duplicated cells. This makes the output both small
and genuinely single-managed.

### ADR-005 — Flexible spec layout (inline or split)
**Status:** Accepted.
**Decision:** A spec may inline data and formatting, or split them across files
via includes/references; both resolve to the same `model` before emission.

### ADR-006 — Fail-fast diagnostics
**Status:** Accepted.
**Decision:** Validate strictly. Unknown keys, dangling references, and type
mismatches are diagnostics with source spans, never silently dropped or guessed.

### ADR-007 — Track the latest MoonBit language spec
**Status:** Accepted.
**Context:** The toolchain evolves quickly; stale idioms accrue debt.
**Decision:** Prefer current idioms; migrate off deprecated syntax proactively
(AGENTS.md §8.8). Deprecated blocks live in `deprecated.mbt`.

### ADR-008 — `src/` sub-package layout
**Status:** Accepted.
**Decision:** Restructure the flat `moon new` scaffold into the `src/` package
map of §4 in Phase 1, so `moon.mod` uses `source = "src"` and packages have
clear, acyclic boundaries.

### ADR-009 — YAML parser: depend on `moonbit-community/yaml`, behind our seam
**Status:** Accepted. (Resolves §8 Q1.)
**Context:** Four candidates exist in the registry: `moonbit-community/yaml`
(pure MoonBit), `myfreess/yaml` (no description/repo, one release),
`ingydotnet/yamlscript` & `yamlstar` (official YAML-org loaders), and
`tonyfettes/tree_sitter_yaml` (a tree-sitter grammar). We need source positions
for diagnostics (ADR-006) and a self-contained native binary (ADR-003).
**Decision:** Depend on **`bobzhang`-style pure library `moonbit-community/yaml`**
(pin `@0.0.6`), consumed **behind the `yaml` seam package** (§4). It follows the
proven libyaml/PyYAML event architecture (`Parser` → `Event` stream with a
`MarkedEventReceiver`), exposes a `Marker { index, line, col }` so we can attach
file/line/col to every `YamlError` (ADR-006), already handles anchors/aliases
(useful for the reuse model, §8 Q3), provides a `Yaml` value tree with `ToJson`,
and depends only on `core` — **no native FFI**, so the CLI stays a clean,
portable native build (ADR-003).
**Rejected:** `ingydotnet/*` — the strongest *pedigree* (the YAML project
itself), but they bind to the native `libyamlscript` shared library, adding a
heavy, platform-specific runtime dependency at odds with ADR-003.
`tree_sitter_yaml` — a C/tree-sitter grammar producing a concrete syntax tree,
not a value loader; also native FFI. `myfreess/yaml` — too immature.
Hand-rolling a `@json` subset — deferred fallback only, loses YAML ergonomics
(comments, anchors, block scalars) and re-implements a solved problem.
**Trade-offs:** the library is young (0.0.x) and may churn — mitigated by the
`yaml` seam (§4, §8 Q1), which exposes *our* document tree + spans to the rest of
the pipeline so the dependency can be swapped or vendored without touching
`loader`/`resolve`/`emit`. For full per-node spans we drive the low-level
`MarkedEventReceiver` (events carry `Marker`s), not just `Yaml::load_from_string`
(whose value tree drops positions). The `moon add` and the seam land in Phase 2,
where the parser is first used.

### ADR-010 — Parser source spans are deferred (library seals its event API)
**Status:** Accepted. (Refines ADR-009; does not supersede it — the library is
still our parser.)
**Context:** ADR-009 chose `moonbit-community/yaml` partly for per-node source
spans via its `MarkedEventReceiver` (events carry `Marker { line, col }`).
Implementing that seam revealed the trait is a **sealed** `pub trait` (not
`pub(open)`), so a type in *our* crate cannot implement it — the event/marker
API is unusable by external callers. The high-level `Yaml::load_from_string`
value tree we can use carries **no positions**, and its `YamlError` is opaque
across the package boundary (no extractable marker).
**Decision:** For now the `yaml` seam consumes `Yaml::load_from_string` and maps
its (already text/number/bool-classified) value tree to our `Node`. `Node`
carries **no spans yet**; diagnostics from `yaml`/`loader` name the **file** but
not a line/col. This is acceptable because **rich file/line/col diagnostics are a
Phase 8 deliverable**, not a Phase 2 one.
**Consequences / path forward:** the `yaml` seam (§4) keeps the parser swappable,
so Phase 8 can obtain spans by one of: (a) upstreaming an open/marked API to
`moonbit-community/yaml`, (b) vendoring a span-capable subset parser, or (c)
switching parsers — all behind the seam, touching only `yaml` (+ the shape of
`Node`). Downstream code already flows optional spans through `@diag.Diagnostic`
(its `span` is optional), so adding spans later is additive.

### ADR-011 — `moonbitlang/x` for the CLI's filesystem, args, and exit
**Status:** Accepted.
**Context:** The `cmd/main` executable needs synchronous file read/write, the
argv, and a process exit code. `core` has none of these; `moonbitlang/async/fs`
(a transitive dep) is async and would drag an event loop into a simple batch CLI.
**Decision:** Depend on **`moonbitlang/x@0.4.47`** (the official MoonBit extended
library) and use `x/fs` (`read_file_to_string`, `write_bytes_to_file`) and
`x/sys` (`get_cli_args`, `exit`). It is used **only** in `cmd/main`, preserving
the I/O-free core (ADR-003). Its `IOError` is `pub(all)`, so the CLI pattern-matches
it for a clean "cannot read/write \<file\>: \<reason\>" message.
**Trade-offs:** `x` is a broad, still-`0.x` grab-bag, but it is first-party and
the surface we use (fs/sys) is small and stable; confined to `cmd/main`, a future
swap touches one file.

### ADR-012 — Named definitions with explicit references; resolved in the loader
**Status:** Accepted. (Resolves §8 Q3.)
**Context:** Phase 5 lets an author declare a value/formula/style once and
reference it many times, compiling to Excel's native sharing (ADR-004). ADR-009
had noted YAML anchors/aliases as a candidate, but the chosen parser
(`moonbit-community/yaml`) **resolves `*alias` into a copy of the anchored value
during load** (its loader looks the anchor up and inlines it), so by the time the
`yaml` seam hands us a `Node` there is no alias identity left — anchors give
textual reuse but cannot be compiled to *defined names* or *shared formulas*.
**Decision:** Reuse is expressed with **explicit named definitions**: a top-level
`defs:` block with `styles`, `values`, and `formulas` maps. A **style** is
referenced by bareword name where a `style:` mapping would go (`style: header`),
matching the existing scalar-shorthand idiom (`fill:` hex, `border:` name). A
**value** or **formula** is referenced by `{ $ref: name }` — an explicit marker
is needed because a bare scalar there is a literal value. The reference's kind is
fixed by position (`style:`/`value:`/`formula:`), so each kind has its own
namespace and a name may be reused across kinds. YAML anchors remain usable as
plain-text convenience but are not the sharing mechanism.
**Resolution stays in the `loader` for now:** references resolve to the same
model value/style, and the emitter's existing structural interning (ADR-004)
already collapses them to one shared string / `cellXfs` id — so the source-level
single-source-of-truth is delivered without a `resolve` package yet. Excel
*defined names* and *shared formulas* (Phase 5 item 3) will introduce `resolve`
(§4) and carry reference identity into the model. A reference to an undefined
name is a fail-fast `@diag.SchemaError` (ADR-006); cyclic references cannot occur
until definitions may reference each other.

### ADR-013 — References compile to Excel defined names; `=name` cells
**Status:** Accepted. (Extends ADR-012 for Phase 5 item 3.)
**Context:** ADR-012 made references resolve in the loader by inlining the target
value/formula. That already yields Excel-native sharing for two of the four
mechanisms — repeated string values dedupe into the **shared-strings** table
automatically, and equal styles intern to one **cellXfs** id (ADR-004). The
missing piece is a mechanism the *author* can edit centrally in Excel: a
**defined name**.
**Decision:** Every declared `defs.values`/`defs.formulas` entry is emitted as a
workbook **defined name** (`set_defined_name`), in declaration order so output is
deterministic. A value or formula **reference** compiles to the formula `=name`
(a `model.Formula` whose body is the name), caching the definition's value so the
cell displays it until Excel recomputes — editing the defined name in Excel then
updates every reference (the §1 "change once, changes everywhere" promise). A
constant's `refers_to` is its formula literal (a string is quoted with inner
quotes doubled; a number/bool/date is its literal); a named formula's is its body
verbatim. Styles are **not** defined names (Excel has no such concept beyond
`cellXfs`); style references stay interned (ADR-012).
**Trade-offs / consequences:** a referenced value cell is a *formula* (`=name`),
not a literal — the chosen behavior, since it is what makes central editing work.
A named formula's defined name inherits Excel's relative-reference semantics
(evaluated relative to the referencing cell); authors wanting position
independence use absolute refs — consistent with "yxl emits, Excel computes"
(§2). Invalid Excel names (e.g. a name shaped like a cell ref) are rejected by
the backend as an `EmitError`; loader-side name validation with better spans is a
Phase 8 refinement. **This fit in the `loader` plus one model field
(`Workbook.defined_names`), so the dedicated `resolve` package (§4) that ADR-012
anticipated is still deferred** — it will land when a pass genuinely needs its own
stage (shared-formula grouping, or cycle detection once definitions may reference
each other).

## 8. Open questions

- **Q1 — YAML parser.** ✅ **Decided (ADR-009), refined (ADR-010):** depend on
  `moonbit-community/yaml@0.0.6` (pure MoonBit, no native FFI), consumed behind
  the `yaml` seam. Its span-carrying event API turned out to be a sealed trait, so
  per-node spans are deferred to Phase 8 (ADR-010); the seam keeps that swap
  local. `moon add` + seam landed in Phase 2.
- **Q2 — Schema altitude.** How close should the schema mirror Excel's structure
  vs. a higher-level ergonomic DSL (e.g. `table:` shorthands)? Start close to
  Excel, add sugar later.
- **Q3 — Reference syntax.** ✅ **Decided (ADR-012):** explicit named definitions
  in a top-level `defs:` block — a bareword name for styles, `{ $ref: name }` for
  values and formulas. YAML anchors were rejected as the core mechanism because
  the parser expands aliases to copies, losing the identity needed to compile to
  defined names / shared formulas.
- **Q4 — Data/format split mechanism.** `!include`, external CSV/JSON data
  sources, or a `data:` / `format:` split within one document?
- **Q5 — Reverse import.** Is `xlsx → yxl.yaml` in scope for v1, or a post-v1
  stretch? (Currently a stretch — §6 Phase 10.)
- **Q6 — Distribution.** Native binary only, or also a wasm CLI? A wasm target
  would favor a lighter backend (`moon-xlsx`) via the ADR-002 seam.

## 9. Risks

- **Backend API churn (mbtexcel 0.1.x).** Mitigation: pin the version; the
  ADR-002 seam contains the blast radius.
- **Heavy / native-only transitive deps.** Mitigation: accept the native target
  (ADR-003); the seam keeps a lighter backend possible later.
- **YAML parser availability.** Mitigation: seam the parser; start with a minimal
  subset and widen.
- **Scope creep into a full spreadsheet library.** Mitigation: the §2 non-goals;
  lean on `mbtexcel` for Excel features rather than reimplementing them.

---

## 10. How to "進める" (pick the next task)

1. Read this file top-to-bottom the first time; thereafter jump to §6.
2. Find the **active phase** — the first phase with an unchecked `[ ]` box.
3. Pick the **next unchecked item** in that phase (top-to-bottom order).
4. If the item is unclear or seems to widen scope beyond the phase, **stop and
   ask** rather than silently broadening it.
5. Implement it end-to-end: code + Tier-1 tests (incl. golden/round-trip where a
   boundary is crossed).
6. Run the validation loop (AGENTS.md §4): `moon check` → `moon test` →
   `moon fmt` → `moon info` → `moon build --target native`.
7. In the **same change**: tick the box, append a §11 changelog entry, and add
   an ADR (§7) if you made an architectural decision.

## 11. Living changelog

Reverse-chronological. One entry per user-visible or structural change.

- **2026-07-25** — **Phase 6 complete: page setup for print.** A sheet takes a
  `print:` block — `area` (a range), `orientation`, `margins` (in inches, Excel's
  unit here), `scale` (a percentage) *or* `fit: { width, height }` (pages across
  and down), `header` / `footer` (Excel's `&`-code syntax, ECMA-376 §18.3.1.46),
  and `breaks` (cells that each start a new page). Nested under one key rather
  than flattened onto the sheet, so the sheet's top level does not balloon.

  Diagnostics: a scale outside Excel's 10–400, a non-integer scale or page
  count, `scale` together with `fit` (Excel offers one or the other), a `fit`
  constraining neither axis, a negative margin, and a break at `A1`.

  Two details the backend does not handle for us. A print area is not a normal
  setting but Excel's built-in **sheet-scoped defined name** `_xlnm.Print_Area`,
  whose value must be absolute and sheet-qualified (`'Report'!$A$1:$D$50`) —
  hence the new `@units.CellRef::to_absolute_a1`. And `fitToWidth`/`fitToHeight`
  are ignored by Excel unless the sheet also carries `<pageSetUpPr
  fitToPage="1"/>`, so a `Fit` scale sets that flag too.

  Added `model.PageSetup` / `PageMargins` / `PageScale` / `Orientation` and
  `Sheet.page` + `set_page_setup`; renamed `MergeRange` → `CellRange` (a print
  area is the same rectangle a merge is) and extracted the shared `parse_range`
  the loader now uses for both. Round-trip verified through the reader, plus the
  emitted `sheet1.xml` and `workbook.xml` inspected directly. 100 tests green.
  **Phase 6 is complete.**

- **2026-07-25** — **Phase 6: freeze / split panes, gridlines, tab color.** A
  sheet takes `freeze: <cell>` — the rows above and columns left of that cell
  stay put, exactly what Excel's "Freeze Panes" does with the cell selected — or
  `split: { x, y }` for a draggable splitter. Freezing names a *cell* because a
  freeze always lands on a row/column boundary; a split names a *position in
  points* because it falls wherever it is dragged. `freeze: A1` (freezes
  nothing), a split with no non-zero axis, and combining `freeze` with `split`
  are all diagnostics. Also `gridlines: false` (the on-screen grid, not cell
  borders) and `tab_color: "RRGGBB"`, reusing the existing color parser.

  Added `model.Panes` (`Freeze` / `Split`) plus `Sheet.panes` / `gridlines` /
  `tab_color` with setters; the emitter maps them to `set_panes`,
  `set_sheet_view`, and `set_sheet_props`, converting a split's points to the
  twips OOXML wants — a backend unit, so the conversion stays behind the seam
  (ADR-002). Round-trip verified for the freeze, gridlines, and tab color; a
  split's `state` attribute is *absent* by design (ECMA-376 §18.18.52 defaults
  it to "split"), which the backend's reader does not model, so that case is
  verified on the emitted `worksheets/sheetN.xml` instead. 95 tests green.

- **2026-07-25** — **Phase 6: multiple sheets — order, active sheet, visibility.**
  Declaration order is the tab order (now asserted, not just assumed). A sheet
  takes `visibility: visible | hidden | very_hidden` — a bareword rather than a
  boolean, because Excel has three states here (`ST_SheetState`, ECMA-376
  §18.18.68), unlike a band's two-state `hidden:`. A top-level `active: <name>`
  picks the tab Excel opens on, by name rather than index, so a typo is a
  diagnostic instead of silently opening elsewhere.

  Three fail-fast checks land in the loader rather than at emit time (ADR-006):
  an `active` naming no declared sheet, an `active` naming a *hidden* one (Excel
  cannot open on a tab it does not show), and a workbook whose every sheet is
  hidden (the backend rejects it with a bare EmitError). Added
  `model.SheetVisibility` + `Sheet.visibility` and `Workbook.active_sheet` /
  `set_active_sheet`; `add_sheet` and `Sheet::new` take an optional
  `visibility~`. The emitter hides tabs in a pass *after* every sheet exists —
  hiding inside the sheet loop would trip the backend's "at least one visible
  sheet" guard whenever an early sheet is the hidden one — then resolves
  `active_sheet` through `sheet_index` to Excel's `activeTab`. Round-trip
  verified, plus the emitted `workbook.xml` inspected directly. 91 tests green.

- **2026-07-25** — **Phase 6: column/row visibility and outline grouping.** A
  column or row band takes `hidden: true` (hide the band) and `group: <level>`
  (the outline level Excel draws as a collapsible bracket — `0` is ungrouped,
  `@model.max_outline_level` = 7 is the deepest). Set both to emit a *collapsed*
  group. The level is validated in the loader, so `group: 8` or `group: 1.5` is a
  `SchemaError` with file context (ADR-006) rather than a backend failure at emit
  time. Round-trip verified: visibility and outline level read back, and a
  band's width/height is unaffected by grouping.

  Structurally, the four per-property band arrays on `Sheet` collapsed into one
  `AxisBand` — an inclusive span plus optional `style`, `size`, `hidden`, and
  `outline_level` — held in `Sheet.columns` / `Sheet.rows`. Adding these two
  properties the old way would have taken the sheet from four band arrays to
  eight, and `load_axis_spec` from a pair to a 4-tuple; one band record per YAML
  entry mirrors the spec shape instead. `set_column_style`/`set_column_width`/
  `set_row_style`/`set_row_height` are replaced by `set_column_band` /
  `set_row_band` (all properties optional) — the whole public-API delta in the
  `.mbti`. An entry that sets nothing (`- at: B`) still contributes no band. 88
  tests green.

- **2026-07-25** — **Phase 6 started: merged cells, column widths, row heights.**
  A sheet may carry `merges:` — a list of `A1:B2` range strings, each merged into
  one cell (corners in any order; the model canonicalizes to top-left /
  bottom-right, and the merge keeps the top-left value). A column band gains an
  optional `width:` (character units) and a row band an optional `height:`
  (points), alongside the existing `style`/`format`; `width` is rejected on a row
  band and `height` on a column band. Added `model.AxisSize` and `MergeRange`,
  `Sheet.column_widths`/`row_heights`/`merges` with their setters and
  `@units.CellRef::rect` (corner canonicalization), wired the loader
  (`load_axis_spec` now returns a style *and* a size; new `load_merges`) and the
  emitter (`set_col_width`/`set_row_height`/`merge_cell`). Round-trip verified:
  the merge range, width, and height read back, and the merged cell keeps its
  value. **Phase 5 is complete** (item 4 tidied: dangling diagnostics done;
  cyclic-reference detection deferred to Phase 7 templating, where definitions
  first reference one another). 85 tests green.

- **2026-07-24** — **Refactor pass (whole tree).** Deduplicated the `units`
  scalar parsers: `CellRef::parse_a1` no longer hand-rolls base-26 and digit
  loops — it splits the letters from the digits and reuses `parse_column` and
  `parse_uint`; `parse_column` now takes a `StringView` (matching `parse_uint`),
  and the loader's `split_range` yields `StringView`s straight into both (dropping
  its `.to_owned()` copies). Replaced ASCII magic numbers (`65`/`48`/`32`) with
  char-literal arithmetic (`'A'.to_int()`, `'0'.to_int()`) and `color`'s hex
  upper-casing loop with `Char::to_ascii_uppercase`. Refreshed two stale package
  docs: the `yaml` seam no longer claims per-node source spans (it has none yet —
  ADR-010), and `units` lists colours/dates as present, not future. No behaviour
  change; the only public-API delta is the intentional `parse_column` →
  `StringView` signature. 81 tests green.

- **2026-07-24** — **Phase 5: references compile to Excel defined names.** Every
  `defs.values`/`defs.formulas` entry now emits a workbook **defined name** (in
  declaration order, deterministic), and a `{ $ref: name }` reference compiles to
  the formula `=name` — so editing the defined name in Excel updates every
  reference (§1's "change once, changes everywhere"). A referenced value caches
  its constant (`=tax_rate` shows `0.08` until recompute); a `refers_to` literal
  quotes strings (inner quotes doubled) and passes numbers/formulas through. The
  other two native mechanisms in the item were already satisfied — repeated
  strings dedupe into shared strings, styles intern to one `cellXfs` id (ADR-004);
  shared *formulas* (fill-down) await a range construct and aren't referenced.
  Added `model.DefinedName` + `Workbook.defined_names`/`add_defined_name`, wired
  the loader to register names and resolve refs to `=name`, and the emitter to
  `set_defined_name`. Recorded as **ADR-013**; the dedicated `resolve` package
  stays deferred (this fit in loader + one model field). Round-trip verified:
  defined names and the `=name` cell survive re-opening. 81 tests green. **Phase 5
  item 3 done; only item 4's cyclic-ref case remains (dangling already covered).**

- **2026-07-24** — **Phase 5 started: named definitions + references (declare
  once).** A spec may carry a top-level `defs:` block — `styles`, `values`, and
  `formulas` maps — that declare a look, constant, or formula once. Cells,
  columns, and rows reference a style by bareword name (`style: header`); a cell
  references a named value or formula by `{ $ref: name }` (e.g. `A1: { $ref:
  company }` as a whole-cell shorthand, or `{ value: { $ref: rate }, format:
  "0.00%" }` / `{ formula: { $ref: subtotal } }` inside the expanded form). A
  referenced style still layers the cell's own `format` on top, and references
  resolve to the same model value/style so the emitter's existing interning
  (ADR-004) collapses them to one shared string / `cellXfs` id. YAML anchors were
  rejected as the mechanism (the parser expands aliases to copies, losing the
  identity needed for Excel-native sharing) — recorded as **ADR-012**, which
  resolves **Q3**. A reference to an undefined name is a fail-fast
  `@diag.SchemaError`. Resolution lives in the `loader` for now; Excel *defined
  names* / *shared formulas* (Phase 5 item 3) will add the `resolve` package.
  80 tests green. **Phase 5 items 1–2 done; items 3–4 (native-sharing compilation,
  cyclic-ref diagnostics) remain.**

- **2026-07-24** — **Refactor pass (whole tree).** Deduplicated: the two
  top-level key scans (`read_date_system`/`read_default_font`) now share a
  `find_key` helper, and `load_sheets` uses the existing `expect_seq`; the
  loader's row-index digit parser reuses `@units.parse_uint` (promoted to public)
  instead of a second hand-rolled loop; the emitter's underline OOXML mapping is
  a single `underline_code` helper shared by the cell-font and rich-text-font
  builders. Moved `combine_style` from `cell.mbt` to `style.mbt`, co-locating
  style assembly with the style parser it drives. Refreshed the stale `load`
  doc comment (it predated `style`/`rich`/`columns`/`rows`/`default_font`) and
  added direct unit tests for `@units.parse_column` and `@units.parse_uint`. No
  behaviour change; only public-API delta is the intentional `parse_uint`
  export. 75 tests green.

- **2026-07-24** — **Phase 4 complete: column/row default styles + workbook
  default font.** A sheet may carry `columns:` and `rows:` — sequences of bands,
  each `{ at: <selector>, style?, format? }` — that apply a default style to a
  whole column/row band; `at` is a column label or range (`B`, `D-F`) or a row
  number or range (`1`, `2-4`). A top-level `default_font: <name>` sets the
  workbook default font face. Band styles share the cell style-id cache, so a
  column style equal to a cell style reuses one `cellXfs` id (ADR-004) — verified
  by re-opening and comparing the cell's, columns', and row's style ids. Added an
  `AxisStyle` model type + `Sheet::set_column_style`/`set_row_style`, a
  `Workbook.default_font`, and `@units.parse_column`; wired the emitter to
  `set_col_style`/`set_row_style`/`set_default_font`. The style parser now takes
  a `context` label so cell, column, and row diagnostics all read naturally.
  (Bands are a **sequence** rather than a selector-keyed mapping because the YAML
  parser rejects bare integer keys, and row selectors are integers.) **Phase 4
  (styling) is done; the active phase is Phase 5 (reuse / dedup engine).**
  73 tests green.

- **2026-07-24** — **Phase 4: rich text.** A cell may hold a `rich:` run list
  instead of a single value — `{ rich: ["Plain ", { text: "bold red", font: {
  bold: true, color: "FF0000" } }] }` — compiling to Excel's inline rich text,
  each run carrying its own optional font (the same `font` shape as a cell
  style). A rich-text cell may still take a cell `style` (alignment, fill,
  borders). Added `CellValue::RichText([RichRun])` and a `RichRun { text, font }`
  model type, wired the emitter to `set_cell_rich_text`, and had the loader
  reject `rich` combined with `value`/`formula`/`type` and an empty run list.
  Round-trip verified: runs and per-run fonts survive re-opening (the backend
  stores colors as ARGB). Only Phase 4 item 5 (column/row default styles + the
  workbook default font) remains. 70 tests green.

- **2026-07-24** — **Phase 4: cell styles (font, fill, border, alignment) with
  interning.** A cell may carry a `style:` mapping —
  `{ font: { bold: true, size: 12, name: Calibri, color: "FF0000" }, fill:
  "FFFF00", align: { horizontal: center, vertical: middle, wrap: true }, border:
  { all: thin, bottom: { style: double, color: "000000" } } }`. The `format:`
  number-format shorthand now folds into the style, so the number format is one
  attribute of the interned look (ADR-004 item 2): equal styles compile to a
  single `cellXfs` id, distinct ones to distinct ids — verified by re-opening the
  bytes and comparing style ids and the read-back `Style`. New model types
  (`Style`, `Font`, `Fill`, `Borders`/`Border`/`BorderStyle`, `Alignment`/
  `HAlign`/`VAlign`) all derive `Eq`/`Hash` so the emitter interns on the model
  style; colors are a type-safe `@units.Color` newtype (validated hex), never a
  bare `String`. `Cell.format : String?` became `Cell.style : Style?`;
  `Sheet::set` gained a `style?` argument beside `format?`. Style parsing lives
  in the new `loader/style.mbt`; the style→backend mapping in `emit`. Rich text
  and column/row default styles remain (Phase 4 items 4–5). 67 tests green.

- **2026-07-23** — **Roadmap tidy: scope audited against the backend, gaps
  captured.** Cross-checked the full `mbtexcel` surface against the phases and
  slotted the missing features in: **Phase 4** — rich text, column/row default
  styles, default font; **Phase 6** — column/row hide-show, outline grouping,
  and page setup for print (orientation/margins/print area/headers-footers/page
  breaks); **Phase 9** — Excel tables vs. pivot tables (split out; pivots flagged
  heaviest), auto filter, password encryption, document properties + calc mode,
  and a catch-all for niche extras (sparklines, shapes, form controls, slicers,
  sheet backgrounds, duration cells). Sharpened §2 non-goals: print *settings*
  are emittable (only rendering/printing is out), and **imperative editing**
  (insert/delete/move rows/cols) is a non-goal — a spec declares the final grid.
  No code change.

- **2026-07-23** — **Refactor pass (whole tree).** Split the 416-line `loader.mbt`
  at its natural seam: structural loading (workbook/sheets/cells + the shared
  `expect_*` helpers) stays in `loader.mbt`, and cell-value interpretation
  (scalar/expanded/typed/date/formula/error) moves to a new `loader/cell.mbt`.
  Extracted the emitter's number-format style interning into a named
  `intern_format_style` helper (ADR-004), and refreshed the `load` doc for the
  richer cell forms. No behaviour change; 60 tests green.

- **2026-07-23** — **Phase 3 complete: error literals + explicit typing.** `type`
  now covers `text`/`number`/`bool`/`date`/`error`. Explicit typing coerces the
  value to the declared type — `{ value: 42, type: text }` stores a string cell,
  `{ value: "42", type: number }` parses a numeric one, `{ value: "true", type:
  bool }` a boolean — with a diagnostic when the value can't convert. `type:
  error` holds an Excel error literal (`#DIV/0!`, `#N/A`, `#REF!`, …) validated
  against the known set. Added `CellValue::Error` and routed it through the
  emitter. **Phase 3 (rich cell values) is done; the active phase is Phase 4
  (styling).**

- **2026-07-23** — **Phase 3: formulas.** A cell may carry a `formula` —
  `C1: { formula: "=SUM(B2:B3)", value: 1650 }` — which compiles to an Excel
  `<f>` the app recomputes on open; the optional `value` is the cached result
  shown until then, and a leading `=` is accepted and stripped. Added a
  `Formula` case to the model, wired the emitter to the backend's
  `set_cell_formula`, and had the loader reject combining `formula` with `type`.
  Verified end to end: `=SUM(B2:B3)` emits `<c><f>SUM(B2:B3)</f><v>1650</v></c>`.

- **2026-07-23** — **Phase 3: dates / date-times (with a date system).** A cell
  typed `date` — `A1: { value: "2026-07-23", type: date }` (or with a time,
  `"2026-07-23 14:30:00"`) — compiles to an Excel serial with a sensible default
  date/date-time format, overridable via `format`. The workbook's date system is
  selectable with a top-level `date1904: true` (default is the 1900 system). All
  the calendar math lives in `units` (`DateTime`, `DateSystem`, `to_serial`),
  pure and independently tested against known serials, including Excel's 1900
  leap-year bug (1900-03-01 → 61, skipping the phantom serial 60); the emitter
  sets the backend's 1904 flag to match. Verified end to end: `2026-07-23
  14:30:00` → serial `46226.604…`, and a date round-trips back to `2000-01-01`.

- **2026-07-23** — **Phase 3: number formats (built-in + custom).** A cell may now
  be written in an **expanded form** — `A1: { value: 0.5, format: "0.00%" }` —
  alongside the scalar shorthand; `format` is any Excel number-format code (a
  built-in code like `0.00` or a custom one like `#,##0.00`). The model's `Cell`
  gained an optional `format`, and the emitter **interns** formats: each distinct
  code becomes one style id reused by every cell that names it, the first
  instance of the reuse machinery (ADR-004). Verified end to end — the format is
  applied on read-back (`0.5` → `50.00%`) and equal codes share one style id.
  Split the roadmap item: dates/date-times (a formatted number + a date system)
  are the next Phase 3 step.

- **2026-07-23** — **Refactor pass (whole tree).** Removed the vestigial root
  `t-ujiie-g/yxl` package — the `moon new` stub and the Phase-0 backend smoke
  test, now covered by the `emit` round-trip and `cli` golden tests. Factored the
  CLI's `yxl:` message prefix into one `report` helper; adopted `guard … is
  Some(x) else …` for the argument and sheet-name checks; and scrubbed roadmap
  phase/section codes from comments (keeping stable `ADR-nnn` references). No
  behaviour change; 35 tests green.

- **2026-07-23** — **Phase 2 complete: the `yxl build` CLI (walking skeleton).**
  Added the `cli` library (I/O-free: argument parsing → a `Command`, and
  `compile`, the whole parse→load→emit pipeline as source → `.xlsx` bytes) and a
  thin `cmd/main` native executable that reads the spec, compiles it, writes the
  workbook, and maps failures to stable exit codes (0 ok · 1 spec/emit/IO error ·
  2 usage) — the only place with filesystem access and process exit (ADR-003).
  Added `moonbitlang/x` for `x/fs`/`x/sys` (ADR-011). A **golden test** compiles a
  spec, re-opens the bytes with the backend reader, and asserts the cells across
  text/number/bool (quoted `"007"` stays text). `yxl build report.yxl.yaml -o
  report.xlsx` now produces a real, valid workbook end to end. **Phase 2 done;
  the active phase is Phase 3 (rich cell values).**

- **2026-07-23** — **Phase 2: the `loader` (spec → model).** Added the `loader`
  package: it interprets the minimal schema — a top-level `sheets` sequence, each
  sheet a `name` plus an optional `cells` mapping of A1 reference → scalar — and
  builds a `model.Workbook`, failing fast (ADR-006) on unknown keys, wrong types,
  invalid cell references, and duplicate sheet names as `@diag.SchemaError`s that
  name the file. Extended `model.CellValue` and the `emit` backend with `Bool`
  cells, and added `units.CellRef::parse_a1` (the validated inverse of `to_a1`).
  The `model → .xlsx` path now covers text, number, and boolean cells end to end.

- **2026-07-23** — **Phase 2: the `yaml` parser seam.** Added
  `moonbit-community/yaml@0.0.6` and the `yaml` package, which turns YAML source
  into our own `Node` tree (`Str`/`Int`/`Float`/`Bool`/`Null`/`Seq`/`Map`) behind
  a seam, so the pipeline never touches the parser directly. Scalars arrive
  already classified — a bare `1` is `Int`, a quoted `"1"` is `Str` — which is
  exactly the text-vs-number distinction the loader needs. Syntax errors and
  unrepresentable values become `@diag.YamlError`s that name the file.
  **Correction to ADR-009:** the library's span-carrying event API is a *sealed*
  trait we cannot implement, and its value tree has no positions, so per-node
  source spans are deferred to Phase 8 (rich diagnostics) — recorded as ADR-010;
  the seam keeps that future swap local.

- **2026-07-23** — **Phase 1 complete: YAML parser chosen (ADR-009).** Picked
  `moonbit-community/yaml@0.0.6` — a pure-MoonBit, libyaml/PyYAML-style event
  parser with `Marker` (line/col) spans, anchor/alias support, and `ToJson`, and
  no native FFI — to be consumed behind the `yaml` seam. Rejected the official
  YAML-org `ingydotnet/*` loaders (native `libyamlscript` FFI, at odds with the
  self-contained native CLI of ADR-003) and a hand-rolled `@json` subset. The
  `moon add` and the seam itself land in Phase 2, where the parser is first used.
  **Phase 1 (foundations: `diag`, `units`, `model`, the emitter seam, and the
  parser decision) is done; the active phase is now Phase 2 (YAML → a sheet of
  values).**

- **2026-07-23** — **Phase 1: emitter seam + minimal model + `units`.** Added the
  first end-to-end `model → bytes` path. `units` holds the type-safe `CellRef`
  (1-based col/row, bijective base-26 `to_a1`, e.g. col 703 → `AAA`), keeping
  cell refs off bare strings (AGENTS §7). `model` is the shared IR — `Workbook` /
  `Sheet` / `Cell` / `CellValue` (`Text` | `Number`) with a small mutable builder
  (`Workbook::new`/`add_sheet`, `Sheet::set`) whose returned sheet shares
  workbook storage; it imports only `units`, never the backend. `emit` defines
  the `Emitter` seam (`model → bytes`, ADR-002) with the sole `bobzhang/mbtexcel`
  implementation (`MbtexcelEmitter`) behind it and a `to_bytes` convenience;
  backend `XlsxError`s are translated to `@diag.EmitError` so the backend never
  leaks past the seam. A golden round-trip test compiles a model to real `.xlsx`
  bytes and re-opens them with the backend reader to assert the cells survived.

- **2026-07-23** — **Phase 1: `diag` package (source spans + subdomain
  errors).** Added `src/diag`, the lowest package (core-only), with `Pos`
  (1-based line/col), `Span` (file + start/end, with a `point` helper and a
  `file:line:col` `render`), and `Diagnostic` (message + optional span, rendering
  as `file:line:col: message`). Defined the five `pub(all) suberror` types —
  `YamlError` / `SchemaError` / `ResolveError` / `EmitError` / `CliError`, one
  per pipeline stage — each wrapping a `Diagnostic` so every stage fails with the
  same source-located shape and a `catch` can tell stages apart (ADR-006, AGENTS
  §7). Covered by unit tests for each render path plus raise/catch round-trips.

- **2026-07-23** — **Phase 1 started: `src/` layout (ADR-008).** Moved the flat
  `moon new` scaffold under `src/` and set `source = "src"` in `moon.mod`, so the
  §4 package map (`diag`, `units`, `yaml`, `model`, `loader`, `resolve`, `emit`,
  and the `cmd/main` CLI) has a home as those packages land. The scaffold package
  and its Phase-0 backend smoke test now live at `src/`; the CLI entry moved to
  `src/cmd/main`. Run it with `moon run src/cmd/main` (AGENTS.md §5 updated).
  Renames preserved history; no `.mbti` drift; the full native validation loop
  (`check`/`test`/`fmt`/`info`/`build`) stays green.

- **2026-07-23** — **Phase 0 complete.** Scaffolded `t-ujiie-g/yxl` from
  `moon new`, set `preferred_target = native`, and established the project
  foundation: this `ROADMAP.md`, `AGENTS.md` (with `CLAUDE.md` symlink), README,
  `.githooks/` (`moon check && moon fmt`), `.claude/` plugin config
  (`moonbit-skills`), and `.gitignore`. Added the `bobzhang/mbtexcel@0.1.8`
  dependency (ADR-001), a CI workflow (`check` / `fmt --check` / `.mbti` drift /
  `test` + `build` on native), and an end-to-end smoke test — `mbtexcel` builds
  a workbook and emits `.xlsx` bytes (verified `PK` ZIP magic) on native (in
  fact all backends passed). Direction set: a YAML→`.xlsx` compiler + native CLI
  on `mbtexcel` behind an emitter seam (ADR-002). **The active phase is now
  Phase 1 (foundations: seam, model, diagnostics).**

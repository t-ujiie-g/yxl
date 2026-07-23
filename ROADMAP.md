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
- **Rendering / printing / a GUI.** Text in, `.xlsx` out.
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
- [ ] `cli`: `yxl build <in.yaml> -o <out.xlsx>` (native), exit codes
- [ ] Golden test: spec → bytes → re-open → assert cells

### Phase 3 — Rich cell values
- [ ] Dates / date-times (with a date system), number formats (built-in + custom)
- [ ] Formulas (emit `<f>`; Excel computes on open) with optional cached value
- [ ] Booleans, error literals, explicit typing

### Phase 4 — Styling
- [ ] Named styles: font (bold/italic/size/name/color), fill, border, alignment
- [ ] Number format as part of a style
- [ ] Style **reuse** → a single interned style id per distinct style

### Phase 5 — Reuse / dedup engine ("compression") — the differentiator
- [ ] Named definitions for values, formulas, and styles (declare once)
- [ ] Reference syntax (YAML anchors `&`/`*` and/or explicit `$ref` — §8 Q3)
- [ ] Compile references to Excel-native sharing: shared strings, **defined
      names**, **shared formulas**, shared style ids
- [ ] Diagnostics for dangling / cyclic references

### Phase 6 — Layout & structure
- [ ] Merged cells, column widths, row heights
- [ ] Multiple sheets: order, active sheet, visibility (hidden/very-hidden)
- [ ] Freeze / split panes, gridlines, tab color

### Phase 7 — Modular specs
- [ ] Includes / data–format separation (`!include`, external data files)
- [ ] External data sources (CSV/JSON tables feeding a sheet region)
- [ ] Lightweight templating / parameterization

### Phase 8 — CLI UX
- [ ] Rich diagnostics rendered with file/line/col and carets
- [ ] `--check` (validate only), `--watch`, stdin/stdout, `--version`, help
- [ ] Stable exit codes; native binary packaging + install docs

### Phase 9 — Richer Excel features (leverage mbtexcel, additive)
- [ ] Charts, images, tables
- [ ] Data validation, conditional formatting, hyperlinks, comments
- [ ] Sheet / workbook protection

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

## 8. Open questions

- **Q1 — YAML parser.** ✅ **Decided (ADR-009), refined (ADR-010):** depend on
  `moonbit-community/yaml@0.0.6` (pure MoonBit, no native FFI), consumed behind
  the `yaml` seam. Its span-carrying event API turned out to be a sealed trait, so
  per-node spans are deferred to Phase 8 (ADR-010); the seam keeps that swap
  local. `moon add` + seam landed in Phase 2.
- **Q2 — Schema altitude.** How close should the schema mirror Excel's structure
  vs. a higher-level ergonomic DSL (e.g. `table:` shorthands)? Start close to
  Excel, add sugar later.
- **Q3 — Reference syntax.** YAML anchors/aliases (`&name` / `*name`), an
  explicit `$ref` / named-section scheme, or both? Affects the reuse UX.
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

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
  code review, blame, CI. *Partly delivered:* a `cells:` mapping is keyed by A1
  address, so inserting a row rewrites every key below it and the diff looks
  total. External `data:` tables already escape that; diff-stable **inline**
  tables are Phase 11.
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

**The direction matters.** `yxl` *generates* workbooks: reports, statements,
templates, anything whose shape is decided by its author and whose numbers come
from somewhere else. It does not fit the other common case, where a spreadsheet
*is* the human input surface and the file is the source of truth — there, edits
happen in Excel and a spec would be perpetually stale. Saying so up front (in
the README too) costs nothing and saves a mismatch later; `yxl import` (Phase
10) is the bridge *into* the model, not a promise to keep both sides in step.

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
- **Watching files (`--watch`).** Decided out of scope 2026-07-26: a build is a
  single command, and a caller that wants rebuilds on change already has `make`,
  `entr`, or an editor task. (It was also unimplementable without adding a timer
  dependency — but the scope call stands independently of that.)
- **Being a general xlsx library.** That is `mbtexcel`; `yxl` depends on it.
- **Continuous xlsx ⇄ YAML round-tripping.** Keeping a spec and a
  human-edited workbook in step, in both directions, is not a goal: the two
  drift the moment someone types in Excel, and reconciling them is a different
  product. A **one-time import** (existing workbook → a skeleton spec, to get
  started) is a different thing and *is* planned — §6 Phase 10, §8 Q5.

## 3. Design principles

1. **Declarative & deterministic.** The same spec always produces the same
   workbook; no hidden state, stable ordering.
2. **Reuse is first-class.** Named definitions compile to Excel's native sharing
   mechanisms — never N copies of one declared thing. (ADR-004)
3. **Fail fast, explain well.** Invalid or ambiguous input is a diagnostic with
   file/line context, never a silent drop or a guess. (ADR-006)
4. **Backend behind a seam.** Model → bytes goes through one emitter interface,
   so the Excel backend is swappable and the core stays testable. (ADR-002)
5. **Core is I/O-free; the CLI does I/O.** `model` / `loader` / `emit` work on
   strings and bytes; filesystem access lives only in `cli`. Reading an
   `$include` or a `data:` table goes through a resolver the CLI supplies.
   (ADR-003, ADR-014)
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
| `loader` | Document tree → `model`; schema validation with diagnostics; expands `$include` through a reader the CLI injects (ADR-014) |
| ~~`resolve`~~ | **Never built.** Reference resolution fitted in `loader` and interning in `emit`, so ADR-012/ADR-013 folded this package away rather than add a stage with nothing of its own to do |
| `emit` | `model` → `.xlsx` bytes through the emitter seam; the `mbtexcel`-backed implementation lives here |
| `cli` (`cmd/main`) | Argument parsing, file read/write, `--check`, `--set`, exit codes, help |
| `examples` | No product code: the tier-2 test that compiles the `examples/` cookbook and asserts on its output (§5) |

## 5. Verification tiers

- **Tier 1 — In-repo MoonBit tests** (native). Unit + golden + round-trip tests.
  The bar for every phase. The compiler core is I/O-free so it tests on strings
  and bytes.
- **Tier 2 — Example specs** (CI). The `examples/` corpus is the cookbook, and
  it is tested twice over. `src/examples` compiles every `examples/*.yxl.yaml`
  in-process, re-opens the workbook, and asserts named cells hold what the
  example's comments claim — plus a coverage check both ways, so an example with
  no assertions, or an assertion naming a spec that is gone, fails. CI then runs
  the **shipped binary** over the same files, which is what exercises the on-disk
  include/data path resolution and the real exit codes.
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
- [x] Includes / data–format separation — `{ $include: path }` wherever a node
      may stand, resolved through a reader the CLI injects (ADR-014). A YAML
      `!include` tag is **not** possible: the parser drops unknown tags silently
- [x] External data sources — a sheet `data:` list anchors a CSV or JSON table
      at a cell; fields become ordinary cells, styled by the existing
      `columns:` / `rows:` bands rather than by the data block
- [x] Lightweight templating / parameterization — style `extends:` (a definition
      referencing another) and a top-level `params:` block substituted as
      `${name}`, overridable with the CLI's `--set` (ADR-015). **Cyclic-reference
      detection** (deferred from Phase 5) landed with both

### Phase 8 — CLI UX
- [x] Diagnostics rendered with file/line/col and carets, **for YAML syntax
      errors** — the library's `YamlError` carries `mark` and `info`, now
      destructured into a real `Span`; `Diagnostic::render_in` quotes the line
      and points a caret. Schema errors name the file and the construct
      (`cell 'A1'`, `column 'B'`) but no line: **decided out of scope**
      (ADR-016), since per-node provenance would mean vendoring or replacing the
      parser
- [x] `--check` (validate only), `--version`, help
- [x] Stable exit codes (0 / 1 / 2, documented in `yxl help` and the README, and
      exercised end-to-end); native binary build + install docs
- [x] **A Windows binary.** Releases ship Linux x86_64, macOS arm64, and
      Windows x86_64 (a `.zip` with `yxl.exe`), installed by `install.ps1`. The
      unknowns were settled by running them on `windows-latest` rather than
      reasoning about them: the native backend builds (gcc and clang are
      preinstalled — no MSVC setup), the artifact sits at the same relative path
      as everywhere else, and the whole suite passes. Path resolution now takes
      either separator. CI covers all three platforms.

### Phase 9 — Richer Excel features (leverage mbtexcel, additive)
The items here are independent, so they land in whatever order pays best rather
than top to bottom, in **two slices**.

The **first slice is complete**. It deliberately began with everything that
needs *no new architecture* — no drawing parts, no binary assets, no reader
seam — which is why validation, filters, and links arrived before charts, and
why images (which forced a second resolver) came late.

The **second slice** is what used to sit here as a single unnamed line, "extras
as demand warrants". Every one of them is now named and scoped below, and all
six are wanted rather than optional.

#### First slice — landed

- [x] **Excel tables** (structured tables / ListObjects, `add_table`) —
      `tables:` over a range whose top row names the columns, with a name
      formulas can use, one of Excel's built-in styles, and its four appearance
      toggles. Everything Excel would repair or refuse is a diagnostic first: a
      duplicate or malformed name, a header cell that is empty or not text, two
      tables sharing a cell, and a table overlapping the sheet's own `filter:`.
      Deferred: a table with its header row turned off (the backend drops the
      range's first row for one, excelize parity, so a spec's `at` and the
      emitted range would disagree), totals rows, and per-column formulas
- [x] **Charts** — `charts:` anchored at a cell, with fourteen kinds (column /
      bar / line / area and their stacked forms, pie, doughnut, scatter, radar),
      one or more series whose ranges may name another sheet, a series name
      written out *or* read from a cell, a title, legend placement, a size in
      pixels, and per-axis title and bounds. Ranges are emitted the way Excel
      stores them, sheet-qualified and absolute. Deferred: 3-D variants, stock
      and bubble charts (each wants an extra range or a shape the spec cannot
      describe), combo charts, per-series colors and markers, and chart sheets
- [x] **Images** — `images:` anchored at a cell, with alt text, a scale, an
      offset in pixels, and Excel's three anchor kinds. The first thing in this
      phase that is not just schema: a spec names a file it cannot hold as text,
      so the loader gained a second resolver (`BytesResolver`) beside the one
      `$include` uses, and the CLI supplies both. Deferred: a hyperlink on an
      image, cell-embedded ("place in cell") images, and shapes
- [x] **Pivot tables** (`add_pivot_table`) — `pivots:` over a source region whose
      header row names the fields, laid out across `rows` / `columns` / `values`
      / `filters`, with all eleven of Excel's aggregations, a display name per
      field, one of its built-in styles, and either grand total. The file
      carries the definition and an empty cache marked "refresh on load", so
      Excel builds the summary on open. **Two backend defects bound what is
      accepted** (reported upstream, and §9): no `filters:` axis, and one source
      per workbook. Deferred: number formats per value field, sorting and manual
      field order, calculated fields, classic layout, and a pivot sourced from
      an Excel table rather than a range
- [x] **Data validation** — drop-downs (inline choices or sourced from cells,
      including another sheet), and `whole` / `decimal` / `text_length` / `date`
      comparisons across all eight OOXML operators, with Excel's "Ignore blank",
      input prompt, and error dialog. A bound is typed (`Number` or a `DateTime`
      whose serial the emitter computes), never a bare string
- [x] **Hyperlinks** — out of the workbook (`url`) or into it (`to`), with a
      tooltip. A link decorates a cell; it never supplies its text
- [x] **Conditional formatting** — `cell` comparisons (the same eight a
      validation spells, shared code and shared vocabulary), `formula`, `text`,
      `top`/`bottom` by count or percentage, `duplicate`/`unique`, two- and
      three-stop color scales, data bars, and all twenty of Excel's icon sets.
      Looks are interned into Excel's *differential* format table, so a look ten
      rules share is stored once (ADR-004). Deferred, as demand warrants: time
      periods (`today`, `last week`), above/below average, blanks/errors, and
      per-stop control of where a scale or bar anchors its endpoints
- [x] **Comments (notes)** — the last of the range-keyed group. `comments:`
      takes the text on its own or `{ text, author }`
- [x] Auto filter (`set_auto_filter`) — `filter: <range>`. Per-column criteria
      are deferred: the backend takes them as its own little expression language
      (`x > 5`), and passing that through unvalidated would turn a typo into a
      backend `EmitError` instead of a diagnostic (ADR-006). They need a
      structured schema that compiles *to* those strings inside `emit`
- [x] **Sheet / workbook protection** — `protect:` at both levels, plus
      `protection: { locked, hidden }` in a style, without which protection
      cannot leave a form's input cells editable. Excel's own defaults apply,
      and a misspelt allowance is a diagnostic. **The workbook half was
      re-refused 2026-07-27**: the first Tier-3 check to reach it showed Excel
      reporting the file corrupt — the backend writes `<workbookProtection>`
      out of schema order (§9) — so top-level `protect:` is now a named
      refusal until the upstream fix; the sheet half is unaffected. **File encryption**
      (`write_with_password`) is *not* included: it changes the emitter's
      signature and needs the CLI to carry a secret, which wants its own
      decision — a protection password is only anti-accident, and the spec says
      so plainly
- [x] **Workbook metadata**: document properties (title, subject, author,
      keywords, description, category, status, language, version, company) and
      properties of the author's own devising under `custom:`, plus the
      calculation mode and a forced recalculation on open. A custom value keeps
      its YAML type, and a whole number reaches the file as an integer. Excel's
      *date* custom-property type is deliberately not exposed: it wants a full
      timestamp with a zone, which a bare date would have to guess at (ADR-006)
#### Second slice — the rest of what `mbtexcel` can draw

Ordered by what pays first: the two that reuse machinery already here, then the
two that write a part of their own, then the two with the largest vocabulary or
the most Excel verification to do. Each is independent of the others.

Every one of these writes a part Excel *interprets* rather than displays, so
each carries the obligation the pivot tables earned (§9): **open the output in
Excel by hand** before ticking the box, not only round-trip it.

- [x] **Shapes** (`add_shape`) — a geometry floating over the grid, optionally
      carrying text. `shapes:` anchored at a cell, with a named preset
      geometry, a pixel size, fill and line colour, plain text or a list of
      lines each in its own font (the backend writes one paragraph per run, so
      one font covers one line), alt text, and the three anchor kinds images
      spell. The anticipated design point — the backend puts `shape_type`
      straight into `prst=` unchecked — turned out a step worse: it also
      **lowercases the token**, and `ST_ShapeType` is case-sensitive, so
      `roundRect` reaches the file as a geometry Excel does not recognize. The
      accepted subset is therefore the ~23 presets whose token has no capitals
      (rectangle, ellipse, the polygons, star_5, plus, chevron, cloud, …), a
      test pins that invariant, and the camel-case kinds an author will reach
      for — the rounded rectangle, right triangle, the eight arrows, the four
      callouts — are refused *by name* with the reason, the pivots-`filters:`
      arrangement (recorded in §9 pending an upstream report). Not available
      from the backend:
      an `offset` (its shape constructor takes none, unlike pictures) and a
      `scale` (dropped deliberately — a shape has no natural size to scale;
      `size` says it directly). `macro_name` stays out: `.xlsx` carries no
      macros, and VBA is a §2 non-goal
- [x] **Duration cells** — an elapsed time (`26:30:00`, "26 hours 30 minutes"),
      which Excel stores as a fraction of a day under an `[h]:mm:ss` format and
      is *not* a time of day. The smallest item here, and it landed as sized:
      a `type: duration` beside `type: date`, `H:MM[:SS]` parsed by a
      `units.Duration` (hours unbounded, minutes and seconds 0–59, no
      negatives — the 1900 system cannot display one) whose serial the loader
      computes, so the model carries an ordinary `Number` and the emitter
      never knew the feature arrived. `Workbook::set_cell_duration` exists but
      takes a `@time.Duration`; computing the serial ourselves keeps
      `moonbitlang/x/time` out of the model and matches how dates already
      work. The golden test proves the backend renders `[h]:mm:ss` past 24
      (`1.5` displays as `36:00:00`)
- [x] **Sheet backgrounds** (`set_sheet_background`) — a watermark image tiled
      behind a sheet's cells. Reused the `BytesResolver` seam and the format
      list images already brought, so it was `background: logo.png` on a sheet
      and little else, exactly as sized: one model struct, one loader function
      sharing the images' format/emptiness diagnostics, one emitter line. The
      backend validates the extension against the same thirteen formats and
      its reader hands the background back (`Worksheet::sheet_background`), so
      the round trip asserts bytes, extension, and content type. The docs say
      what surprises people: Excel shows a background on screen and never
      prints it
- [x] **Sparklines** (`add_sparkline`) — a chart inside one cell, for a row of
      figures beside it. Line, column, and win/loss; per group the cells
      plotted and where each lands (`at`/`data` for one, `cells:` for
      several), the high/low/every-point markers, manual bounds, line weight,
      and the colours those marks can show. Written as an `x14` extension, and
      the emitted extension list was verified against the part, not just
      round-tripped: the `{05C60535-…}` URI, the namespaces, win/loss spelled
      `stacked`, and the sheet-qualified `<xm:f>` are all as ECMA-376 Part 4
      §2.9 wants them. Two backend gaps bound the schema: the *first*, *last*,
      and *negative* markers are options nothing can set (refused by name with
      the reason), and `manualMin`/`manualMax` are written without
      `minAxisType`/`maxAxisType="custom"` — whether Excel honours them anyway
      is what the manual check watches
- [x] **Form controls** (`add_form_control`) — a button, check box, option
      button, scroll bar, spin button, group box, or label sitting over the
      grid, linked to a cell. The value a control writes into its `cell_link`
      is what makes a sheet a form, which is the same story `protection:
      { locked: false }` already tells. The largest vocabulary here, and the
      loader enforces it kind by kind: each key is admitted only where Excel's
      own "Format Control" dialog shows it, values keep to the dialog's
      0–30000, `page` is the scroll bar's alone, and a misplaced key is a
      diagnostic naming where it belongs. A `link` is a same-sheet cell — the
      backend refuses a qualified reference. Again no `macro_name`: a button
      without a macro is a caption that clicks, and assigning behavior is
      Excel's side of the contract. One reader note: a control's size lands in
      the VML anchor, which the backend does not translate back — the manual
      check is what sees it
- [ ] **Slicers** (`add_slicer`) — the button panel that filters an Excel table
      (`SlicerOptions::new(name, cell, table_sheet, table_name)`), with a
      caption, size, and header. **Last on purpose**: it is the only item that
      depends on another feature of ours (`tables:`), it writes several linked
      parts, and slicers over *pivot* tables touch the same cache machinery that
      [office.mbt#264](https://github.com/moonbitlang/office.mbt/issues/264)
      showed to be fragile. Start with table slicers; treat pivot slicers as a
      separate decision once #264 is answered

#### Not scheduled

Sub-features the first slice consciously left out, gathered here so they are
visible rather than buried in the prose above. Each is a small addition to a
feature that already works, and any can be pulled forward on request — none is a
gate, which is why none carries a box:

- per-column auto-filter criteria — needs a structured schema that compiles
  *to* the backend's little expression language, rather than passing a typo
  through as an `EmitError` (ADR-006)
- table totals rows, per-column formulas, and header-row-off tables — the
  backend drops the range's first row for the last of these
- chart 3-D variants, stock and bubble charts, combo charts, per-series colours
  and markers, and chart sheets
- conditional-format time periods (`today`, `last week`), above/below average,
  blanks/errors, and per-stop anchoring for colour scales and data bars
- pivot number formats per value field, sorting and manual field order,
  calculated fields, and classic layout
- a hyperlink on an image, and cell-embedded ("place in cell") images
- **pivot `filters:`, and more than one pivot source per workbook** — blocked on
  [office.mbt#264](https://github.com/moonbitlang/office.mbt/issues/264) rather
  than on us; both become schema changes the day it is fixed
- **shape geometries whose DrawingML token carries a capital** — the rounded
  rectangle, right triangle, the eight straight arrows, and the four callouts —
  blocked on the backend lowercasing `prst` (§9); each becomes one more row in
  the preset table the day it keeps the token's case
- file encryption (`write_with_password`) — its own decision: it changes the
  emitter's signature and needs the CLI to carry a secret

### Phase 10 — Performance & scale, and import
- [ ] Large-spec performance; streaming where `mbtexcel` supports it
- [ ] Benchmarks + regression guardrails in CI
- [ ] **Import: an existing `.xlsx` → a skeleton spec.** Promoted from a
      post-v1 stretch to a wanted feature (§8 Q5). Framed as a **one-way,
      one-time migration aid**, not a round-trip contract: lossy and irreversible
      is acceptable, which is exactly what makes it cheap enough to be worth
      building. It is the single biggest lowering of the barrier to adoption —
      an existing workbook becomes a starting spec instead of a retyping job.
      Open first: the command's **name** (it emits YAML, so `import` reads from
      yxl's side but not the file's — §8 Q9), and how much it recovers (values
      and formulas certainly; styles interned into `defs.styles`; merges,
      widths, and print setup if cheap). Needs a *reader* seam mirroring ADR-002,
      since it is the first code outside `emit` to touch the backend.

### Phase 11 — Authoring ergonomics (added after the v0.1.0 review, §11)
These sharpen what §1 already claims, so they land **before the schema freeze**;
the first item changes what a spec looks like.
- [ ] **Diff-stable tables.** A `cells:` mapping is keyed by A1 address, so
      inserting a row rewrites every key below it — `git diff` reports the whole
      block as changed, which undercuts the "diffable" headline. Fix by letting a
      `data:` entry carry its rows **inline** rather than only from a file:
      `- { at: A2, values: [[APAC, 2400000], [EMEA, 1750000]] }`. A row insert is
      then a one-line diff, the anchor localizes addresses to one place, and it
      reuses the anchored-table machinery `csv:`/`json:` already go through
      instead of inventing a second concept. `cells:` stays for scattered,
      individually-styled cells, which is what it is good at.
- [ ] **A JSON Schema for the spec, generated from `docs/spec.md`'s contents.**
      Publishing one lets an author write
      `# yaml-language-server: $schema=…` and get completion and validation in
      VS Code — a large ergonomic return for a small artifact. Generating it
      *from* the reference (or checking the two agree in CI) is what stops the
      pair drifting, which is the same trick `examples/` plays for the cookbook.

### v1.0 — Stability gate
- [ ] Schema freeze (breaking budget spent here). The **spec reference** it
      freezes is written: [`docs/spec.md`](./docs/spec.md)
- [x] Stand up Tier 2: an `examples/` corpus that CI compiles and asserts on
      (§5), which is also what stops the README and cookbook drifting
- [ ] Tier-3 manual: Excel / LibreOffice / Google Sheets open cleanly — and
      *automate the cheap half of it first*: a workbook that makes Excel show its
      repair dialog is the classic way an xlsx writer fails, and nothing in CI
      would currently catch it. Opening every `examples/` output with LibreOffice
      headless, or reading it back with `openpyxl`, would (post-v0.1.0 review,
      §11)
- [ ] Cookbook + CLI docs complete — `examples/` and `docs/spec.md` exist and CI
      keeps them honest; what remains is filling them out as Phase 9 lands
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

### ADR-014 — Includes are `{ $include: path }`, resolved through an injected reader
**Status:** Accepted.
**Context:** Phase 7 needs a data/format split (§8 Q4, ADR-005). The obvious
spelling is YAML's own `!include` tag — but the parser seam cannot see tags. The
library's tag-carrying API is its `MarkedEventReceiver` event stream, whose
trait is **sealed** (`pub trait`, not `pub(open)`), so we cannot implement a
receiver (this is the same wall ADR-010 hit for source spans); the value-tree API
we do use (`Yaml::load_from_string`) drops unknown tags silently. Verified: a
spec containing `A1: !include x.yaml` compiles *successfully* with the cell set
to the text `"x.yaml"`. A directive that degrades into a plain string on a typo
is exactly what ADR-006 forbids.
**Decision:** An include is a **single-key mapping** `{ $include: <path> }`,
usable wherever a node may stand (a whole document, one sheet, a `cells:` block,
a `defs.styles` map). `$` marks it as a directive rather than spec data, matching
`$ref` (ADR-012). Expansion is a pre-pass over the document tree, so every
schema reader below is unaware more than one file existed. Combining `$include`
with sibling keys is a diagnostic rather than an implied merge — that keeps merge
semantics available to define later.
**Reading the files stays outside the core (ADR-003):** `load` takes an
`IncludeResolver` — `(from, path) -> Included { name, source }` — that the CLI
supplies from the filesystem and tests supply from a map. The resolver returns
the *name* it opened, so a diagnostic inside an included file points at that
file and nested relative includes resolve against the right directory. Include
**cycles are detected during expansion** and reported with the whole chain
(`a.yaml -> b.yaml -> a.yaml`); this is the cycle detection Phase 5 deferred,
arriving with the first construct that can actually form a loop.
**Trade-offs / consequences:** `load` now raises `Error` rather than only
`@diag.SchemaError`, because a syntax error in an included file is a genuine
`@diag.YamlError` — the alternative was relabelling syntax errors as schema
errors, which would lie about the kind. The path is resolver-defined: the CLI
treats it as relative to the including file, so a spec directory can be moved
wholesale. Should the parser ever gain an open event API, `!include` could be
added as sugar over the same expansion, but `$include` stays the contract.

### ADR-015 — Parameters are `${name}`; a lone placeholder keeps its type
**Status:** Accepted.
**Context:** Phase 7 wants one spec to build many workbooks. The project's other
directives are single-key mappings (`$ref`, `$include`), but a parameter's main
use — composing a sheet name or a title out of parts (`"${quarter} ${region}"`)
— cannot be expressed by substituting a whole node.
**Decision:** A top-level `params:` block declares names with defaults;
`${name}` inside **any string** substitutes one, in mapping keys as well as
values, so a cell reference or a sheet name may be parameterized. Substitution
is a pre-pass over the document tree (after include expansion, so included files
see the parameters), leaving the schema readers below unaware parameters exist.
A default may itself use `${other}`; that makes cycles possible, and they are
detected and reported with the chain.

Two rules make the mechanism carry types rather than only text:
- A string that is **exactly one placeholder** takes the parameter's own type,
  so `B1: "${rate}"` is a number cell, not the text `0.08`.
- A `--set` value arrives from a command line as text and is read as **the
  scalar it looks like** — the same inference CSV fields get, since neither
  carries types. Without this, `--set rate=0.15` would silently turn a number
  cell into a text one.

**Trade-offs / consequences:** `$$` is a literal `$`, and a `$` beginning
neither escape is itself, which leaves Excel's absolute references (`$A$1`)
untouched. The two meanings collide only when a literal `$` *immediately*
precedes a placeholder: `$B$${n}` reads its middle `$$` as the escape, and the
author writes `$B$$${n}` instead. The substitution pass runs **even when no
parameters are declared**, so a stray `${nope}` is a diagnostic rather than a
literal reaching a cell (ADR-006) — a spec that wants a literal `${` writes
`$${`. Setting a name the spec does not declare is likewise an error, so a typo
on the command line says so instead of quietly doing nothing.

### ADR-016 — Schema diagnostics name the file and the construct, not the line
**Status:** Accepted. (Closes the deferral ADR-010 left to Phase 8; does not
supersede it — its analysis of the parser still holds.)
**Context:** ADR-010 deferred per-node source spans on the grounds that "rich
file/line/col diagnostics are a Phase 8 deliverable". Phase 8 arrived. Syntax
errors turned out to be fixable cheaply — the library's `YamlError` does carry a
marker, which is now destructured into a real `Span` and rendered with a caret.
*Schema* errors are the hard half: they would need every `Node` to remember
where it came from, and the parser exposes positions only through a **sealed**
trait, so that means vendoring the parser, upstreaming an open API, or writing
our own.
**Decision:** Do none of those. A schema diagnostic names the file and the
construct it is about — `cell 'A1'`, `column 'B'`, `sheet 'Sales'`, `parameter
'region'` — which in a structured document locates the problem about as well as
a line number would, and the messages say what was expected. The cost of the
alternatives is a parser fork to maintain, for a strictly cosmetic gain.
**Consequences:** the `yaml` seam still keeps the swap possible, and
`@diag.Diagnostic`'s span stays optional, so if this is ever revisited the change
is additive and local. One knock-on stays documented rather than fixed: an
external `data:` path resolves against the spec passed to `yxl build` rather than
the file the entry was written in (it fails loudly with the path it tried, never
silently reading the wrong file).

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
- **Q4 — Data/format split mechanism.** ✅ **Decided (ADR-014):**
  `{ $include: path }`, usable wherever a node may stand, resolved through an
  `IncludeResolver` the CLI injects so the core stays I/O-free (ADR-003). A YAML
  `!include` tag was ruled out on evidence — the parser's tag-carrying API is a
  sealed trait and its value tree drops tags silently, so a typo would compile to
  a plain string instead of failing (ADR-006). Because an include can replace any
  node, a `data:` / `format:` split needs no separate mechanism. External CSV/JSON
  tables remain their own Phase 7 item.
- **Q5 — Reverse import.** ✅ **Decided 2026-07-26: in scope, as a one-way
  import.** Wanted after the v0.1.0 review: an existing workbook becomes a
  starting spec instead of a retyping job, which is the biggest single drop in
  the barrier to adoption. Explicitly *not* a round-trip contract — lossy and
  irreversible is fine for a migration aid (§2, §6 Phase 10). What it recovers,
  and what it is called, are Q9.
- **Q10 — Non-ASCII on the Windows command line.** ✅ **Decided 2026-07-26:
  document it.** `moonbitlang/x/sys` reads argv as UTF-8 ("TODO: Handle other
  encodings") while Windows supplies it in the system code page, so
  `yxl build 売上\report.yaml` cannot work — the characters are already lost
  before yxl sees them. Fixing it here means our first FFI (`GetCommandLineW` +
  `CommandLineToArgvW`), Windows-only, for a problem upstream has already
  identified as theirs. Paths *inside* a spec are unaffected, which covers the
  case that matters: name the spec you type in ASCII, and everything it refers to
  can be in any script. README and `docs/spec.md` say so. Revisit if upstream
  stalls and real users hit it.

- **Q9 — What is the import command called, and how much does it recover?**
  `import` reads naturally from yxl's side ("bring this workbook in") but the
  thing it *writes* is YAML, so the word points the wrong way for anyone reading
  the command line. Candidates: `yxl import report.xlsx -o report.yxl.yaml`,
  `yxl scaffold`, `yxl extract`, `yxl decompile`, or `yxl init --from`. Scope, in
  rough order of value per effort: cell values and formulas → styles interned
  into `defs.styles` → merges, column widths, sheet visibility → print setup.
  Deciding where to stop matters more than the name: an import that recovers
  everything is a round-trip by another route, and §2 says that is not the
  product.
- **Q7 — The parser's sealed API: vendor, replace, or live with it?**
  ✅ **Decided (ADR-016): live with it.** The YAML parser's value tree carries no
  positions and its marker-carrying event API is a sealed trait (ADR-010), so
  schema diagnostics name the file and the construct but not a line, and a
  `data:` path resolves against the root spec rather than the file it was
  written in. Vendoring or replacing the parser buys a line number for messages
  that already name what they are about; not worth it before v1.0. Revisit only
  if real use shows the file-plus-construct form is not enough.
- **Q8 — stdin/stdout.** ✅ **Decided 2026-07-26: dropped, revisit on demand.**
  `-o -` would let a workbook be piped straight to an uploader or mailer, and
  `build -` would take a generated spec from a pipe. Both were dropped because
  the workaround is one line (`yxl build s.yaml -o /tmp/r.xlsx && …`), so the
  gain is convenience, not capability. Three costs stood against it: the
  toolchain exposes **no stdin and no byte-level stdout** (only `println`), so
  either half needs `moonbitlang/async` or a native FFI stub; a spec read from a
  pipe has no directory, leaving relative `$include:` / `csv:` paths with nothing
  to resolve against (a `--base-dir` or a ban); and writing a binary to stdout
  requires first moving every message to stderr, for which there is likewise no
  API (no `eprintln`). Implement if piping actually comes up — and prefer the
  `-o -` half, which carries neither the path-resolution nor the "generate the
  spec" motivation that `params:` / `--set` / `$include` / `data:` already
  cover.

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
- **A workbook Excel refuses to open cleanly.** The classic xlsx-writer failure:
  output that our own round-trip tests read back happily, and that Excel greets
  with a repair dialog. Nothing in CI would catch it — Tier 1 re-opens with the
  same library that wrote the file, which cannot disagree with itself, and Tier 3
  is manual and scheduled for the v1.0 gate. Mitigation: automate the cheap half
  (LibreOffice headless, or `openpyxl`, over the `examples/` outputs) rather than
  wait for v1.0. Raised in the post-v0.1.0 review.
- **Backend defects that only Excel reveals.** Phase 9's pivot tables shipped
  round-trip-green while Excel showed `#SPILL!`, because the backend writes a
  fixed `<location>`; a second defect gives every pivot the same `cacheId`, so a
  second source would be summarized wrongly with no error at all. Both are
  reported upstream ([office.mbt#264](https://github.com/moonbitlang/office.mbt/issues/264)) and worked around by refusing the
  spec (`docs/spec.md` §14).
  Mitigation is the one already listed below — automate "does Excel open it
  cleanly" — and, until then, **open the output by hand when a feature writes a
  part Excel interprets rather than displays**.
- **The backend writes `<workbookProtection>` out of schema order.**
  `write_workbook_xml.mbt` emits it after `</sheets>` and `definedNames`,
  while CT_Workbook (ECMA-376 §18.2) wants it *before* `bookViews` — and a
  schema violation in workbook.xml makes Excel report the whole file as
  corrupt, repair refused. Shipped broken in the first slice's protection and
  caught only when the second slice's manual-check obligation finally opened
  a workbook that used it: every Excel-opened example until then happened not
  to carry workbook-level `protect:`. Found by feature-bisecting the failing
  workbook with eleven probe files rather than re-reading code. Worked around
  by refusing top-level `protect:` by name with the reason; sheet protection
  and `locked: false` styles are unaffected and verified clean. The lesson
  already in this section stands sharper: *a feature is not done until Excel
  has opened it* — the round trip cannot catch what the reader tolerates.
- **The backend lowercases a shape's `prst` token.** `write.mbt` passes
  `shape_type` through `.to_lower()`, and DrawingML's `ST_ShapeType` enum is
  case-sensitive — `roundRect` written as `roundrect` is a geometry Excel does
  not recognize. Found in Phase 9's shapes by dumping the drawing part rather
  than trusting the round trip (the backend's own reader accepts what its
  writer produced, so tests stay green). Worked around by accepting only
  presets whose token has no capitals and refusing the rest by name; a test
  pins the no-capitals invariant. Two smaller reader defects found alongside,
  affecting only what tests can assert: a text run written with
  `xml:space="preserve"` is invisible to the reader (it splits on the literal
  `<a:t>`), and no run's font is read back. All pending an upstream report.
- **MSVC cannot compile the backend's formula evaluator.** MoonBit's native
  backend hands each test executable to the platform C compiler as one
  translation unit, and `mbtexcel`'s formula dispatch — a `match` with a
  thousand-odd arms — becomes C that MSVC refuses with `fatal error C1026:
  parser stack overflow, program too complex`. It only bites when the evaluator
  survives dead-code elimination, which happens the moment anything in a package
  reaches it, however indirectly: `Workbook::get_pictures` does, because it also
  looks for images *inside* cells. Ubuntu and macOS (clang) compile it fine, so
  this shows up as a Windows-only CI failure in a package whose own code never
  mentions formulas. Mitigation for now: prefer the backend reader that matches
  what `yxl` actually emits (`Worksheet::images()`, `Worksheet::charts()`) over
  the whole-workbook lookups. If a needed API drags the evaluator in, the escape
  hatch is `MOON_CC=clang-cl` on the Windows runner. Found in Phase 9's images.
- **A headline the schema does not earn.** §1 leads with "diffable", and a
  `cells:`-keyed spec is not, under row insertion. Mitigation: Phase 11's inline
  tables, before the schema freeze; until then §1 and the README say which half
  is delivered.

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

- **2026-07-27** — **Workbook-level `protect:` refused: it corrupted every
  file that used it.** The form-controls manual check opened the interactive
  example and Excel reported it *corrupt, repair refused* — the first
  Tier-3 look at a workbook carrying top-level `protect:`, which shipped in
  the first slice before the open-it-in-Excel obligation existed. Eleven
  probe workbooks bisected the failure feature by feature: controls,
  comments, links, validations, the filter, and sheet protection each opened
  clean alone and in pairs; the one that failed held workbook protection.
  The part told the rest: the backend writes `<workbookProtection>` after
  `</sheets>` and `definedNames`, and CT_Workbook wants it before
  `bookViews` (ECMA-376 §18.2) — a schema violation in the workbook's
  load-bearing part, which is why Excel refuses even to repair.

  So top-level `protect:` is now a **named refusal with the reason** (the
  pivots-`filters:` arrangement), documented in `docs/spec.md` §16; sheet
  protection and `locked: false` styles are untouched and verified clean.
  The interactive example drops its `structure: true`. Recorded in §9
  pending an upstream report.

- **2026-07-27** — **Form controls.** `controls:` puts a button, check box,
  option button, scroll bar, spin button, group box, or label over the grid.
  A control writes into its **linked cell** — a boolean, an option index, or
  a number — which is what formulas react to, and the other half of the story
  sheet protection tells: lock the sheet, unlock the entry cells, and let the
  controls drive the rest.

  The largest vocabulary of the slice, enforced kind by kind rather than
  pooled: `text` belongs to the captioned kinds, `checked` to the two
  tickable ones, `link` to the four that write a value, `min`/`max`/`step`/
  `value` to the two ranged ones, `page` to the scroll bar alone (a spin
  button has no trough), `horizontal` to both sliders — and a misplaced key
  is a diagnostic naming where it belongs, which is exactly what Excel's own
  "Format Control" dialog expresses by greying things out. Values keep to the
  dialog's 0–30000; `min` above `max` is refused; a `link` is a same-sheet
  cell because the backend validates it as a bare reference.

  No `macro:`, deliberately: an `.xlsx` carries no macros (§2), so a button
  without one is a caption that clicks — the spec says so rather than
  accepting a key that does nothing. The interactive example gained a
  "Rush order" check box and a priority spin button beside its form rows.

- **2026-07-27** — **Sparklines.** `sparklines:` puts a chart inside a cell —
  a line, a column per point, or win/loss — for the row of figures beside it.
  Each entry is a *group*, Excel's own unit of styling and scaling: one
  sparkline via `at`/`data`, or several via `cells:`, sharing the kind, the
  high/low/every-point markers, manual whole-number bounds, the line weight,
  and the colours those marks can show. `data` may name another declared
  sheet; naming an undeclared one is the same diagnostic a chart gets.

  The x14 extension the backend writes was **verified against the part**, per
  this item's standing instruction, not just round-tripped: the
  `{05C60535-1F16-4fd2-B633-F4F36F0B64E0}` URI, both namespaces, win/loss
  spelled `stacked`, and `<xm:f>'Data'!B2:E2</xm:f>` sheet-qualified and
  quoted as Excel writes it.

  Three backend gaps surfaced, the first two bounding the schema: the
  *first point*, *last point*, and *negative points* markers are carried as
  options nothing can set, so `first:`/`last:`/`negative:` are refused by
  name with the reason; the reader strips the sheet prefix off a read-back
  `range_ref` (tests note it; the file is right); and `manualMin`/`manualMax`
  are written without the `minAxisType`/`maxAxisType="custom"` attributes
  ECMA-376 wants beside them — whether Excel honours the bounds anyway is
  exactly what the manual check watches, and `min:`/`max:` become a refusal
  if it does not.

- **2026-07-27** — **Sheet backgrounds.** `background: assets/logo.png` on a
  sheet tiles the image behind its cells, like a watermark. The smallest kind
  of feature this project gets to land: the `BytesResolver` seam, the format
  list, and the extension/emptiness diagnostics all arrived with images, so
  this is one model struct, one loader function, and one emitter line. The
  backend reader hands the background straight back, so the round trip asserts
  bytes, extension, and content type; the layout example gained the watermark,
  and the docs say the thing that surprises people — Excel shows a background
  on screen and **never prints it**.

- **2026-07-27** — **Duration cells.** `type: duration` beside `type: date`:
  `H:MM` or `H:MM:SS`, hours unbounded — `26:30:00` is twenty-six and a half
  hours, an *elapsed* time, not a clock time. A new `units.Duration` parses it
  and renders the serial (its length as a fraction of a day, independent of
  the date system, so the loader computes it and the model carries a plain
  `Number`); without a `format:` the cell wears `[h]:mm:ss`, whose `[h]` keeps
  counting past 24 instead of rolling into days. Negative durations are not
  part of the syntax: Excel's 1900 date system cannot display one. The golden
  test shows the whole trip — `36:00:00` compiles to `1.5` and formats back as
  `36:00:00` — and the quickstart example gained an "Hours logged" row.

- **2026-07-27** — **Shapes**, opening Phase 9's second slice. `shapes:` floats
  a preset geometry over the grid at a cell, with a pixel `size`, a `fill` and
  a `line` colour (the line optionally with a width in points), `alt` text,
  and the three anchor kinds images spell. `text:` is a plain string or a list
  of lines — a *list gives one font per line*, because the backend writes each
  run as its own paragraph, and saying so in the schema is honester than
  calling it rich text.

  **The geometry table is the story.** The roadmap had anticipated validating
  `kind` against DrawingML's `ST_ShapeType` because the backend writes the
  token unchecked; dumping the emitted drawing part showed it also *lowercases*
  it, and the enum is case-sensitive — `roundRect` reaches the file as
  `roundrect`, a geometry Excel does not recognize. So the accepted table
  holds only presets whose token has no capitals — rectangle, ellipse, the
  polygons through decagon, star_5, plus, chevron, cube, can, donut, frame,
  heart, moon, sun, cloud, pie, line — a test pins the no-capitals invariant,
  and the camel-case kinds an author will reach for (the rounded rectangle,
  right triangle, eight arrows, four callouts) are refused **by name** with
  the reason, exactly as a pivot's `filters:` is. Recorded pending an
  upstream report, with two
  reader defects found alongside (§9): a run written `xml:space="preserve"`
  never reads back, and no run's font does.

  Also not in the schema, by the backend's shape: an `offset` (the shape
  constructor takes none, unlike pictures) and a `scale` (dropped on purpose —
  a shape has no natural size to scale; `size` says it directly).

  Verified in the package: `prstGeom prst="cloud"`, the solid fill, the line
  colour and width in EMU, and one `<a:p>` per text line. New
  `examples/shapes.yxl.yaml`: a cloud stamp over a report, a chevron with a
  bold headline over a plain line, a star pinned with `positioning: fixed`.
  **Awaiting the second slice's standing obligation — open the output in
  Excel by hand — before this is called fully done.**

- **2026-07-27** — **A full pass of the AGENTS.md §8 refactoring checklist**,
  behavior-preserving throughout. What it found, by lens:

  *Duplication and dead code.* The range formatter existed three times and the
  sheet lookup three times; both are now model methods (`CellRange::to_a1`,
  `Workbook::sheet`). Charts and images each validated pixels with their own
  near-copy — one `expect_pixels` (with a per-caller floor) serves both, and
  the two selector parsers share one `parse_selector`. The executable's three
  file-read diagnostics converged on one wording, and the examples corpus now
  resolves included paths with the real `@cli.resolve_path` instead of a
  POSIX-only shadow copy — so the corpus exercises the rule the CLI ships.
  `is_table_style` / `is_pivot_style` had no callers anywhere and are gone,
  as is a smoke test the golden round-trip superseded.

  *Constants.* The Excel limits that lived in the loader (drawing pixels,
  image scale, defined-name length) moved to `model` beside the seven already
  there. The protect allowances became an array serving both the lookup and
  the diagnostic (the pattern the chart/pivot/image tables set), as did the
  alignment and border-style spellings — the match arm and its "expected …"
  list can no longer drift apart. `params`/`defs` keys and the `type: date`
  default formats got named constants.

  *File boundaries.* Three splits, each along a line a sibling file had
  already drawn: `model/page.mbt` (print setup, matching `loader/page.mbt`
  and `emit/page.mbt`), `emit/conditional.mbt` (matching the loader's split,
  and giving `conditional_test.mbt` a source file), and `loader/sheet.mbt`
  (per-sheet loading and presentation, giving `sheet_test.mbt` a source file
  and leaving `loader.mbt` the document entry point).

  *Docs.* The README's pivots-example row claimed a `filters` axis the loader
  refuses by name; corrected, along with the pivot changelog lead below. The
  status blurb now names the remaining features instead of "Phase 9's second
  slice", and `yxl version` joined the command list.

  What the survey found and this pass did **not** do, recorded so it is a
  decision rather than an omission: unifying the ~60 hand-written
  "missing required key" / "unknown key … (expected …)" messages behind two
  `expect.mbt` helpers (a coherent follow-up of its own), per-source test
  files for `model/style.mbt`, `emit/style.mbt`, and `cli/path.mbt`, and a CI
  step exercising the executable's failure exit codes.

- **2026-07-27** — **Phase 9 reorganized into two slices.** The phase ended
  with one unnamed line — "further additive extras as demand warrants:
  sparklines, shapes, form controls, slicers, sheet backgrounds, duration
  cells" — which is a backlog wearing a checkbox: nothing in it could ever be
  said to be done, and a reader could not tell whether any of it was wanted.

  All six are wanted. They are now named and scoped items in a **second slice**,
  ordered by what pays first: shapes and duration cells (which reuse the image
  and cell-type machinery already here), sheet backgrounds (which reuses the
  bytes seam), sparklines, form controls, and slicers last — the only one that
  depends on another feature of ours (`tables:`) and the one whose pivot variant
  touches the cache machinery #264 showed to be fragile.

  Each item now carries what was learned looking the API up rather than a name
  alone: that `shape_type` reaches `prst=` unvalidated, so an unknown preset
  makes Excel repair the file; that a duration is a fraction of a day under an
  `[h]:mm:ss` format and can be computed the way dates already are, keeping
  `moonbitlang/x/time` out of the model; that sparklines are an `x14` extension
  Excel is strict about. And each carries the obligation the pivots earned —
  **open the result in Excel by hand**, because every one of them writes a part
  Excel interprets rather than displays.

  Separately, the sub-features the first slice consciously skipped — filter
  criteria, totals rows, 3-D charts, pivot number formats, and the rest — moved
  out of the prose into a **Not scheduled** list with no boxes, so they are
  visible without pretending to be planned.

- **2026-07-27** — **Pivot tables**, the last of Phase 9's Excel features.
  `pivots:` names a source region, groups it down `rows` and along `columns`,
  and aggregates in `values` — with all eleven of Excel's aggregations, a
  display name per field, its built-in styles, and either grand total. (A
  `filters` axis is refused for the backend defect described below.)

  **A pivot is entirely references**, like a chart: the fields are named after
  the *columns of the source's header row*, never after letters or indices. So
  the checks that matter need the finished workbook, and run beside the table
  ones: the source sheet must be declared, the region must have a header row
  with rows beneath it and more than one column, its top row must name every
  column as text, every field laid out must be one of those names — and the
  pivot may not be drawn over the cells it summarizes. The backend answers each
  of these with `InvalidPivotTable`, which says nothing about where in the spec
  the mistake was written; the diagnostic here lists the fields the source
  actually has.

  **Two ranges, two spellings.** A chart's ranges are quoted and absolute
  (`'Orders'!$A$1:$D$7`), because Excel resolves them as formulas. A pivot's are
  *split* by the backend on the first `!` and each half written into the XML as
  it stands, so quoting the sheet would name a sheet that does not exist —
  `InvalidSheetName`, found by trying it. They go bare (`Orders!A1:D7`). That
  split is also why a sheet whose name holds a `!` — which Excel permits — is
  refused for a pivot: nothing downstream could tell the name from the
  separator.

  **The file carries no summary.** The cache is written empty and marked
  `refreshOnLoad="1"`, so the numbers appear when Excel opens the workbook. That
  is the same arrangement as a formula, which `yxl` also emits without
  evaluating (§2), and it is what keeps a pivot honest when its source changes.

  **Opening the result in Excel is what found the rest of this entry**, and is
  the argument for the "does Excel open it cleanly" gate in §9: the round-trip
  tests were green while one of the two pivots in the example showed `#SPILL!`.

  Two defects in `bobzhang/mbtexcel`, both reported upstream as
  [office.mbt#264](https://github.com/moonbitlang/office.mbt/issues/264):

  1. **`<location>` is written with fixed attributes** — `firstHeaderRow="1"
     firstDataRow="2" firstDataCol="1"`, and no `rowPageCount` /
     `colPageCount`. Those values describe a pivot of rows and values only, so
     a pivot with a **page (filter) field** contradicts its own declared
     location and Excel cannot place it. A six-layout workbook opened in Excel
     narrowed it precisely: rows, columns, columns-without-rows, and two row
     fields are all correct; both layouts with a filter show `#SPILL!`.
  2. **Every pivot is written with `cacheId="1"`** while `xl/workbook.xml`
     numbers the caches 1, 2, … Excel resolves a pivot's cache by that number,
     so a second pivot over a *different* source silently summarizes the
     first's data. No error anywhere: the workbook opens, the pivot draws, the
     numbers are wrong.

  So the schema accepts only what survives: `filters:` is refused **by name**,
  with the reason, rather than left to look like an unknown key — and every
  pivot in a workbook must share one source, which keeps the `cacheId`
  collision harmless. Both restrictions are documented in `docs/spec.md` §14 as
  backend limits, not as design.

  Verified in the package: `pivotTable1.xml` with `axisRow` / `axisCol` fields
  resolved to their source positions, `<dataField fld="3" name="Total revenue"
  subtotal="sum"/>`, `colGrandTotals="0"` where asked, the style info, and
  `pivotCacheDefinition1.xml` pointing at `<worksheetSource ref="A1:D7"
  sheet="Orders"/>` (ECMA-376 §18.10). New `examples/pivots.yxl.yaml`: two
  summaries of one order log.

- **2026-07-27** — **Images**, and the seam they needed. `images:` anchors a
  picture at a cell, with alt text, a scale, an offset in pixels, and Excel's
  three anchor kinds — spelled the way its "Size and Properties" pane spells
  them (`move`, `move_and_size`, `fixed`) rather than as OOXML's `oneCell` /
  `twoCell` / `absolute`.

  **This is the first spec key that names a file the loader cannot read as
  text**, and the include resolver has no bytes to give. Rather than widen
  `Included` — which would make every text resolver invent bytes it does not
  have — the loader gained a second seam of the same shape: `BytesResolver`,
  defaulting to one that refuses with a diagnostic. The CLI supplies both, and
  the core still opens nothing itself (ADR-003). Tests pass an in-memory map,
  so nothing but the `examples` package touches the disk.

  The bytes travel into the model and then into the package, so a compiled
  workbook carries the picture and no longer needs the file. The format comes
  from the file's extension, because that is what Excel decodes by — it never
  inspects the bytes — so an unknown extension, a name with no extension, and
  an empty file are each diagnostics rather than a workbook Excel opens with a
  broken-image box.

  One backend detail worth recording: `add_picture_from_bytes` wants the format
  as a *suffix*, dot included (`.png`). Passing `png` fails with
  `UnsupportedFeature`, which says nothing about the dot; the model keeps the
  bare extension and the emitter adds the dot at the seam.

  **And one Windows-only CI failure worth the note in §9.** Reading the result
  back with `Workbook::get_pictures` turned the Windows build red with
  `fatal error C1026: parser stack overflow` — pointing at `mbtexcel`'s formula
  builtins, which nothing here calls. That reader also looks for images *inside*
  cells, which reaches the formula evaluator, which stops it being dead-code
  eliminated, whose thousand-armed dispatch MSVC then cannot parse. Confirmed by
  the symbol tables: the two failing test binaries carried `FormulaParser`, the
  passing ones did not. Reading `Worksheet::images()` instead — the drawing
  pictures, which is what `yxl` emits — is both the fix and the better-matched
  API, and matches how the chart tests already read charts.

  Verified in the package: `xl/media/image1.png` byte-identical to the source,
  a `twoCellAnchor` for `move_and_size` at col 3 / row 1 (D2) with `colOff`
  38100 EMU = 4 px, the alt text in `descr`, and the drawn size — 16 px scaled
  ×2 = 304800 EMU — worked out by the backend from the image's own dimensions.
  `examples/layout.yxl.yaml` now carries a logo (`examples/assets/logo.png`).

- **2026-07-27** — **Charts.** `charts:` anchors a chart at a cell: fourteen
  kinds, one or more series, a title, legend placement, a size in pixels, and
  per-axis title and bounds. A chart holds no values — every part of it points
  at a range — so it needed no new cell machinery, only references written the
  way Excel writes them.

  **Which is the thing worth getting right.** A chart lives in a part of its
  own (`xl/charts/chart1.xml`), where a bare `B2:B4` names nothing, so every
  range is emitted sheet-qualified and absolute: `'Figures'!$B$2:$B$4`. The
  quoting helper `absolute_range` already did for print areas came out as
  `quoted_sheet` and is now shared. A series may name another sheet, and that
  sheet must be declared — checked beside the other cross-sheet references,
  because a chart plotting a sheet that does not exist opens as an empty frame
  saying nothing about why.

  **A series name is either a literal or a cell**, and the backend tells them
  apart by looking for `!`. So `name: Data!B1` would silently become a lookup
  the author never asked for — it is refused, pointing at `name_from`, which is
  the key that *does* read a name from a cell (usually the column header, so
  renaming the header renames the series).

  Fourteen kinds rather than the backend's fifty-odd: the 3-D variants, stock
  charts, and bubble charts each want either an extra range per series or a
  shape the spec has no way to describe, and half-supporting them would be
  worse than not listing them. The spelling table doubles as the diagnostic's
  list of what *is* accepted, so the two cannot drift.

  Verified by reading `chart1.xml` and `drawing1.xml` out of the file: the two
  series with their `strRef` / `v` names, both axis titles, `<c:min val="0"/>`,
  `<c:legendPos val="b"/>`, and the anchor at `E2` with `cx="4953000"` —
  520 px at 9525 EMU each (ECMA-376 §20.1.2.1).

  New `examples/charts.yxl.yaml`, since the feature earns a cookbook page of
  its own: a column chart of two series named from their headers, a pie, and a
  bar chart on a second sheet plotting the first.

- **2026-07-27** — **Excel tables.** `tables:` declares a region to *be* a table
  (a ListObject) rather than merely look like one: filter buttons, banded
  shading, a name formulas can use (`=SUM(Revenue[Revenue])`), and a range Excel
  extends as rows are typed beneath it. The cells stay ordinary cells — a table
  says what a region *is*, so it composes with `cells:` and with `data:`, and
  the `modular` example now declares the region its CSV fills a table.

  **The backend derives the column names from the header cells already in the
  sheet**, which fixes the emission order (tables after cells) and, more
  importantly, means an empty header cell makes it *invent* `Column1` and write
  that into the sheet — a spec's grid, edited by the compiler. So the loader
  checks the header row instead: every column named, as text, no two the same
  (Excel compares them ignoring case). A number is not a column name; quote it.

  Four more checks that Excel would otherwise answer with a repair — silent
  about what it dropped: a name that breaks Excel's defined-name rules, a name
  another table already uses (workbook-wide, ignoring case), two tables sharing
  a cell, and a table overlapping the sheet's own `filter:`. They need the
  finished workbook, so they run beside the cross-sheet reference check rather
  than while the entry is read.

  **A one-row range is refused rather than grown.** The backend extends
  `A1:C1` to `A1:C2`, matching Excel's own dialog; in a compiler that means
  covering a cell the spec never mentioned, so it is a diagnostic. For the same
  reason `header: false` is deferred: the backend *drops* the first row of a
  headerless table's range (excelize parity, verified in its own parity tests),
  so `at` and the emitted range would disagree.

  Style names are checked against Excel's built-in set (`TableStyleLight1`–
  `21`, `Medium1`–`28`, `Dark1`–`11`) because Excel falls back to its default
  for a name it does not know, which would read as a backend bug rather than a
  typo.

  Renamed `loader/table.mbt` to `data.mbt` (and `load_table` to
  `load_data_entry`): it loads `data:`, and leaving "table" on it next to the
  new `tables:` would have been a trap.

  The emitted part was read out of the file by hand, not only round-tripped:
  `<table ref="A1:C3">` with a `tableColumn` per header, `<tableStyleInfo>`
  carrying the four toggles, the sheet's `<tableParts>`, and the relationship
  and content-type entries that make Excel see it (ECMA-376 §18.5).

- **2026-07-26** — **Protection**, at three levels: the workbook's structure,
  a sheet's cells, and — the one that makes the other two useful — a style's
  `protection: { locked, hidden }`. Excel locks every cell by default, so
  protecting a sheet freezes all of it; unlocking a style is the only way to
  build a form somebody can fill in, and shipping sheet protection without it
  would have been shipping half a feature.

  A sheet's `allow:` grants what a reader may still do, and anything unnamed
  keeps Excel's default — selection allowed, everything else blocked, exactly
  what its own dialog opens with. **The polarity was worth checking rather than
  assuming**: OOXML's `sheetProtection` attributes mark what is *locked*, while
  the backend's options (and ours) name what is *allowed*, and getting that
  backwards would have produced workbooks that quietly permitted everything.
  Verified in the emitted XML.

  **`with_protection` does not exist in the backend.** It builds a style by
  seeding from one attribute and layering the rest with `with_*` builders, and
  protection has only a from-scratch constructor — so a style cannot carry both
  a number format and cell protection. Rather than drop one silently, the
  emitter refuses, names the number format so the author can find the style,
  and the spec documents the limit. It is the first place `emit` raises a
  diagnostic of its own rather than wrapping the backend's, so the seam's error
  wrapping now passes ours through untouched.

  **File encryption is deliberately excluded.** `write_with_password` changes
  the emitter's signature and needs the CLI to carry a secret; that wants its
  own decision. A *protection* password is only anti-accident — Excel stores a
  hash, removes it for anyone who asks, and the file's contents are readable
  regardless — so the spec says so outright and points at `${…}` + `--set`
  rather than inviting a password into a version-controlled file.

  One testing limit recorded: the backend's reader does not surface a sheet
  password's hash, so the round-trip test asserts only that adding one disturbs
  nothing else. That the hash reaches the file was read out of the XML by hand;
  asserting it would need a zip reader the test packages do not have.

- **2026-07-26** — **Refactoring pass over the whole tree.** No behaviour
  changed; 257 tests pass.

  **Split at a boundary, not at a line count.** `loader/decorations.mbt` had
  reached 525 lines holding four unrelated schemas: `filter:` (7 lines),
  `links:` (60), `comments:` (37), and `validations:` (~290). Validations are as
  substantial as conditional formats, which already had a file, so
  `validation.mbt` came out at the same boundary and the tests followed. What
  stays behind is what the two big files *share* — the comparison vocabulary and
  sheet-qualified range parsing — which the header now says outright.

  **Tests moved to sit beside what they test:** the `comments:` tests had been
  written into `properties_test.mbt` and now live in `decorations_test.mbt`,
  where the loading does.

  **Three untested error paths covered:** an unterminated quoted sheet name
  (`'Lists!A1:A3`), a list source that is a cell rather than a range, and a
  conditional bound given a sequence.

  **Excel's rank caps** (1000 by count, 100 by percent) became named constants
  in `model`, where every other Excel limit already lives.

  Two documentation drifts fixed: the README's example table had not caught up
  with the notes and document properties added to `interactive` and `layout`,
  and `load_filter`'s doc comment described a duplicate `filter:` key
  "replacing" the first — which cannot happen, since the YAML parser rejects a
  repeated mapping key before the loader sees it.

  One finding deliberately **not** acted on: the sheet and top-level key lists
  are written twice, as `match` arms and again in the unknown-key diagnostic.
  Extracting a constant would have matched the `VALIDATION_RULES` pattern
  without matching its reason — those lists appear in *two* diagnostics, so
  naming them removes a copy, while these appear in one, so naming them removes
  nothing and still leaves two places to edit.

- **2026-07-26** — **Notes, document properties, and calculation settings** —
  the rest of Phase 9's schema-only features, leaving only the ones that need
  new machinery (tables, charts, images, pivots, protection).

  **`comments:`** completes the range-keyed group: text on its own, or
  `{ text, author }`. A note decorates a cell exactly as a link does — the value
  shown is still the cell's own. Leaving the author out does *not* omit it: the
  file always carries one, so Excel writes a generic name. The model says so
  and a test pins it, because the tempting doc comment ("`None` leaves it out")
  would have been wrong.

  **`properties:`** is what the file says about itself — title, subject, author,
  keywords, description, category, status, language, version, company, and any
  number of `custom:` names of the author's own devising. An unset key is left
  out of the file rather than written empty, so a reader can tell "not said"
  from "said to be blank". A custom value keeps its YAML type, and a whole
  number reaches the file as `<vt:i4>4210</vt:i4>` rather than a float. Excel's
  *date* custom-property type is deliberately not exposed: it wants a full
  timestamp with a zone, and a bare `2026-01-01` would have to be guessed at
  (ADR-006) — write it as text until that is settled.

  **`calc:`** takes `mode` (automatic / automatic_no_tables / manual) and
  `on_load`. It only tells Excel what to do on open; `yxl` still never evaluates
  a formula.

  One deletion worth recording: the loader had grown a duplicate-name check for
  custom properties that **could never fire** — the YAML parser rejects a
  repeated mapping key first, and with a line and column this layer cannot
  supply (ADR-016). Removed, and the test rewritten to assert the guarantee
  where it is actually enforced.

- **2026-07-26** — **Conditional formatting.** A sheet's `conditional:` takes
  rules that decide formatting from the *value* rather than the address: `cell`
  comparisons, a `formula`, `text` matches, `top`/`bottom` by count or
  percentage, `duplicate`/`unique`, color scales, data bars, and icon sets.
  Rules apply in the order written, which is Excel's priority order, and
  `stop_if_true` cuts the rest off.

  **A `cell` rule spells its comparison exactly as a validation does** — the
  same `at_least`, the same `between` — because it is the same code. Generalizing
  `load_comparison` over *how a bound is read* was all it took: a validation's
  declared kind fixes what its bounds may be, while a conditional format infers
  (a number, a date if the text parses as one, otherwise text). One vocabulary,
  learned once.

  **Looks are interned into Excel's `dxfs` table**, which is separate from the
  `cellXfs` ids cells wear — an id from one means nothing in the other, so it
  gets its own cache. Reuse still holds inside it: ten rules sharing a look
  store it once (ADR-004), which a test pins.

  Two rules of the schema are worth stating, both about the same distinction.
  The seven rules that *highlight* **require** a `style` — one without a look
  would match cells and then change nothing. The three that *draw* — a scale, a
  bar, an icon set — **refuse** one, having nothing to apply it to.

  Icon-set names are Excel's own (`3TrafficLights1`, `5Rating`), listed in
  `model` so an unknown one fails as a diagnostic rather than as a backend error
  from deep inside the emitter (ADR-006). A test emits all twenty, so the copied
  list cannot drift from what the backend accepts.

- **2026-07-26** — **Validation, filters, and links** — the first Phase 9 slice.
  A sheet gains three keys that *decorate* cells rather than fill them:
  `validations:`, `filter:`, and `links:`. Grouped because they share that
  property and need no new architecture — no drawing part, no binary asset, no
  reader seam — which is why they landed before charts.

  **`validations:`** covers drop-downs, whose choices are either written inline
  or sourced from cells (`list: { from: "Statuses!A1:A3" }`, another sheet
  included), and `whole` / `decimal` / `text_length` / `date` comparisons across
  all eight OOXML operators, each with Excel's "Ignore blank", input prompt, and
  error dialog. A bound is typed — a number, or a `DateTime` whose serial the
  *emitter* computes, since the epoch is a workbook property the loader does not
  know. Integral bounds are written as integers, so the stored formula reads
  `46023` and not `46023.0`.

  **`filter:`** is `set_auto_filter` over a range. **`links:`** takes a bare URL
  for the common case, or `{ to: … }` for an in-workbook target — never inferred
  from shape, because `Summary!A1` and a URL are both just text. A link supplies
  no display text: Excel shows the cell's own value, so recording one would
  store a string nobody sees.

  Two diagnostics are worth naming, both for failures Excel reports as *nothing
  at all*. A **sheet named** by `to:` or by a list's `from:` must be declared —
  otherwise the drop-down comes up empty and the link goes nowhere, and the
  workbook looks fine until someone clicks. That check runs after the whole spec
  is loaded, since a lookup sheet is routinely the last tab. And an **inline
  list over Excel's 255-character limit** is refused with its actual length and
  a pointer to `from:`, rather than being handed to the backend, which would
  fail far from the spec that caused it.

- **2026-07-26** — **The release path is rehearsed on every pull request.**
  Tagging v0.1.1 failed on Windows: packaging ended in `shasum -a 256`, and Git
  Bash ships GNU `sha256sum`, not Perl's `shasum` — while macOS ships `shasum`
  and no `sha256sum`. Nothing here was subtle; the flaw was that **the Package
  step ran only on a tag push**, so its first execution on Windows was the one
  that had to work. The whole build was green and the release still produced
  nothing.

  Packaging now lives in `.github/scripts/package.sh`, which **CI runs on all
  three platforms on every PR** — it builds the archive, unpacks it, and runs
  the binary out of it, so the layout `install.sh` / `install.ps1` expect is
  checked too. The script tries `sha256sum` then `shasum`, and writes the
  `.sha256` line itself (`<hash> *<file>`) rather than passing through whichever
  tool it found, so the format is identical everywhere and binary-mode
  verification is right on Windows as well.

  The wider lesson, worth stating once: **a code path that only executes during
  a release is untested code, and CI's green tick says nothing about it.**

- **2026-07-26** — **Windows support.** The post-v0.1.0 review's top gap, closed.
  Feasibility was answered by *running* it on `windows-latest` rather than
  reasoning about it: the native backend builds (gcc and clang are preinstalled,
  so no MSVC setup), the binary lands at the same relative path as on Unix, the
  whole suite passes there unchanged, and it writes a real `.xlsx`. Releases now
  ship a `.zip` with `yxl.exe`, `install.ps1` gives Windows the same one-line
  install, and CI runs the full matrix on three platforms.

  **Path separators** were the one real bug: `resolve_path` split on `/` alone,
  so a spec named the way Windows tab-completion writes it —
  `yxl build examples\modular.yxl.yaml` — resolved its includes against the
  working directory instead of the spec's folder. Both separators now split, and
  `C:\…`, `C:/…` and UNC `\\server\share` count as absolute. The rule moved
  from the executable into `cli`: string work, not I/O, so it deserves tests that
  run on every platform (ADR-003 keeps the reading in `cmd/main`).

  **On the yen sign**, since Japanese Windows is a first-class case: that console
  *draws* U+005C as `¥` — the same character in a different glyph — so handling
  `\` handles it. A genuine yen sign (U+00A5, or full-width U+FFE5) is
  deliberately **not** a separator: Windows treats it as an ordinary filename
  character, so splitting there would break a legal name like `見積¥1000.yaml`
  while rescuing nothing. The hazard that does bite is **CP932 dame-moji** — 表,
  ソ, 十 carry 0x5C as their *second byte*, and a byte-wise split would cut such
  a name in half; MoonBit strings are sequences of characters, so this splitting
  cannot. Pinned by unit tests and by a Windows CI job that builds a spec
  referring to `表ソ十\見積¥1000\`.

  **One limitation stands, and it is upstream** (§8 Q10): non-ASCII cannot cross
  the *command line* on Windows. `moonbitlang/x/sys` reads argv as UTF-8 ("TODO:
  Handle other encodings") while Windows hands it over in the system code page,
  so `yxl build 売上\report.yaml` fails — as `???` on an English-locale machine,
  as unusable CP932 bytes on a Japanese one. Paths *inside* a spec are
  unaffected, being read as UTF-8 through `@fs`. Documented rather than worked
  around.

- **2026-07-26** — **Post-v0.1.0 review absorbed into the roadmap.** An outside
  review of the shipped v0.1.0 raised five points; this records where each landed.

  *Accepted and scheduled:* a `cells:`-keyed spec is **not** diffable under row
  insertion, which contradicts §1's headline — §1 now says which half is
  delivered and **Phase 11** adds inline `data:` tables; the **one-way
  direction** is now stated in §1 and §2 rather than left to be discovered, with
  a one-time import separated from continuous round-tripping; and **import** was
  promoted from a post-v1 stretch to a wanted Phase 10 item (§8 Q5), with its
  name and scope left open as §8 Q9.

  *Recorded, not scheduled:* no Windows binary (added to Phase 8 with its
  unknowns spelled out — since **closed**, see above); a **JSON Schema**
  generated from `docs/spec.md` (Phase 11); and the fact that **nothing checks
  Excel opens the output without a repair dialog** — Tier 1 re-opens files with
  the same library that wrote them, which cannot disagree with itself (§9 risks,
  and named in the v1.0 gate).

- **2026-07-26** — **v0.1.0 released; CI trigger and action runtimes tidied.**
  The first release published from a `v0.1.0` tag: Linux x86_64 and macOS arm64
  tarballs with checksums, and the one-line installer live. Two things the run
  surfaced. **CI no longer runs on push to `main`** — with `main` reachable only
  through a PR, and `strict` requiring that PR to be current first, the
  post-merge run re-tested a tree the PR had already passed; tags stay covered by
  `release.yml`, which tests again before packaging. **Node 20 deprecation
  warnings gone**: `actions/upload-artifact@v4` and `download-artifact@v4` still
  target Node 20 and were being forced onto Node 24, so they move to `@v7` and
  `@v8`, whose `action.yml` files declare `using: node24` — the inputs in use
  were checked against those tags rather than assumed. `actions/checkout@v5`
  already runs on Node 24 and was left alone.

- **2026-07-26** — **Release runners: no Intel macOS build.** Caught before the
  first release rather than by it: the matrix named `macos-13`, GitHub's free
  Intel runner, which is **retired** — that job would have failed, and because
  the publish step waits on the whole matrix, the release would have produced
  nothing. Its successors (`macos-15-intel`, `-large`) are larger runners whose
  billing could not be confirmed, so rather than quietly commit the repository to
  possibly-paid minutes, the Intel target was dropped. `install.sh` no longer
  claims a `macos-x86_64` build exists — it sends those users to the source
  instructions instead of a binary that could not run anyway.

- **2026-07-26** — **Release automation, the spec reference, and a PR-only
  `main`.** Three pieces of project plumbing, none of them compiler changes:

  - **`docs/spec.md`** — the exhaustive reference for `*.yxl.yaml`: every
    top-level key, sheet key, cell form, style attribute, band, print setting,
    include, data table, and parameter rule, plus the diagnostics and exit
    codes. Written *against the code*, then checked by compiling a spec that
    exercises nearly every key in it, and by confirming that each construct the
    page calls an error really is one. Doing that caught one mistake: the page
    listed seven Excel error literals where the loader accepts ten. This is the
    "documented spec reference" the v1.0 gate asks for.
  - **`.github/workflows/release.yml`** — a **tag push** (`v*`) builds and
    publishes; merging a PR only runs CI, because a release should be a
    deliberate act. The first job refuses to build unless the tag, `moon.mod`,
    and the version `yxl version` reports agree, so a mistagged release stops
    before it produces binaries. Then Linux x86_64 and macOS arm64 tarballs
    (binary + README + LICENSE + examples, each with a `.sha256`), tested before
    packaging, published with `gh` — no third-party action in the release path.
  - **`main` is PR-only.** Recorded in `AGENTS.md §4` with the branch/PR/tag
    commands, and in the README. `AGENTS.md §1`'s "no separate docs" rule now
    names its three user-facing exceptions (README, `docs/spec.md`, `examples/`)
    so the spec reference is not mistaken for the planning doc the rule forbids.

  - **`install.sh`** — a one-line install, the shape a MoonBit CLI user expects
    (`bit`'s installer was the reference): detect OS/arch, resolve the latest
    release (or `YXL_VERSION`), download, **verify the SHA-256**, and place the
    binary in `YXL_INSTALL_DIR` (default `~/.local/bin`), warning if that is not
    on `PATH`. It then *runs* `yxl version`, which catches a binary that matches
    the platform's name but not the machine. Two deliberate departures from the
    reference: a checksum failure **aborts** rather than warning, and there is no
    "use the arm64 build on Intel macOS" fallback — that cannot work. (A real
    `macos-x86_64` target was added and then removed before any release; see the
    entry above.) Verified against
    a local stand-in release: a good install, a tampered tarball (refused), a
    missing version, and an unsupported platform.

  README's install section now leads with the one-liner and keeps building from
  source as the second path.

- **2026-07-26** — **Verification tier 2 stood up: the `examples/` corpus.** §5
  had promised this tier since Phase 0 and nothing had ever enforced it. There
  are now five worked examples, each one a cookbook page whose comments explain
  the feature it demonstrates: `quickstart` (cell kinds, formats, a formula),
  `styling` (declare-once styles, `extends`, a defined name, rich text),
  `layout` (merges, freeze, sized and grouped bands, sheet visibility, print
  setup), `modular` (`$include` plus CSV and JSON `data:` tables across a
  sub-directory), and `parameters` (`params:` with `${}` and `--set`).

  They are tested twice. A new `src/examples` package — no product code, just
  the test — compiles each spec in-process, re-opens the workbook, and asserts
  named cells hold what the example claims, with a **coverage check both ways**:
  an example with no assertions fails, and so does an assertion naming a spec
  that no longer exists. CI then runs the **shipped binary** over the same
  corpus, which is what exercises the on-disk include/data path resolution and
  the exit codes a user sees.

  Verified by breaking things on purpose: changing a cell's value, adding an
  example with no assertions, and putting an unknown key in an included file
  each fail the suite. The test lives in its own package because the toolchain
  now warns that main packages will stop generating blackbox tests, and because
  neither the I/O-free `cli` (ADR-003) nor the executable entry point should
  host a test that reads files. 136 tests green.

- **2026-07-26** — **Phase 8 complete: three scope decisions, and a roadmap
  tidy.** What was left of the phase is settled by decision rather than code:

  - **`--watch` — out of scope** (§2 non-goals). A build is a single command, and
    anyone wanting rebuilds on change already has `make`, `entr`, or an editor
    task. The call stands on its own; it happens to also sidestep needing a timer.
  - **Carets for *schema* errors — out of scope** (**ADR-016**), closing the
    deferral ADR-010 left to this phase. They would need every `Node` to remember
    its origin, which means vendoring or replacing the parser; the messages
    already name the file *and* the construct (`cell 'A1'`, `column 'B'`), which
    locates the problem about as well in a structured document. The `yaml` seam
    keeps the swap possible if that ever proves wrong.
  - **stdin/stdout — dropped, revisit on demand** (§8 Q8). The workaround is one
    line, so the gain is convenience rather than capability, and the toolchain
    exposes no stdin, no byte-level stdout, and no stderr — so it would have cost
    a large dependency or an FFI stub, plus a rule for what relative paths in a
    piped spec resolve against.

  A consequence worth recording: because there is no stderr API either, `yxl`
  prints diagnostics to **stdout**. `main.mbt` used to call that "a later
  refinement"; it is now noted as blocked, with the reason, rather than implying
  someone forgot.

  Tidied while there: §4 stopped listing a `resolve` package that was never built
  (ADR-012/013 folded it into `loader` and `emit`) and stopped advertising
  `--watch`; §3's I/O principle now describes the resolver the CLI actually
  injects; and §5 admits **Tier 2 does not exist** — there is no `examples/`
  directory, so nothing enforces it — with standing it up named explicitly in the
  v1.0 gate, since that is also what would keep the README from drifting.

- **2026-07-26** — **Phase 8: diagnostics with position, `--check`, `--version`,
  help, install docs.** YAML syntax errors used to read `invalid YAML:
  moonbit-community/yaml.YamlError.YamlError` — the library's error was rendered
  through `Show`, which yields a type name. It is a `pub suberror` carrying
  `mark` (line/col) and `info`, so it is now destructured into a real
  `@diag.Span`, and the span machinery built back in Phase 1 finally carries
  something. `Diagnostic::render_in(source)` adds the quoted line and a caret:

  ```text
  report.yaml:5:8: invalid YAML: while parsing a block mapping, ...
    |
  5 |      B1: y
    |        ^
  ```

  The CLI gained `--check` (run the whole pipeline, write nothing — so a spec
  that passes is one `build` accepts), `version`/`--version`/`-V`,
  `help`/`--help`/`-h`, and a bare `yxl` now prints usage instead of erroring.
  `--check` with `-o` is a usage error rather than a silently unwritten file.
  Exit codes 0/1/2 are documented in both the usage text and the README, and
  verified end-to-end. The README gained install steps whose paths were checked
  against a real `--release` build, and CI now fails if `moon.mod`'s version and
  the constant `yxl version` prints ever drift.

  **Two sub-items are blocked, not skipped.** `--watch` and stdin/stdout need a
  sleep/timer and a stdin that the dependency set does not have: `--watch` would
  busy-spin at full CPU, and nothing can read a spec from a pipe. Both want
  `moonbitlang/async` (a large dependency, so an ADR) or a native FFI stub.
  Likewise, carets for *schema* errors need per-node provenance the sealed
  parser API withholds. Recorded together as **§8 Q7**. 134 tests green.

- **2026-07-26** — **Refactor pass (whole tree), after Phase 7.** No behaviour
  change; 129 tests green throughout. The only public-API delta is three
  functions *leaving* the surface.

  *Duplication.* The scalar inference that reads untyped text as a number or a
  boolean existed twice — in `csv_field` and in `infer_scalar` — which the
  parameterization entry above had already claimed was shared. It is now, and the
  claim is corrected. `expect_scalar` and `scalar_value` also spelled the same
  refusal separately; the message is now one `not_scalar`. The three cycle
  detectors (includes, style inheritance, parameters) each built their diagnostic
  by hand; they now share `cycle_error`.

  *Helpers in the wrong home.* `render_cycle` lived in `include.mbt` but served
  all three cycle checks, and `infer_scalar` lived in `params.mbt` but is a CSV
  concern too. Both moved: cycle detection to its own `cycle.mbt`, the scalar
  helpers to `expect.mbt`, the file that already holds the vocabulary every
  loader shares.

  *Consistency.* `$include` and `params` were named constants while `$ref` — the
  oldest of the three directives — was an inline literal; it is now `REF_KEY`.

  *Public surface.* `Font::over`, `Alignment::over`, and `Borders::over` were
  public but called only by `Style::over`; they are private now, so the model
  exposes merging whole styles rather than their pieces.

  *File splitting.* `loader_test.mbt` had grown to 1699 lines and 61 tests
  covering ten source files. Split along those files — `cell_test`, `style_test`,
  `axis_test`, `sheet_test`, `page_test`, `include_test`, `table_test`,
  `params_test` — leaving `loader_test.mbt` (104 lines) for the shared helpers
  and document-level structure.

  *Docs.* README had gone stale again: it still said modular specs were "ahead"
  and showed none of Phase 7. Rewritten, and its example **verified by compiling
  it twice** — once plain, once with `--set` — so the `$include`/`data:`/`params:`
  /`extends:` it now advertises are all exercised.

- **2026-07-26** — **Phase 7 complete: parameterization (`params:` / `--set`).**
  A spec declares parameters with defaults and substitutes them as `${name}` in
  any string — values *and* mapping keys, so a sheet name, a cell reference, or a
  title composed of parts can all be parameterized. `yxl build … --set
  region=EMEA` overrides a default without editing the spec: one spec, many
  workbooks (ADR-015). A default may use another parameter, so **parameter cycles
  are detected** and reported with the chain, alongside the style-inheritance
  cycles.

  Two rules keep types intact: a string that is exactly one placeholder takes the
  parameter's own type (`B1: "${rate}"` is a number cell), and a `--set` value is
  read as the scalar it looks like — the same inference CSV fields get. Without
  the second, `--set rate=0.15` would quietly turn a number cell into text.
  *(This entry originally claimed the two inferences were already one shared
  `infer_scalar`; they were not — the edit had silently missed. The refactor
  below actually makes it so.)*

  A bug caught while testing: the pass originally short-circuited when a spec
  declared no parameters, which let a stray `${nope}` survive as a literal into a
  cell. It now always runs, so an unbacked placeholder is a diagnostic (ADR-006).

  `Command::Build` gained `params`, and `compile`/`load` an optional `params~`.
  129 tests green. **Phase 7 is complete.**

- **2026-07-26** — **Phase 7: style inheritance (`extends:`).** A style
  definition may extend another — `header: { extends: base, font: { bold: true } }`
  — and so may an inline `style:` mapping. The merge reaches *inside* a font, an
  alignment, and the four border edges, so a child that sets `bold` keeps the
  base's face and size; a fill and a number format are single values with no
  parts to blend, so setting either replaces it. Added `@model.Style::over` (plus
  `Font`/`Alignment`/`Borders::over`), which is the whole public-API delta.

  This is the roadmap's "first construct that can let one definition reference
  another", so **cyclic-reference detection lands for definitions** as promised
  in Phase 5: `a -> b -> a` (and a style extending itself) is reported with the
  chain. Resolution is depth-first and memoized, which also buys *forward
  references* — a style may extend one declared later, so the block reads in
  whatever order suits the author — while the walk keeps declaration order so a
  broken spec reports the same error every time. 122 tests green.

- **2026-07-26** — **Phase 7: external data sources (CSV / JSON).** A sheet
  takes a `data:` list, each entry anchoring a table at a cell:
  `- { at: A2, csv: data/sales.csv }`. Fields become **ordinary cells at load
  time** — the model stays the final grid, and nothing below the loader knows the
  values came from elsewhere. Formatting is deliberately *not* duplicated in the
  data block: a region is styled with the `columns:` / `rows:` bands that already
  exist, which is what makes data and formatting separable (ADR-005). Where a
  `data:` table and `cells:` overlap, the later key wins.

  CSV is parsed in-tree (RFC 4180: quoted fields, doubled inner quotes, embedded
  commas and newlines, CRLF, ragged rows) rather than by a new dependency. Since
  CSV carries no types, a bare field is read as a number or boolean when it looks
  like one and text otherwise, while a **quoted** field stays text — the same
  quoting rule YAML scalars already follow here, so `"007"` survives as text. An
  empty field writes no cell at all rather than empty text.

  JSON uses `moonbitlang/core`'s parser. An array of arrays maps straight to
  rows; an array of objects **requires `columns:`** naming the fields to take and
  their order, because JSON object key order is not dependable and silently
  deriving a layout from it would break determinism (§3.1). `null` is a blank
  cell; a missing named field is a diagnostic rather than a guessed blank.

  **Known limitation, documented in `table.mbt`:** a data path resolves against
  the spec passed to `yxl build`, not against the file the `data:` entry was
  written in — includes expand into one tree before any key is read, and the tree
  carries no per-node provenance. A data path inside an included file in another
  directory therefore fails to resolve, loudly and with the path it tried, never
  silently reading the wrong file. Per-node provenance (the same missing piece as
  source spans, ADR-010) would make both rules agree; noted on the Phase 8
  diagnostics item. 118 tests green.

- **2026-07-26** — **Phase 7 started: includes / data–format separation.** A
  spec may now be split across files: `{ $include: path }` stands wherever a node
  may — a whole document, one sheet, a `cells:` block, a `defs.styles` map — and
  expands before any schema key is read, so every loader below is unaware more
  than one file existed (ADR-005, ADR-014).

  The obvious spelling, YAML's `!include` tag, turned out to be **impossible**:
  the parser's tag-carrying API is a sealed trait (the wall ADR-010 already hit)
  and the value tree drops unknown tags *silently* — verified, a spec with
  `A1: !include x.yaml` compiled successfully with the cell set to the text
  `"x.yaml"`. A directive that degrades to a string on a typo is what ADR-006
  exists to prevent, so `$include` (a directive marker matching `$ref`) is the
  contract. §6 and §8 Q4 are corrected accordingly.

  Reading files stays out of the core (ADR-003): `load` takes an
  `IncludeResolver` that the CLI backs with the filesystem — resolving each path
  relative to the file containing it, so a spec directory moves wholesale — and
  tests back with a map, needing no fixtures. Include **cycles are detected and
  reported with the whole chain**; this is the cycle detection deferred from
  Phase 5, arriving with the first construct that can form a loop. Combining
  `$include` with sibling keys is a diagnostic, not an implied merge.

  Public API: `load` and `compile` gained an optional `resolve~`, and `load` now
  raises `Error` rather than only `@diag.SchemaError` — a syntax error inside an
  included file is a real `@diag.YamlError`, and relabelling it would lie about
  the kind. 113 tests green.

- **2026-07-25** — **Refactor pass (whole tree), after Phase 6.** No behaviour
  change: the same spec compiles to *byte-identical* `.xlsx` output and the
  `.mbti` files show **no public-API diff**. 107 tests green (81 → 107 over the
  phase, +7 in this pass).

  *Duplication.* Four sites hand-rolled "parse an A1 reference or raise a
  diagnostic"; they now share `expect_cell_ref`. The scalar expectations were
  split across two files (`expect_map`/`string`/`seq`/`bool` in `loader.mbt`,
  `expect_number`/`expect_color` in `style.mbt`) — all of them, plus
  `schema_error` and `find_key`, now live in one `loader/expect.mbt`, the
  vocabulary every loader file shares.

  *File splitting*, at concern boundaries rather than line counts: `loader.mbt`
  661 → 341 (print block out to `loader/page.mbt`, mirroring the existing
  axis/cell/style/defs layout); `emit.mbt` 560 → 284 (style translation out to
  `emit/style.mbt`, print setup to `emit/page.mbt`). `build_workbook` was a
  145-line function doing everything; it is now a short driver over `emit_sheet`
  and `emit_cell`.

  *Simplification.* `load_sheet` carried 11 mutable locals to stage keys before
  creating the sheet; it now reads only `name` and `visibility` up front (via
  `find_key`) and applies every other key to the sheet in place — zero mutables.
  `load_page_setup` likewise stopped rebuilding the record per key.

  *Tests.* `model_test.mbt` had not kept up with Phases 4–6: added direct
  coverage for the band setters, `merge` canonicalization, the sheet
  presentation setters, `PageSetup::empty`, `Style::is_empty`, defined names and
  the active sheet, plus `CellRef::rect` in `units`.

  *Docs.* `README.md` was badly stale — it claimed "the compiler is not yet
  functional" (six phases ship) and showed a schema that never existed (a
  `workbook:` wrapper, `A1: { text:, merge: }`, top-level `styles:`). Rewritten
  against the real schema, with the example **verified by compiling it**; the
  package table dropped the `resolve` package that was never built (ADR-013
  folded it into the loader). Two `moon.pkg` comments cited ROADMAP `§4`, which
  §8.6 forbids — a reader without this file cannot follow them.

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

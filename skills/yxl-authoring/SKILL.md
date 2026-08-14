---
name: yxl-authoring
description: Build and maintain Excel workbooks as yxl specs (*.yxl.yaml). Use when the user wants an .xlsx generated from YAML, wants a spreadsheet under version control, asks to create a report/workbook with yxl from scratch, or asks to edit, review, refresh, or troubleshoot an existing yxl spec. Carries the default architecture to build unless told otherwise — a sheet per file, styles named once, tabular data, and shared data held in one master other sheets reference — plus the edit-and-verify loop and month-to-month operation. For migrating an existing .xlsx into a spec, see the extract-to-spec skill.
---

# yxl-authoring: workbooks as specs

`yxl` compiles a YAML spec into an `.xlsx` file. It is a compiler, not a
spreadsheet engine: it *emits* formulas and Excel computes them on open. The
payoff of the spec form is that a workbook becomes reviewable text — reuse is
declared once, a change is a small diff, and a monthly refresh is a data swap.

**Ground truth is `docs/spec.md`** in the yxl repository
(<https://github.com/t-ujiie-g/yxl>), with `examples/` as the worked cookbook —
CI compiles every example, so they cannot lie. Section numbers below (§n) refer
to `docs/spec.md`. **Never guess a schema key**: unknown keys, dangling
references, and type errors are hard errors with a diagnostic naming the file
and the construct. If a key might not exist, check the spec first.

```bash
yxl build report.yxl.yaml -o report.xlsx     # compile
yxl build report.yxl.yaml --check            # validate only, write nothing
yxl build report.yxl.yaml -o r.xlsx --set month=2026-07
yxl extract legacy.xlsx -o legacy.yxl.yaml   # existing workbook → starting spec
```

## Prerequisite: the `yxl` CLI

Check with `yxl version`. If it is missing, install it — prebuilt binaries
cover Linux x86_64 and macOS arm64:

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.sh | sh
```

```powershell
# Windows (PowerShell) — experimental; a release may carry no Windows binary
irm https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.ps1 | iex
```

The script verifies the release's SHA-256 and installs into `~/.local/bin`
(`%LOCALAPPDATA%\yxl\bin` on Windows); make sure that directory is on `PATH`.
On any other platform, build from source with
[MoonBit](https://www.moonbitlang.com/download) installed:

```bash
git clone https://github.com/t-ujiie-g/yxl.git && cd yxl
moon build --target native --release
install -m 755 _build/native/release/build/cmd/main/main.exe ~/.local/bin/yxl
```

The README's Install section is the authoritative version of this, including
the Windows caveats (no non-ASCII spec path on the command line).

## The default architecture

**Build this unless the user says otherwise.** It is what makes a spec survive
its second month. When the user does ask for something else — one flat file,
the data pasted inline, no hidden sheets — do it their way and note in one line
what it trades away; their instruction wins, every time, and repeating the
objection is not your job. Do **not** reorganize an existing spec into this
layout as a side effect of an unrelated edit: match the spec's own idiom and
offer the migration as its own piece of work.

The exception is scale, not preference: a one-sheet, one-off workbook stays a
single file. Take the splits below as soon as there is a second sheet, a second
user of a style, or data that will be refreshed.

`examples/workbook.yxl.yaml` in the yxl repository is this whole layout,
compiled and asserted on by CI. **Copy its shape** rather than reinventing one.

```text
report/
  report.yxl.yaml           # params, defs, the list of sheets — nothing else
  defs.yaml                 # defs: styles / values / formulas
  styles.yaml               # the look, named by role
  sheets/
    summary.yaml            # one file per sheet, named after the sheet
    sales.yaml
    masters.yaml
  masters/stores.csv        # data many sheets share — one copy
  data/sales-2026-07.csv    # data that arrives per issue
```

### 1. The entry file is a table of contents

`params:`, `defs:`, and a `sheets:` list of `{ $include: … }` — twenty lines
that show the workbook's shape. Written order is tab order (§2), so the file
also *is* the tab order. Do not number the sheet files to encode it: the list
already says it, and two orderings drift.

### 2. One sheet, one file

A sheet is the unit people edit, review, and argue about; a file per sheet
means two of them can be edited without conflict and `git diff` names the sheet
that changed. Keep the file's own basename equal to the sheet name.

### 3. The look is declared once and named by role

Every style lives in `defs.styles` (§6), in one file, named for the job it does
— `header`, `total`, `money`, `on_target` — never for what it looks like
(`bold_blue`). Build them with `extends:` off a `base` so a font change is one
line. An inline style mapping in a sheet is for a genuine one-off; anything
that appears twice gets a name. This is not tidiness: a named style compiles to
a *single* `cellXfs` id however many cells wear it (ADR-004).

Formatting reaches a region through `columns:` / `rows:` bands (§4), which is
also the only way to style what `data:` and `formulas:` write — neither carries
styling, by design, so data and look stay separable.

### 4. Shared data has exactly one home

The rule: **a value a human maintains is typed once in the repository, and
appears once in the workbook if anything computes from it.** Store names,
account codes, region lists, price masters — all of it.

- **Default — one copy in the workbook, reached by reference.** Give the master
  its own sheet, fed by its own CSV, and declare the region an Excel table
  (§11) so it has a name formulas can use. Make it `visibility: hidden` (§2)
  when it is plumbing rather than a page to read — at least one sheet must stay
  visible. Every other sheet then reaches it *by name*:

  ```yaml
  # sheets/masters.yaml — the only place the store list exists
  name: Masters
  visibility: hidden
  cells:                                   # a table's top row must name its
    A1: { value: store_code, style: header }   # columns, as text
    B1: { value: store_name, style: header }
    C1: { value: region, style: header }
  data: [{ at: A2, csv: masters/stores.csv }]
  tables: [{ at: "A1:C${store_rows}", name: StoreMaster }]
  ```

  ```yaml
  # any other sheet: look it up, do not copy it
  formulas:
    - at: "C2:C${sales_rows}"
      formula: >-
        IFERROR(INDEX(StoreMaster[store_name],
        MATCH(A2, StoreMaster[store_code], 0)), "")
  validations:
    - at: "A2:A${sales_rows}"
      list: { from: "Masters!A2:A${store_rows}" }
  ```

  A structured reference (`StoreMaster[store_name]`) beats a range: it says
  what it reads, and it does not have to be updated when the master moves. A
  drop-down sourced `from:` the master's own cells cannot offer a value the
  master does not have. Charts and pivots point at the master sheet the same
  way.
- **When each sheet must physically show the rows**, name the *same* file from
  each sheet's `data:` entry — one path works from every sheet file, because a
  `data:` path resolves against the entry spec — or `$include` one shared
  `values:` file. One source in git, N regions in the workbook; Excel interns
  the strings anyway, so the file does not grow the way the sheets do.
- **Never** paste the same list into two sheets' `cells:`. That is the fork the
  whole format exists to prevent.

A workbook-wide constant that is not a table — a tax rate, a target — is a
`defs.values` entry (§6); it compiles to a defined name, so formulas say
`target_revenue` and Excel's Name Manager can edit it. A cross-sheet *range*
that is not a table can be named the same way in `defs.formulas`.

### 5. A rectangle of rows is `data:`, and a real table is `tables:`

Use `data:` (§9) for anything with rows: inline `values:` for a handful a human
maintains, `csv:`/`json:` for anything a system produces. A `cells:` mapping is
keyed by address, so inserting a row rewrites every key below it — keep `cells:`
for scattered, individually-styled cells (titles, labels, a KPI box).

Then declare the region a table (§11) when it is one: filter buttons, banded
rows, a name for formulas, and it grows when a user types under it. Prefer a
table over `filter:` — it carries its own, and the two may not overlap.

### 6. A derived column is one `formulas:` range

`{ at: E2:E500, formula: "C2*D2" }` (§3), never five hundred near-identical
`cells:` entries. It compiles to Excel's own shared formula, so the file stores
one. A `{ $ref: }` is refused here on purpose — a defined name gives every cell
the *same* formula, not a translated one.

### 7. Everything that changes per issue is a `params:` entry

The month, the region, the title (§7) — and two less obvious ones:

- **File names.** `csv: "data/sales-${month}.csv"` makes next month
  `--set month=2026-08` plus a file dropped beside its siblings. A missing file
  fails loudly with the path it tried.
- **The ends of ranges that must match the data.** A table's `at:` and a
  validation's `from:` have to be exact, so let them read `${sales_rows}`:
  growth is one number in the entry file, not a hunt through the sheets.

## What bites in practice

- **Two path rules, on purpose.** `$include` resolves relative to the file it is
  written in (so a spec directory moves as a unit); a `data:` path resolves
  relative to the spec `yxl build` was given (ADR-016). A sheet file three
  directories down still writes `csv: data/sales.csv`.
- **Ranges do not grow with the data.** Split them in two: the ones that must be
  exact (`tables:`, a validation's `from:`) read a `params:` row count; the ones
  that may over-reach (`formulas:`, `conditional:`) are written generously and
  guarded — `IF(A4="", "", …)` — so adding a row to the master is no spec edit
  at all.
- **Nothing checks formula text.** `$ref` targets and the sheet names in `to:` /
  `from:` are verified at compile time; a table name or defined name typed
  inside a formula is not, and surfaces as `#NAME?` only when Excel opens the
  file. That is the argument for reaching across sheets through names declared
  once, and for opening the output after a rename.
- **A `data:` block writes text, numbers, and booleans — never dates.** Inline
  `values:` keep the types YAML gave them (a quoted `"007"` stays text, where a
  CSV field has to be guessed at), but a date is a string to both, so a date
  column lands as text. Where the *type* matters, write those cells with
  `cells:` and `type: date` (§3), or derive a real date beside the column with
  `DATEVALUE`.
- **Write a validation's `from:` plainly** — `Masters!A2:A5`, not `$A$2:$A$5`.
  yxl adds the `$` and the sheet-name quoting itself, and refuses the `$` form.
- **Sheet keys apply in written order** (§2), and a `formulas:` range may not
  overlap a cell that `cells:` or `data:` writes. Put derived columns beside the
  data block, or leave `null` in the data rows where the formula column runs —
  `null` writes no cell, so the range is free to fill it.
- **A cell that must defy its own rule is an `overrides:` entry** (§23), not a
  restructuring. One cell of a `${month}` value, a refreshed CSV, or a
  `formulas:` range differing this once is a top-level
  `{ at: Sales!E37, formula: "=D37", reason: … }` — the range stays whole and
  the reason stays with it. Do not inline the parameter, split the range, or
  stop reading the column from its file to accommodate one cell. Always write
  the `reason:`; a growing list is the signal that the rule itself is wrong.

## Writing a spec from scratch

Start minimal and grow it under `--check`; do not draft a hundred lines and
debug them in one go. The architecture above is the destination, not the first
keystroke.

1. **Skeleton first.** One sheet, a few `cells:`, `yxl build --check`. A spec is
   a mapping with one required key (`sheets:`, §1).
2. **Data before decoration.** Lay in the rows (`data:`) and the calculations
   (`formulas:`), confirm they compile, and only then style.
3. **Split as the rules above bite** — the second sheet becomes a file, the
   second use of a style becomes a `defs.styles` name, the second consumer of a
   list becomes a master. Splitting is a mechanical move at any point (`$include`
   replaces any node, §8), so it costs nothing to do it when it earns it.
4. **Richer features each have a section and an example**: validations, links,
   notes, conditional formatting (§10), tables (§11), charts (§12), images
   (§13), pivots (§14), protection (§16), shapes (§18), sparklines (§19), form
   controls (§20), slicers (§21). Copy the shape from `examples/*.yxl.yaml`
   rather than improvising.

## Editing an existing spec

- **Read `defs:` and the masters before touching cells.** A look or a value used
  across the workbook is defined once; edit the definition, not the forty places
  it lands. Never paste an inline copy of something a `defs:` entry or a master
  sheet already holds.
- **Respect the spec's own idiom.** If tables are `values:` rows, add a row, not
  a `cells:` entry; if a column is a `formulas:` range, widen `at:` instead of
  appending one-off formula cells. Keep the diff the shape a reviewer expects.
- **Renames are global.** A `defs` name, a sheet name, or a table name is
  referenced by text (`$ref`, formula bodies, `from:`, `active:`); rename with a
  project-wide search, then `--check`, then open the file — the formula bodies
  are the half the compiler cannot check.
- Run `yxl build --check` after every meaningful edit. Diagnostics name the file
  and the construct (`sheet 'Sales' cell 'B2' …`) — trust them over guessing.
  Some refusals are deliberate and documented: workbook-level `protect:`
  (backend defect, §16), shape geometries whose token carries a capital (§18),
  pivot layouts the backend miswrites (§14). Do not work around a refusal by
  dropping the feature silently — tell the user what was refused and why.

## Operating a spec month to month

The steady state a spec should reach: **refresh = data swap, redesign = spec
diff.**

- Data that arrives monthly lives in files a `data:` entry names — replacing the
  file, and setting the parameter that names it, is the whole refresh. Per-run
  values (issue date, title) are `params:` set at build time.
- Rebuild and spot-open the output. The compile is deterministic, but features
  Excel *interprets* (charts, pivots, conditional rules) deserve one human
  glance after a data shape changes — most often a range that no longer covers
  the new rows.
- Keep generated `.xlsx` out of version control; the spec and its data files are
  the source of truth. A CI job that runs `yxl build --check` on every change
  catches a broken spec before the month-end rush.
- Formula *results* are not in the file until Excel opens it — yxl emits, Excel
  computes. Do not chase "empty" formula cells in the raw bytes.

## Migrating an existing workbook

`yxl extract` turns an `.xlsx` into a starting spec, and the **extract-to-spec
skill** is the rewrite workflow that follows — classifying report vs data
sheets, restoring formula ranges the file could not keep, naming styles, and
verifying the result. Its destination is the architecture above. Use it whenever
the starting point is an existing workbook rather than a blank page.

## Verify before calling it done

```bash
yxl build spec.yxl.yaml -o out.xlsx   # exit 0, no diagnostics
```

then open `out.xlsx` once in Excel or LibreOffice: no repair dialog, formulas
compute, the layout reads as intended. Exit codes are stable: `0` success, `1`
invalid spec or I/O failure, `2` bad command line.

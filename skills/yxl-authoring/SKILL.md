---
name: yxl-authoring
description: Build and maintain Excel workbooks as yxl specs (*.yxl.yaml). Use when the user wants an .xlsx generated from YAML, wants a spreadsheet under version control, asks to create a report/workbook with yxl from scratch, or asks to edit, review, refresh, or troubleshoot an existing yxl spec. Carries the default architecture to build unless told otherwise — a sheet per file, styles named once, every table a layout of named columns whose rows come from data, totals and subtotals as footers, repeated column groups as blocks, and shared data held in one master other sheets reach by name — plus the edit-and-verify loop and month-to-month operation. For migrating an existing .xlsx into a spec, see the extract-to-spec skill.
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

Formatting reaches a table through its layout columns' `style` / `format` and
the layout's `header_style` (§25), and elsewhere through `columns:` / `rows:`
bands (§4). Rows of data never carry styling, by design, so data and look stay
separable.

### 4. Every table is a layout

**A rectangle with a header row is a `layouts:` entry (§25)**, not `cells:` plus
`data:` plus `formulas:` addressed by letter. A layout is an anchor cell and a
list of *named* columns; everything else follows from the names:

```yaml
layouts:
  - at: A2
    name: sales                          # → defined names sales.amount, …
    header_style: header
    csv: "data/sales-${month}.csv"       # rows fill the columns with no formula
    columns:
      - { name: store_code, header: 店舗コード }
      - { name: amount, header: 売上, style: money }
      - name: store_name
        header: 店舗名
        formula: 'IFERROR(INDEX(stores.name, MATCH({{store_code}}, stores.code, 0)), "")'
    footer:
      - row: { store_code: 合計, amount: { total: sum } }
        style: total
```

Why it is the default:

- **Nothing is addressed by letter or row.** `{{amount}}` is this row's cell of
  that column, so inserting a column is a one-line diff and moves no formula.
- **The body is as long as the data.** A monthly CSV of a different length
  moves the formula column, the conditional rules, the footer, and anything
  anchored `below:` it — no row count to keep in step, no over-reaching range
  guarded with `IF(A4="",…)`.
- **Data fills only the input columns**, by name for a CSV (it must start with a
  header row) or a JSON array of objects, by position for inline `values:`. A
  derived column needs no `null` placeholder, and a source that reorders or adds
  fields breaks nothing. `field:` maps a column to a differently named field.
- **One definition per rule.** A column's `format`, `width`, `conditional` rules
  and `formula` live on the column, once.

Reach for the rest of §25 as the shape demands:

- **Two-row headers** — `header: [売上, 当年]`; a shared parent merges across,
  a short column merges down, `null` leaves a blank.
- **Totals and subtotals** — `footer:` rows straight after the body.
  `{ total: sum }` aggregates the column; a `by:` group repeats rows per value
  (nested for 支店 → 直営/FC), with `order:` fixed or sorted and labels like
  `"{{branch}} 計"`; its totals are live `SUMIFS`.
- **A column group that repeats per item** (当年 / 前年 / 前年比 for each of
  売上, 粗利, …) — declare it once in `defs.blocks` and place it per item:
  `{ block: yoy, as: sales, header: 売上 }`.
- **An Excel table** over a layout — `tables: [{ at: sales, name: SalesEntries }]`
  gives filter buttons and banding without repeating the range.

Fall back to `cells:` for what is not a table — titles, labels, a KPI box — and
to `data:` / `formulas:` / bands only for an irregular grid a layout cannot
describe. `examples/columns.yxl.yaml` and `examples/subtotals.yxl.yaml` are the
worked cases.

### 5. Shared data has exactly one home

The rule: **a value a human maintains is typed once in the repository, and
appears once in the workbook if anything computes from it.** Store names,
account codes, region lists, price masters — all of it.

Give the master its own sheet, fed by its own CSV, as a **named layout**, and
make the sheet `visibility: hidden` (§2) when it is plumbing rather than a page
to read — at least one sheet must stay visible. Every other sheet reaches it by
name:

```yaml
# sheets/masters.yaml — the only place the store list exists
name: Masters
visibility: hidden
layouts:
  - at: A1
    name: stores                       # stores.code, stores.name, …
    csv: masters/stores.csv
    columns: [{ name: code, header: store_code }, { name: name, header: store_name }]
```

```yaml
# any other sheet: look it up, do not copy it
formula: 'IFERROR(INDEX(stores.name, MATCH({{store_code}}, stores.code, 0)), "")'
validations:
  - { at: sales.store_code, list: { from: stores.code } }
```

`stores.name` is a workbook defined name over the column's body. It says what
it reads, it follows the master when rows are added, and Excel's Name Manager
shows it. A drop-down sourced from it cannot offer a code the master does not
have. A sheet that needs one row per store reads only the *key* from the
master's file (`code`) and looks the rest up — git still holds one file, and the
workbook one copy of each name. **Never** paste the same list into two sheets.

A workbook-wide constant that is not a table — a tax rate, a target — is a
`defs.values` entry (§6); it compiles to a defined name too, so formulas say
`target_revenue`.

### 6. Reach across by name, never by address

A layout's `name:` is how the rest of the workbook refers to it, wherever it is
and however long it has grown (§25):

- **Formulas**, on any sheet: `SUM(sales.amount)`,
  `SUMIFS(sales.amount, sales.branch, "東京")`.
- **Ranges yxl reads**: a chart series (`values: sales.amount`), a validation's
  list, a sparkline, a pivot's `source: sales` (the table with its header).
- **Placement**: `at: { below: sales, gap: 1 }` for a chart, an image, another
  layout — it follows the table's last row, footer included.
- **Exceptions**: an override finds its cell by meaning,
  `{ at: { layout: sales, column: amount, where: { store_code: S004 } }, … }`,
  and must match exactly one row — so it stays on S004 when rows move.

### 7. Everything that changes per issue is a `params:` entry

The month, the region, the title (§7) — and **file names**:
`csv: "data/sales-${month}.csv"` makes next month `--set month=2026-08` plus a
file dropped beside its siblings. A missing file fails loudly with the path it
tried. Row counts are *not* parameters any more: a layout's body follows its
data, and everything that reads it does so by name.

## What bites in practice

- **Two path rules, on purpose.** `$include` resolves relative to the file it is
  written in (so a spec directory moves as a unit); a `data:` or layout `csv:`
  path resolves relative to the spec `yxl build` was given (ADR-016). A sheet
  file three directories down still writes `csv: data/sales.csv`.
- **A CSV read by a layout starts with a header row**, which names its fields;
  one read by a plain `data:` block does not. A field a column asks for that
  the header lacks is an error naming both.
- **Nothing checks formula text.** `{{name}}` references, `$ref` targets, layout
  names in `from:` / `values:` / `at:`, and sheet names are verified at compile
  time; a defined name or table name typed *inside* a formula (`stores.name`) is
  not, and surfaces as `#NAME?` only when Excel opens the file. Open the output
  after a rename.
- **Write newer functions as the formula bar shows them** — `XLOOKUP`, `FILTER`,
  `TEXTJOIN`; yxl stores them under Excel's `_xlfn.` names (§3). The parameter
  names of `LET` / `LAMBDA` are not prefixed yet, so avoid those two.
- **A `data:` block writes text, numbers, and booleans — never dates.** Inline
  `values:` keep YAML's types (a quoted `"007"` stays text), but a date is a
  string to both. Where the *type* matters, write those cells with `cells:` and
  `type: date` (§3), or derive a real date beside the column with `DATEVALUE`.
- **A `below:` anchor follows a layout declared earlier in the spec**, on the
  same sheet. Two layouts may not both set a band (width, style) on one column.
- **Write a validation's `from:` plainly** — a layout column name, or
  `Masters!A2:A5`, never `$A$2:$A$5`; yxl adds the `$` and the quoting itself.
- **A cell that must defy its own rule is an `overrides:` entry** (§23), not a
  restructuring. One cell of a formula column differing this once is a
  top-level entry with a `reason:` — by meaning for a layout (§6 above), or
  `{ at: Sales!E37, … }` elsewhere. Do not split the column or inline the value
  to accommodate one cell; a growing list is the signal that the rule is wrong.

## Writing a spec from scratch

Start minimal and grow it under `--check`; do not draft a hundred lines and
debug them in one go. The architecture above is the destination, not the first
keystroke.

1. **Skeleton first.** One sheet, a few `cells:`, `yxl build --check`. A spec is
   a mapping with one required key (`sheets:`, §1).
2. **Data before decoration.** Lay in each table as a layout — its columns, its
   rows, its derived columns — confirm it compiles, and only then style it and
   add the footer.
3. **Split as the rules above bite** — the second sheet becomes a file, the
   second use of a style becomes a `defs.styles` name, the second consumer of a
   list becomes a master. Splitting is a mechanical move at any point (`$include`
   replaces any node, §8), so it costs nothing to do it when it earns it.
4. **Richer features each have a section and an example**: layouts, blocks and
   footers (§25), validations, links,
   notes, conditional formatting (§10), tables (§11), charts (§12), images
   (§13), pivots (§14), protection (§16), shapes (§18), sparklines (§19), form
   controls (§20), slicers (§21), one-off exceptions (§23). Copy the shape from
   `examples/*.yxl.yaml` rather than improvising.

## Editing an existing spec

- **Read `defs:` and the masters before touching cells.** A look or a value used
  across the workbook is defined once; edit the definition, not the forty places
  it lands. Never paste an inline copy of something a `defs:` entry or a master
  sheet already holds.
- **Respect the spec's own idiom.** In a layout, a new column is one entry in
  `columns:` and a new item of a repeated group is one block instance; in an
  older spec, if tables are `values:` rows, add a row, and if a column is a
  `formulas:` range, widen `at:`. Keep the diff the shape a reviewer expects.
  Converting an older spec's tables to layouts is worth offering — as its own
  piece of work, not a side effect.
- **Renames are global.** A `defs` name, a sheet name, a table name, a layout
  name or a column name is referenced by text (`$ref`, formula bodies, `from:`,
  `{{…}}`, `active:`); rename with a
  project-wide search, then `--check`, then open the file — the formula bodies
  are the half the compiler cannot check.
- Run `yxl build --check` after every meaningful edit. Diagnostics name the file
  and the construct (`sheet 'Sales' cell 'B2' …`) — trust them over guessing.
  Some refusals are deliberate and documented: three icon sets the backend
  writes into the wrong attribute (§10), sparkline markers it cannot switch on
  (§19), a style carrying both a number format and cell protection (§16). Do
  not work around a refusal by dropping the feature silently — tell the user
  what was refused and why.

## Operating a spec month to month

The steady state a spec should reach: **refresh = data swap, redesign = spec
diff.**

- Data that arrives monthly lives in files a layout reads — replacing the file,
  and setting the parameter that names it, is the whole refresh; the body,
  its formulas, its footer and whatever sits below it follow the new length. Per-run
  values (issue date, title) are `params:` set at build time.
- Rebuild and spot-open the output. The compile is deterministic, but features
  Excel *interprets* (charts, pivots, conditional rules) deserve one human
  glance after a data shape changes — most often a range written by address,
  outside any layout, that no longer covers the new rows.
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

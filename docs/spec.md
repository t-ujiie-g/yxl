# The `yxl` spec format

A reference for `*.yxl.yaml`. Worked examples live in
[`examples/`](../examples); this page is the exhaustive list.

> **Not frozen.** The schema may change until v1.0 (see
> [`ROADMAP.md`](../ROADMAP.md)). Every change is in the §11 changelog.

Throughout: **unknown keys are errors**, not ignored. A bad key, reference, or
value fails the build with a diagnostic naming the file — `yxl` never guesses
and never silently drops part of a spec.

---

## 1. Document

A spec is a YAML mapping. Only `sheets` is required.

```yaml
sheets: [...]          # the workbook's sheets, in tab order
active: Summary        # the sheet Excel opens on (default: the first)
params: {...}          # named values substituted as ${name}   → §7
defs: {...}            # named styles, values, and formulas    → §6
properties: {...}      # what the file says about itself       → §14
calc: {...}            # when Excel recalculates               → §14
protect: {...}         # lock the workbook's structure         → §15
date1904: false        # use Excel's 1904 date epoch
default_font: Calibri  # the workbook's default font face
```

| Key | Type | Notes |
|---|---|---|
| `sheets` | sequence | **Required.** Order here is tab order. |
| `active` | text | Must name a declared, **visible** sheet. |
| `params` | mapping | §7. |
| `defs` | mapping | §6. |
| `properties` | mapping | Document properties. §14. |
| `calc` | mapping | Calculation settings. §14. |
| `protect` | mapping | Workbook protection. §15. |
| `date1904` | boolean | `true` selects the 1904 epoch. Affects how dates serialize. |
| `default_font` | text | Face name only; size and colour are per-style. |

Any node may instead be `{ $include: path }` — see §8.

## 2. Sheets

```yaml
sheets:
  - name: Sales        # required
    cells: {...}       # → §3
    data: [...]        # → §9
    columns: [...]     # → §4
    rows: [...]        # → §4
    merges: [A1:C1]
    visibility: visible | hidden | very_hidden
    freeze: B2         # or: split: { x: 120, y: 60 }
    gridlines: true
    tab_color: "1F77B4"
    print: {...}       # → §5
    filter: A1:D1      # → §10
    validations: [...] # → §10
    links: {...}       # → §10
    conditional: [...] # → §10
    comments: {...}    # → §10
    tables: [...]      # → §11
    charts: [...]      # → §12
    images: [...]      # → §13
    protect: {...}     # → §15
```

| Key | Type | Notes |
|---|---|---|
| `name` | text | **Required.** Must be unique in the workbook. |
| `cells` | mapping | A1 reference → value. §3. |
| `data` | sequence | External CSV/JSON tables. §9. |
| `columns` / `rows` | sequence | Bands. §4. |
| `merges` | sequence of `A1:B2` | Corners in any order; the merge shows the top-left value. |
| `visibility` | bareword | `hidden` can be undone in Excel's UI; `very_hidden` only via VBA. **At least one sheet must stay visible.** |
| `freeze` | cell | Rows above and columns left of it stay put. `A1` freezes nothing and is an error. |
| `split` | `{ x, y }` | A draggable splitter, in **points** from the top-left; `0` leaves that axis unsplit. Mutually exclusive with `freeze`. |
| `gridlines` | boolean | The on-screen grid, *not* cell borders. |
| `tab_color` | hex `RRGGBB` | |
| `print` | mapping | §5. |
| `filter` | range | Excel's auto filter. §10. |
| `validations` | sequence | What cells will accept. §10. |
| `links` | mapping | Hyperlinks, by cell. §10. |
| `conditional` | sequence | Formatting decided by the value. §10. |
| `comments` | mapping | Notes, by cell. §10. |
| `tables` | sequence | Excel tables over the sheet's regions. §11. |
| `charts` | sequence | Charts anchored on the sheet. §12. |
| `images` | sequence | Pictures anchored on the sheet. §13. |
| `protect` | mapping | Sheet protection. §15. |

Sheet keys apply **in the order written**, so where a `data:` table and `cells:`
overlap, whichever comes last wins.

## 3. Cells

A cell is either a scalar or a mapping.

```yaml
cells:
  A1: Region                                  # text
  B1: 2400000                                 # number
  C1: true                                    # boolean
  D1: "007"                                   # quoted → stays text
  A2: { value: 0.085, format: "0.0%" }
  B2: { formula: "SUM(B1:B1)", value: 2400000 }
  C2: { value: "2026-07-23", type: date }
  D2: { $ref: tax_rate }                      # a named value → §6
  A3:
    rich:
      - "Plain then "
      - { text: bold, font: { bold: true } }
```

YAML's own types carry over: a bare `1` is a number, a quoted `"1"` is text.

### The expanded form

| Key | Notes |
|---|---|
| `value` | A scalar, or `{ $ref: name }` naming a `defs.values` entry. |
| `formula` | A formula body; a leading `=` is accepted and stripped. Or `{ $ref: name }` naming a `defs.formulas` entry. With `value:`, that value is the **cached result** Excel shows until it recomputes. |
| `rich` | A sequence of runs: a plain string, or `{ text:, font: }`. Mixes fonts inside one cell. |
| `type` | `text` \| `number` \| `bool` \| `date` \| `error` — coerces the value. Cannot be combined with `formula`. |
| `format` | An Excel number-format code, e.g. `"#,##0.00"`, `"0.0%"`. |
| `style` | A style name (bareword) or an inline style mapping. §6. |

`type: date` accepts `YYYY-MM-DD` or `YYYY-MM-DD HH:MM:SS` and stores an Excel
serial. Without an explicit `format`, a date defaults to `yyyy-mm-dd` and a
date-time to `yyyy-mm-dd hh:mm:ss`.

`type: error` accepts Excel's error literals: `#DIV/0!`, `#N/A`, `#NAME?`,
`#NULL!`, `#NUM!`, `#REF!`, `#VALUE!`, `#SPILL!`, `#CALC!`, and
`#GETTING_DATA`.

> **`yxl` emits formulas; Excel computes them.** There is no evaluator here.

## 4. Column and row bands

A band applies to a span of columns or rows. `at` selects it: a column label
(`B`, `D-F`) or a row number (`1`, `2-4`).

```yaml
columns:
  - at: B
    width: 18            # character units
    style: header        # or an inline mapping
    format: "#,##0"
  - at: D-F
    group: 1             # outline level 0-7; Excel draws a collapsible bracket
    hidden: true         # both together = a collapsed group
rows:
  - at: 1
    height: 28           # points
```

| Key | Columns | Rows |
|---|---|---|
| `at` | **required** | **required** |
| `style`, `format`, `hidden`, `group` | ✔ | ✔ |
| `width` (character units) | ✔ | — |
| `height` (points) | — | ✔ |

A band that sets nothing contributes nothing. `group` must be a whole number
between 0 and 7; `0` means ungrouped, which is distinct from omitting the key.

## 5. Print setup

```yaml
print:
  area: A1:D50
  orientation: portrait | landscape
  margins: { top: 1, bottom: 1, left: 0.7, right: 0.7, header: 0.3, footer: 0.3 }
  scale: 80                  # percent, 10-400
  fit: { width: 1, height: 0 }   # pages across / down; 0 = unconstrained
  header: "&CQuarterly report"
  footer: "&LPage &P of &N"
  breaks: [A21, C1]          # each starts a new page above and left of itself
```

Margins are in **inches** (Excel's unit here) and may not be negative. `scale`
and `fit` are the two halves of Excel's scaling control and **cannot be
combined**. `header`/`footer` use Excel's `&`-code syntax (ECMA-376 §18.3.1.46).
A break at `A1` breaks nothing and is an error.

## 6. Definitions and references

Declare once, reference by name. Reuse compiles to Excel's *native* sharing: a
style becomes one `cellXfs` id however many cells wear it, and a value becomes a
**defined name**, so editing it in Excel updates every reference.

```yaml
defs:
  styles:
    base:   { font: { name: Calibri, size: 11 } }
    header: { extends: base, font: { bold: true }, fill: "1F3864" }
  values:
    tax_rate: 0.085
  formulas:
    subtotal: "SUM(B2:B10)"
```

- A **style** is referenced by bareword: `style: header`.
- A **value** or **formula** is referenced by `{ $ref: name }`.
- The three namespaces are separate; the same name may exist in each.
- A reference to an undeclared name is an error, and so is a cycle.

### Style attributes

| Key | Value |
|---|---|
| `extends` | Another declared style's name. Merges *inside* font, alignment, and each border edge, so a child setting `bold` keeps the base's face and size. A fill or number format has no parts to blend, so setting it replaces it. Works in inline styles too. Forward references are fine; cycles are an error. |
| `font` | `{ bold, italic, underline, strike, size, name, color }` — all optional. |
| `fill` | A hex `RRGGBB`, or `{ color: RRGGBB }`. Solid fills only. |
| `border` | A style name for all four edges (`border: thin`), or a mapping of `all` / `left` / `right` / `top` / `bottom`, each a style name or `{ style, color }`. Styles: `thin`, `medium`, `thick`, `dashed`, `dotted`, `double`, `hair`. |
| `protection` | `{ locked, hidden }` — what sheet protection does to a cell wearing this style. §15. |
| `align` | `{ horizontal, vertical, wrap }`. Horizontal: `left`, `center`, `right`, `fill`, `justify`, `distributed`. Vertical: `top`, `middle`, `bottom`, `justify`, `distributed`. |

A cell's own `format` layers on top of a referenced style.

## 7. Parameters

One spec, many workbooks.

```yaml
params:
  region: APAC
  rate: 0.085
  title: "${quarter} ${region}"   # a default may use another parameter
```

```bash
yxl build report.yxl.yaml -o emea.xlsx --set region=EMEA
```

- `${name}` substitutes in **any string** — values *and* mapping keys, so a
  sheet name or a cell reference can be parameterized.
- A string that is **exactly one placeholder** keeps the parameter's type, so
  `B1: "${rate}"` is a number cell, not the text `0.085`.
- A `--set` value is read as the scalar it looks like, so `--set rate=0.15`
  stays a number.
- `$$` is a literal `$`; a `$` that begins neither escape is itself, so Excel's
  absolute references (`$A$1`) are safe. Where a literal `$` immediately
  precedes a placeholder, write `$B$$${n}`.
- Referencing an undeclared parameter is an error, as is `--set` naming one, as
  is a cycle among defaults.

## 8. Includes

`{ $include: path }` stands wherever a node does — a whole document, one sheet,
a `cells:` block, a `defs.styles` map.

```yaml
defs:
  styles:
    $include: styles/theme.yaml
sheets:
  - name: Sales
    cells:
      $include: data/q3.yaml
```

- Paths resolve **relative to the file containing the include**, so a spec
  directory can be moved as a unit.
- Either separator works: `/` and `\` both split a path, on every platform. Use
  `/` inside a spec if you want it to read the same everywhere. (On Japanese
  Windows the backslash *displays* as `¥` — that is the same character. A real
  yen sign is an ordinary filename character, as it is to Windows itself.)
- Non-ASCII paths are fine **inside** a spec. On the *command line*, Windows
  cannot carry them today — see the README's install notes.
- Includes may nest. A cycle is an error, reported with the whole chain.
- `$include` replaces its entire node, so combining it with sibling keys is an
  error rather than an implied merge.

> A YAML `!include` **tag** is not supported and never will be: the parser drops
> unknown tags silently, which would turn a typo into a plain string instead of
> a diagnostic (ADR-014).

## 9. External data

`data:` anchors a CSV or JSON table at a cell; its rows run down and its fields
right. The values become ordinary cells.

```yaml
data:
  - at: A2
    csv: data/sales.csv
  - at: D1
    json: data/notes.json
    columns: [label, count]
```

| Key | Notes |
|---|---|
| `at` | **Required.** The top-left field lands here. |
| `csv` / `json` | The source path. Exactly one. |
| `columns` | **Only for JSON objects**: the fields to take, in order. |

**Formatting is not part of a data block** — style the region with `columns:` /
`rows:` bands. That is what keeps data and formatting separable.

### CSV

RFC 4180: commas separate fields, newlines separate records, and a `"`-quoted
field may contain either and doubles an inner quote. CRLF is accepted, and rows
need not be the same length.

CSV carries no types, so a **bare** field is read as a number or boolean when it
looks like one and text otherwise, while a **quoted** field always stays text —
so `"007"` survives. An empty field writes no cell at all.

### JSON

An **array of arrays** maps straight to rows. An **array of objects** requires
`columns:`, because JSON object key order is not dependable and deriving a
layout from it would break determinism. `null` is a blank cell; a named field
that is missing is an error.

> **Path resolution differs from `$include`:** a `data:` path resolves against
> the spec passed to `yxl build`, not against the file the entry was written in.
> It fails loudly with the path it tried, never silently reading the wrong file.
> (ADR-016 — the tree carries no per-node provenance.)

## 10. Validation, filters, links, notes, and conditional formatting

These decorate cells rather than fill them. A validation over an empty range is
legal, and a link supplies no text of its own — the value you see still comes
from `cells:` or `data:`.

### Auto filter

```yaml
filter: A1:D1        # the header row Excel hangs its dropdowns off
```

One per sheet. Excel reads the range's top row as the header and filters what
lies beneath it. Per-column criteria are not expressible yet.

### Validations

```yaml
validations:
  - at: B2:B200
    list: [Draft, Sent, Paid]          # the choices themselves
  - at: C2:C200
    list: { from: "Statuses!A1:A3" }   # or the cells holding them
    allow_blank: false
    prompt: { title: Status, body: "Pick one." }
    error: { title: "Not a status", body: "Choose from the list.", style: stop }
  - at: D2:D200
    whole: { between: [1, 1000] }
  - at: E2:E200
    decimal: { at_least: 0 }
  - at: F2:F200
    text_length: { at_most: 12 }
  - at: G2:G200
    date: { at_least: "2026-01-01" }
```

| Key | Notes |
|---|---|
| `at` | **Required.** The range the rule covers. |
| `list` | A sequence of choices, or `{ from: range }` naming the cells holding them. |
| `whole` / `decimal` / `text_length` / `date` | A comparison (below). `text_length` measures the text; `whole` refuses a fractional bound. |
| `allow_blank` | Excel's "Ignore blank", **default `true`**. |
| `prompt` | `{ title, body }` — shown when the cell is selected. |
| `error` | `{ title, body, style }` — shown when a value is refused. |

Exactly one rule per entry. The comparison is exactly one of `between`,
`not_between` (each `[low, high]`), `equals`, `not_equals`, `at_least`,
`at_most`, `greater_than`, `less_than`. `error.style` is `stop` (the default,
which refuses the value), `warning`, or `information` (which let it through).

A `date` bound is written as a date (`YYYY-MM-DD`); every other kind takes a
number. An inline `list` is stored as one comma-joined string and must fit
Excel's 255-character limit — over that, source it from cells instead.

### Links

```yaml
links:
  A2: https://example.com/orders/1001         # outside the workbook
  B1: { to: "Statuses!A1", tip: "The statuses" }   # inside it
  C1: { url: "https://example.com", tip: "The dashboard" }
```

A bare value is a URL. `to:` is an in-workbook target — `Sheet!A1` or a defined
name — and is *not* inferred from shape, since `Summary!A1` and a URL are both
just text.

| Key | Notes |
|---|---|
| `url` | A target outside the workbook. Exactly one of `url` / `to`. |
| `to` | A target inside it. |
| `tip` | The hover tooltip. |

A sheet named by `to:` or by a validation's `from:` must be declared, or the
build fails — Excel reports neither, so a typo would otherwise ship as a
drop-down that comes up empty or a link that goes nowhere.

### Notes

```yaml
comments:
  C3: "Bulk order — check stock before confirming."
  B1: { text: "Sourced from the Statuses sheet.", author: Finance }
```

A note (Excel's older name for it is a comment) appears on hover. Like a link,
it decorates the cell: the value shown is still the cell's own.

| Key | Notes |
|---|---|
| `text` | **Required** in the expanded form; a bare value is the text. |
| `author` | Shown above the text. A note always carries one in the file, so leaving it out does not omit it — Excel writes a generic name instead. |

### Conditional formatting

Formatting decided by the value rather than the address.

```yaml
conditional:
  - at: B2:B50
    cell: { at_least: 1000000 }    # the same comparisons validations use
    style: strong                  # a declared style, or an inline mapping
  - at: B2:B50
    cell: { less_than: 0 }
    style: weak
    stop_if_true: true             # matched here, Excel tries no later rule
  - at: C2:C50
    text: { contains: urgent }
    style: weak
  - at: D2:D50
    formula: "AND($D2>0, $E2<0)"
    style: strong
  - at: E2:E50
    top: 10                        # or { count: 10, percent: true }
    style: strong
  - at: F2:F50
    duplicate: true                # or unique: true
    style: weak
  - at: G2:G50
    color_scale: { low: "F8696B", middle: "FFEB84", high: "63BE7B" }
  - at: H2:H50
    data_bar: { color: "638EC6" }
  - at: I2:I50
    icon_set: 3TrafficLights1      # or { style:, reverse:, icons_only: }
```

| Key | Notes |
|---|---|
| `at` | **Required.** The range the rule covers. |
| `cell` | A comparison, spelled exactly as in a validation (§ above). The bound is read as it is written: a number, a date if it parses as one, otherwise text. |
| `formula` | An expression, true where the rule should apply. Written relative to the range's **top-left** cell, as Excel's own dialog does — `$B2` holds the column and lets the row move. |
| `text` | Exactly one of `contains`, `not_contains`, `begins_with`, `ends_with`. |
| `top` / `bottom` | A count (1–1000), or `{ count, percent: true }` for a percentage (1–100). |
| `duplicate` / `unique` | `true`. Values appearing more than once, or exactly once, in the range. |
| `color_scale` | `low` and `high`, optionally `middle` — a two- or three-color gradient. |
| `data_bar` | `color`, and `bar_only: true` to hide the value behind the bar. |
| `icon_set` | One of Excel's own names — `3Arrows`, `3TrafficLights1`, `4Rating`, `5Boxes`, … — optionally with `reverse` and `icons_only`. |
| `style` / `format` | The look applied where the rule matches. |
| `stop_if_true` | Stop evaluating later rules on a cell this one matched. |

Rules apply **in the order written**, which is Excel's priority order.

`style` and `format` are **required** for the rules that highlight (`cell`,
`formula`, `text`, `top`, `bottom`, `duplicate`, `unique`) — one without a look
would match cells and change nothing. They are **refused** for the three that
draw their own appearance (`color_scale`, `data_bar`, `icon_set`), which would
have nothing to apply it to.

Excel keeps these looks in a table of its own, separate from the styles cells
wear, but they are declared the same way and shared the same way: a look used by
ten rules is stored once.

## 11. Tables

An *Excel table* (a "ListObject") declares a region to **be** a table rather than
merely look like one: it arrives with filter buttons, banded shading, a name
formulas can use (`=SUM(Revenue[Revenue])`), and it grows over any row typed
beneath it.

```yaml
tables:
  - at: A1:B4              # required; the top row is the header
    name: Revenue          # what formulas call it (default: Table1, Table2, …)
    style: TableStyleMedium2
    banded_rows: true      # shade alternate rows       (default: true)
    banded_columns: false  # shade alternate columns    (default: false)
    first_column: false    # emphasize the first column (default: false)
    last_column: false     # emphasize the last column  (default: false)
```

| Key | Type | Notes |
|---|---|---|
| `at` | range | **Required.** Includes the header row, so it spans at least two rows. |
| `name` | text | Excel's defined-name rules: starts with a letter or `_`, then letters, digits, `.` and `_` — **no spaces** — and never looks like a cell reference. Unique across the workbook, ignoring case. |
| `style` | text | One of Excel's built-ins: `TableStyleLight1`–`TableStyleLight21`, `TableStyleMedium1`–`TableStyleMedium28`, `TableStyleDark1`–`TableStyleDark11`. |
| `banded_rows`, `banded_columns`, `first_column`, `last_column` | boolean | The four toggles of Excel's "Table Design" ribbon. What each does depends on the style, which supplies the colours. |

The cells stay ordinary cells — write them with `cells:` or `data:` as usual;
`tables:` only says what the region is. **The top row must name every column, as
text**, and no two names may repeat (Excel compares them ignoring case). A
number is not a column name: quote it if that is what you meant.

```yaml
cells:
  A1: Region      # ← the column names
  B1: Revenue
  A2: APAC
  B2: 2400000
tables:
  - at: A1:B2
    name: Revenue
```

A table may not overlap another table or the sheet's own `filter:` — a table
carries its own filter buttons, so it needs no separate one. Excel repairs (or
refuses) a workbook that breaks any of this, so `yxl` refuses the spec first.

A table with its header row turned off is not expressible yet.

## 12. Charts

A chart is a picture of cells that already exist. It holds no values of its own
— every part of it points at a range — so editing a cell redraws the chart, and
a chart may plot a sheet other than the one it sits on.

```yaml
charts:
  - at: E2                 # required; the chart's top-left corner floats here
    type: column           # required
    title: Revenue by region
    legend: bottom         # bottom | top | left | right | top_right | none
    size: { width: 520, height: 300 }    # pixels
    x_axis: { title: Region }
    y_axis: { title: Amount, min: 0, max: 4000000 }
    series:                # required; at least one
      - values: B2:B4      # required
        categories: A2:A4  # the labels down the category axis
        name_from: B1      # the legend entry, read from a cell
      - values: Figures!C2:C4
        name: Cost         # …or written out
```

| Key | Type | Notes |
|---|---|---|
| `at` | cell | **Required.** A chart floats above the grid; the cells beneath it keep whatever they hold. |
| `type` | bareword | **Required.** See below. |
| `series` | sequence | **Required**, and not empty. |
| `title` | text | |
| `legend` | bareword | `none` leaves the chart without one. |
| `size` | `{ width, height }` | **Both required**, in whole pixels. |
| `x_axis` / `y_axis` | `{ title, min, max }` | At least one of the three. An unset end leaves Excel scaling the axis to the data. |

**Types:** `column`, `column_stacked`, `column_percent_stacked`, `bar`,
`bar_stacked`, `bar_percent_stacked`, `line`, `area`, `area_stacked`,
`area_percent_stacked`, `pie`, `doughnut`, `scatter`, `radar`. Excel's 3-D
variants, stock charts, and bubble charts are not expressible yet.

### Series

| Key | Notes |
|---|---|
| `values` | **Required.** The cells plotted. `Sheet!A1:A9` names another sheet, which must be declared. |
| `categories` | The labels down the category axis — for a `scatter` chart, the X values. Without it Excel numbers the points 1, 2, 3, … |
| `name` | What the legend calls the series, written out. |
| `name_from` | A cell to read that name from — usually the column header, so renaming the header renames the series. Mutually exclusive with `name`. |

A literal `name` may not contain `!`: Excel reads a series name holding one as a
reference to a cell, so it would quietly become a lookup. Use `name_from`.

A `pie` or `doughnut` draws only its first series. Every range is emitted
sheet-qualified and absolute (`'Figures'!$B$2:$B$4`), which is how Excel stores
one — a chart lives in a part of its own, where a bare `B2:B4` names nothing.

## 13. Images

A picture floats above the grid: `at` positions its top-left corner, and the
cells under it keep whatever they hold.

```yaml
images:
  - at: E1
    file: assets/logo.png      # required
    alt: Example Ltd logo
    scale: 0.5                 # or: { x: 2, y: 0.5 }
    offset: { x: 4, y: 4 }     # pixels in from the cell's corner
    positioning: move          # move | move_and_size | fixed
```

| Key | Type | Notes |
|---|---|---|
| `at` | cell | **Required.** |
| `file` | path | **Required.** Resolved like a `data:` path — see §9. |
| `alt` | text | What a screen reader announces; Excel's "Alt Text". |
| `scale` | number or `{ x, y }` | A factor over the image's natural size, above `0` and at most `100`. One number scales both directions. |
| `offset` | `{ x, y }` | **Both required**, in whole pixels, and never negative — OOXML's anchor measures in from the cell's corner (ECMA-376 §20.5.2.3). |
| `positioning` | bareword | What happens when the cells beneath change. |

**Positioning**, in the words of Excel's own "Size and Properties" pane:

| Written | Excel calls it |
|---|---|
| `move` (the default) | "Move but don't size with cells" |
| `move_and_size` | "Move and size with cells" |
| `fixed` | "Don't move or size with cells" |

**Formats:** `png`, `jpg`/`jpeg`, `gif`, `bmp`, `tif`/`tiff`, `ico`, `svg`,
`emf`/`emz`, `wmf`/`wmz`. The format is taken from the file's extension, since
that is what Excel decodes by — it never inspects the bytes. An unknown
extension, a name with no extension at all, and an empty file are each
diagnostics.

The bytes are read while the spec compiles and travel into the workbook, so the
`.xlsx` carries the picture itself and no longer needs the file.

## 14. Document properties and calculation

```yaml
properties:
  title: Quarterly report
  subject: Regional sales
  author: Finance team          # Excel's "creator"
  keywords: "sales, q3"
  description: Revenue by region.
  category: Reports
  status: Final                 # Excel's "content status"
  language: en-GB
  version: "1.2"
  company: Example Ltd
  custom:                       # names of your own devising
    Cost centre: 4210
    Reviewed: true

calc:
  mode: manual                  # automatic | automatic_no_tables | manual
  on_load: true                 # recalculate once when the workbook opens
```

Every `properties:` key is optional, and one left out is left out of the file —
a reader can tell "not said" from "said to be blank". A `custom:` value keeps
its YAML type: `4210` is a number, `true` a boolean, anything else text. Write a
date as text; Excel's date type here wants a full timestamp with a zone, and one
written without would have to be guessed at.

`calc:` only tells Excel what to do **on open** — `yxl` emits formulas and never
evaluates them (§3). `mode: manual` leaves a workbook showing whatever cached
values the spec supplied, which is worth setting where recalculation is slow;
`on_load: true` forces one full pass regardless, which is what you want where
the spec supplied no cached values at all.

## 15. Protection

```yaml
protect:                    # the workbook itself
  structure: true           # no adding, removing, renaming, reordering sheets
  windows: false
  password: "${wb_password}"

defs:
  styles:
    entry:
      protection: { locked: false }   # this is what makes a form fillable

sheets:
  - name: Orders
    protect:                # the sheet's cells
      password: "${sheet_password}"
      allow:
        sort: true
        auto_filter: true
        select_locked_cells: false
```

**Excel locks every cell by default**, so protecting a sheet freezes all of it.
The way to leave a form's input boxes editable is to give *them* a style with
`protection: { locked: false }`. `hidden: true` additionally keeps the cell's
formula out of the formula bar — the value still shows, and the file still
contains the formula.

A sheet's `allow:` names what a reader may still do; anything unnamed keeps
Excel's default, which is **selection allowed, everything else blocked** —
exactly what its own "Protect Sheet" dialog opens with. The full list:
`select_locked_cells`, `select_unlocked_cells`, `format_cells`,
`format_columns`, `format_rows`, `insert_columns`, `insert_rows`,
`insert_hyperlinks`, `delete_columns`, `delete_rows`, `sort`, `auto_filter`,
`pivot_tables`, `edit_objects`, `edit_scenarios`. A misspelt one is an error,
not a permission that silently never applies.

> **A protection password is not encryption.** It stops accidents and is
> trivially removed; Excel stores a hash, not the word, and the file's contents
> are readable either way. A spec is usually version-controlled, so write the
> password as a parameter (§7) and pass it with `--set` rather than committing
> it. Encrypting the *file* is not supported.

### One combination the backend cannot express

A style may carry **either** a number format **or** cell protection, not both.
The build fails saying so, naming the format, rather than dropping one
silently. Split them into two styles, or drop the format.

## 16. Diagnostics

A failed build prints one diagnostic and exits non-zero. YAML **syntax** errors
carry a line and column with the source quoted:

```text
report.yaml:5:8: invalid YAML: while parsing a block mapping, did not find expected key
  |
5 |      B1: y
  |        ^
```

**Schema** errors name the file and the construct they are about — `cell 'A1'`,
`column 'B'`, `sheet 'Sales'`, `parameter 'region'` — but not a line; the
parser exposes no per-node positions (ADR-016).

| Exit code | Meaning |
|---|---|
| `0` | success |
| `1` | the spec is invalid, or a file could not be read or written |
| `2` | the command line itself was wrong |

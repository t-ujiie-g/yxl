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
properties: {...}      # what the file says about itself       → §15
calc: {...}            # when Excel recalculates               → §15
protect: {...}         # refused for now — backend defect      → §16
date1904: false        # use Excel's 1904 date epoch
default_font: Calibri  # the workbook's default font face
```

| Key | Type | Notes |
|---|---|---|
| `sheets` | sequence | **Required.** Order here is tab order. |
| `active` | text | Must name a declared, **visible** sheet. |
| `params` | mapping | §7. |
| `defs` | mapping | §6. |
| `properties` | mapping | Document properties. §15. |
| `calc` | mapping | Calculation settings. §15. |
| `protect` | mapping | Workbook protection — **refused for now**, a backend defect. §16. |
| `date1904` | boolean | `true` selects the 1904 epoch. Affects how dates serialize. |
| `default_font` | text | Face name only; size and colour are per-style. |

Any node may instead be `{ $include: path }` — see §8.

## 2. Sheets

```yaml
sheets:
  - name: Sales        # required
    cells: {...}       # → §3
    formulas: [...]    # → §3
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
    shapes: [...]      # → §18
    background: assets/logo.png   # tiled behind the cells → §13
    sparklines: [...]  # → §19
    controls: [...]    # → §20
    slicers: [...]     # → §21
    pivots: [...]      # → §14
    protect: {...}     # → §16
```

| Key | Type | Notes |
|---|---|---|
| `name` | text | **Required.** Must be unique in the workbook. |
| `cells` | mapping | A1 reference → value. §3. |
| `formulas` | sequence | One formula filled across a region. §3. |
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
| `shapes` | sequence | Boxes and other geometries floating over the sheet. §18. |
| `background` | path | An image tiled behind the cells. §13. |
| `sparklines` | sequence | Charts inside single cells, in groups. §19. |
| `controls` | sequence | Buttons, check boxes, and sliders over the grid. §20. |
| `slicers` | sequence | Button panels filtering declared tables. §21. |
| `pivots` | sequence | Pivot tables placed on the sheet. §14. |
| `protect` | mapping | Sheet protection. §16. |

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
  E2: { value: "26:30:00", type: duration }   # an elapsed time, not a clock time
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
| `type` | `text` \| `number` \| `bool` \| `date` \| `duration` \| `error` — coerces the value. Cannot be combined with `formula`. |
| `format` | An Excel number-format code, e.g. `"#,##0.00"`, `"0.0%"`. |
| `style` | A style name (bareword) or an inline style mapping. §6. |

`type: date` accepts `YYYY-MM-DD` or `YYYY-MM-DD HH:MM:SS` and stores an Excel
serial. Without an explicit `format`, a date defaults to `yyyy-mm-dd` and a
date-time to `yyyy-mm-dd hh:mm:ss`.

`type: duration` accepts `H:MM` or `H:MM:SS` — an *elapsed* time, so the hours
may exceed 23 (`26:30:00` is twenty-six and a half hours). Excel stores it as a
plain number, the length as a fraction of a day; the default format `[h]:mm:ss`
is what makes it display as hours, because `[h]` keeps counting past 24 instead
of rolling into days.

`type: error` accepts Excel's error literals: `#DIV/0!`, `#N/A`, `#NAME?`,
`#NULL!`, `#NUM!`, `#REF!`, `#VALUE!`, `#SPILL!`, `#CALC!`, and
`#GETTING_DATA`.

> **`yxl` emits formulas; Excel computes them.** There is no evaluator here.

### Filled formula ranges

A calculation column is one formula that *moves*: `D2` is `B2*C2`, `D3` is
`B3*C3`, and so on down. Writing that as `cells:` costs a line per row, and
inserting a row rewrites every line below it. `formulas:` says it once.

```yaml
formulas:
  - at: D2:D500
    formula: "B2*C2"
```

The formula is written **as it applies at the range's top-left cell**. Every
other cell gets it with its relative references shifted by that cell's offset;
absolute references (`$C$2`) do not move. A range may span columns as well as
rows, and a one-cell range is allowed.

| Key | Notes |
|---|---|
| `at` | **Required.** A `TopLeft:BottomRight` range. |
| `formula` | **Required.** The formula body; a leading `=` is accepted and stripped. |

This compiles to Excel's own **shared formula**: the file stores the text once
and marks the rest of the range as following it, so a 500-row column is one
stored formula, not five hundred.

A `{ $ref: name }` is **refused** here. A `defs.formulas` reference compiles to a
defined name (§6), which gives every cell that references it the *same* formula
— the opposite of filling a range with one that shifts per row. Write the
formula in place instead.

**Formatting is not part of a formula range**, for the same reason it is not part
of a `data:` block (§9): style the region with a `columns:` / `rows:` band, which
reaches every cell the range fills (§4).

A range may not overlap another range, or any cell that `cells:` or `data:`
writes — a cell holds one formula, and letting one side silently win would hide
the clash. Split the range around the exception:

```yaml
formulas:
  - at: D2:D9
    formula: "B2*C2"
  - at: D11:D500          # D10 is written by hand
    formula: "B11*C11"
```

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

### How a band's styling reaches a cell

A band's `style` / `format` applies to every cell in its span, written or not.
Where several apply, they **layer**, innermost last: the column band, then the
row band over it, then the cell's own `style` / `format` over both. Layering is
per attribute, as `extends` is (§6), so a column can set the number format while
the cell sets the font and both survive.

```yaml
columns:
  - at: B
    format: "#,##0"        # every B cell counts in thousands
rows:
  - at: 1
    style: { font: { bold: true } }   # …and the header row is bold
cells:
  B1: Revenue              # bold, and shown as text
  B2: 2400000              # bold and 2,400,000
```

One exception, and it is Excel's rather than `yxl`'s: **an inherited number
format does not apply to a text cell.** An Excel number format is
`positive;negative;zero;text`, so a code with fewer than four sections says
nothing about text and Excel displays it plain. A `format:` written on the cell
itself is always honoured — that is a request, not an inheritance.

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
| `protection` | `{ locked, hidden }` — what sheet protection does to a cell wearing this style. §16. |
| `format` | An Excel number-format code, as on a cell. A `format:` written beside the reference layers over this one. |
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

### Sheet backgrounds

`background: <path>` on a sheet tiles an image behind its cells, like a
watermark — the same formats, path resolution, and diagnostics as an `images:`
file. One per sheet.

> **Excel never prints a background.** It shows on screen only — a surprise
> worth knowing before building letterhead around one. A printed watermark is a
> header/footer picture, which `yxl` does not emit yet.

## 14. Pivot tables

A pivot table summarizes cells that live somewhere else — usually a plain data
sheet — grouping them down the rows and along the columns and aggregating in the
middle. The spec says what to summarize and how; **Excel does the arithmetic**,
and redoes it whenever the source changes.

```yaml
pivots:
  - at: A3:F30                 # required; where the pivot is drawn
    source: Orders!A1:D7       # required; header row first
    rows: [Region]
    columns: [Quarter]
    values:
      - field: Revenue
        function: sum          # default
        name: Total revenue    # Excel would say "Sum of Revenue"
    name: RevenueByRegion
    style: PivotStyleMedium9
    row_grand_totals: true
    column_grand_totals: true
```

| Key | Type | Notes |
|---|---|---|
| `at` | range | **Required.** The corner the pivot starts from; Excel grows it past this as it needs to. |
| `source` | range | **Required.** `Sheet!A1:D7` names another sheet, which must be declared. Its **top row names the fields**, and there must be at least one row beneath and more than one column. |
| `rows` / `columns` | sequence | Field names, or `{ field, name }` to relabel one. |
| `values` | sequence | Field names (summed), or `{ field, function, name }`. |
| `name` | text | Default: `PivotTable1`, `PivotTable2`, … |
| `style` | text | `PivotStyleLight1`–`28`, `PivotStyleMedium1`–`28`, `PivotStyleDark1`–`28`. |
| `row_grand_totals` / `column_grand_totals` | boolean | Both default to `true`, as Excel does. |

**Functions:** `sum` (the default), `count`, `count_numbers`, `average`, `max`,
`min`, `product`, `std_dev`, `std_dev_p`, `var`, `var_p`.

Every field named on any axis must be a column of the source's header row, and
that row must name **every** column of the range, as text — a pivot cannot refer
to a field Excel would not find. A pivot may not be drawn over the cells it
summarizes.

> **The file carries no summary.** `yxl` writes the pivot's definition and an
> empty cache marked "refresh on load", so the numbers appear when Excel opens
> the workbook — the same arrangement as a formula, which `yxl` also emits
> without evaluating.

### Two limits the Excel backend imposes today

Both are defects in `bobzhang/mbtexcel`, reported upstream as
[office.mbt#264](https://github.com/moonbitlang/office.mbt/issues/264). `yxl` refuses the spec rather than emit a workbook that is
broken or quietly wrong.

**No `filters:` axis.** Excel's "Filters" box is the fourth axis a pivot can
have. The backend writes the pivot's `<location>` without accounting for the
filter rows above the body, and Excel answers with `#SPILL!` where the pivot
should be. `filters:` is therefore rejected by name, with that reason. Rows,
columns, several fields on an axis, and every aggregation are unaffected —
each was checked in Excel.

**One source per workbook.** The backend gives every pivot `cacheId="1"` while
numbering the caches `1`, `2`, …, and Excel resolves a pivot's cache by that
number. A second pivot over a *different* source would summarize the first
one's data — silently, with no error anywhere. Two pivots over the **same**
source are fine and stay correct; a second source is rejected.

## 15. Document properties and calculation

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

## 16. Protection

```yaml
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

> **Workbook-level `protect:` is refused for now** — a backend defect: it
> writes `<workbookProtection>` after `<sheets>`, out of the schema's element
> order, and Excel reports the whole file as corrupt. Protect each sheet
> instead; the key returns the day the upstream writer places it correctly.

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

## 17. Diagnostics

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

## 18. Shapes

A shape — a box, star, or other preset geometry — floats above the grid,
optionally carrying text: `at` positions its top-left corner, and the cells
under it keep whatever they hold.

```yaml
shapes:
  - at: E2
    kind: cloud                     # required — see the geometry list below
    text: Approved                  # or a list of lines, each with its own font
    size: { width: 240, height: 120 }
    fill: "1F77B4"
    line: { color: "333333", width: 2 }
    alt: An approval stamp
    positioning: move               # move | move_and_size | fixed
```

| Key | Type | Notes |
|---|---|---|
| `at` | cell | **Required.** |
| `kind` | bareword | **Required.** One of the geometries below. |
| `text` | text or list | A plain string, or a sequence of lines — each a string or `{ text, font }`, the font written as a style's `font:` (§4 of the styling keys). Each entry is its own *line*: one font covers one line. |
| `size` | `{ width, height }` | **Both required**, in whole pixels. Unset, the shape is 160 × 160. |
| `fill` | hex color | The fill; unset keeps the theme default. |
| `line` | hex color or `{ color, width }` | The outline. `width` is in points and must be above `0`; a bare hex is just the color. |
| `alt` | text | What a screen reader announces; Excel's "Alt Text". |
| `positioning` | bareword | The same three anchors an image takes (§13). |

**Geometries.** `kind` is one of: `rectangle`, `ellipse`, `triangle`,
`diamond`, `parallelogram`, `trapezoid`, `pentagon`, `hexagon`, `octagon`,
`decagon`, `star_5`, `plus`, `chevron`, `cube`, `can`, `donut`, `frame`,
`heart`, `moon`, `sun`, `cloud`, `pie`, `line`. Each maps to a DrawingML
preset (ECMA-376 §20.1.10.56); an unknown name is a diagnostic.

**Backend limits.** The Excel backend lowercases the geometry token it writes
into the file, and DrawingML's tokens are case-sensitive — `roundRect` written
as `roundrect` is a geometry Excel does not recognize. The kinds whose token
carries a capital are therefore *refused by name*, with the reason: the
rounded rectangle, the right triangle, the eight straight arrows, and the four
callouts. They become plain schema additions the day the backend keeps the
token's case. An offset in from the anchor cell (which images take) is not
available either: the backend's shape constructor does not accept one.

## 19. Sparklines

A sparkline is a chart inside one cell, for the row of figures beside it. Each
`sparklines:` entry is a **group**: Excel scales and styles a group as one
unit, so a column of them reads as one series.

```yaml
sparklines:
  - at: F2                       # one sparkline …
    data: B2:E2                  # … of these cells (may name another sheet)
    markers: true                # dot every point (line only)
    high: true                   # pick out the highest point
    color: "1F77B4"
  - cells:                       # or several cells, styled as one group
      - { at: G2, data: Results!B2:E2 }
      - { at: G3, data: Results!B3:E3 }
    type: win_loss               # line (default) | column | win_loss
    axis: true                   # draw the horizontal axis at zero
```

| Key | Type | Notes |
|---|---|---|
| `at` / `data` | cell / range | One sparkline: the cell it sits in, the cells it plots. `data` may name another (declared) sheet. |
| `cells` | sequence of `{ at, data }` | Several sparklines in one group. A group is placed one way: `at`/`data` **or** `cells`. |
| `type` | bareword | `line` (default), `column`, or `win_loss` — win/loss plots only each point's sign. |
| `markers` | boolean | Dot every point. Line only — the other kinds already draw one mark per point. |
| `high` / `low` | boolean | Emphasize the highest / lowest point. |
| `min` / `max` | whole number | Manual vertical bounds; unset, Excel scales each end to the data. Whole numbers — the backend accepts nothing finer. |
| `weight` | number | The line weight in points, above `0`. Line only. |
| `color` | hex color | The series colour. |
| `colors` | `{ markers, high, low }` | Colours for the marks that can show. |
| `axis` | boolean | Draw the horizontal axis at zero. |

**Backend limits.** Excel's *first point*, *last point*, and *negative points*
markers are carried by the backend as options nothing can set, so `first:`,
`last:`, and `negative:` are refused by name with the reason — they become
plain schema additions the day the setters exist upstream.

## 20. Form controls

A form control sits over the grid and writes into its **linked cell** — a
boolean for a check box, the chosen option's index for option buttons, the
number for a scroll bar or spin button. That linked value is what formulas
react to, and it is the other half of the story `protection` (§16) tells: lock
the sheet, unlock the entry cells, and let the controls drive the rest.

```yaml
controls:
  - at: F2
    kind: check_box            # see the kinds below
    text: Rush order
    checked: false
    link: G2                   # the cell the control writes into (same sheet)
  - at: F4
    kind: scroll_bar
    link: H4
    min: 0
    max: 100
    step: 5                    # one arrow click
    page: 20                   # one click in the trough
    value: 40
    horizontal: true
    size: { width: 160, height: 20 }
```

**Kinds:** `button`, `check_box`, `option_button`, `scroll_bar`,
`spin_button`, `group_box`, `label`.

Each key is admitted only on the kinds whose own "Format Control" dialog shows
it — anything else is a diagnostic naming where the key belongs:

| Key | Belongs to | Notes |
|---|---|---|
| `at` / `kind` | all | **Required.** |
| `size` | all | `{ width, height }`, both in whole pixels. |
| `text` | `button`, `check_box`, `option_button`, `group_box`, `label` | The caption. |
| `checked` | `check_box`, `option_button` | Starts ticked. |
| `link` | `check_box`, `option_button`, `scroll_bar`, `spin_button` | A **same-sheet** cell; the backend refuses a qualified reference. |
| `min` / `max` / `step` / `value` | `scroll_bar`, `spin_button` | Whole numbers `0`–`30000`, Excel's own dialog limit; `min` may not exceed `max`. |
| `page` | `scroll_bar` | A click in the trough; a spin button has none. |
| `horizontal` | `scroll_bar`, `spin_button` | Lay it sideways. |

No `macro:` — an `.xlsx` carries no macros, and a button without one is a
caption that clicks. Assigning behavior is Excel's side of the contract.

> **On a protected sheet, unlock the linked cell.** Excel writes a control's
> value into its `link` like any other edit, so a locked target makes the
> control show "the cell is on a protected sheet" instead of working. Give the
> linked cell a style with `protection: { locked: false }` (§16), exactly as
> for typed-into entry cells.

## 21. Slicers

A slicer is a table's filter as a panel of buttons — one per distinct value of
one column — floating over the grid. Clicking a button filters the table,
visibly.

```yaml
sheets:
  - name: Sales
    cells: { A1: Region, B1: Revenue, A2: APAC, B2: 2400 }
    tables:
      - at: A1:B4
        name: Revenue        # a slicer needs the table *named*
    slicers:
      - at: G1
        table: Revenue       # the declared table, on any sheet
        column: Region       # one of its header cells
        caption: Filter by region
        size: { width: 160, height: 140 }
        header: true
```

| Key | Type | Notes |
|---|---|---|
| `at` | cell | **Required.** Where the panel's top-left corner sits. |
| `table` | text | **Required.** The `name:` of a declared table, compared without case (Excel's own rule). A table the spec left unnamed cannot be sliced. |
| `column` | text | **Required.** One of the table's header cells; anything else is a diagnostic naming what the table has. |
| `caption` | text | The panel's title; unset, Excel shows the column name. |
| `size` | `{ width, height }` | Both in whole pixels; unset, 200 × 200. |
| `header` | boolean | Whether the panel shows its title bar. |

The slicer may sit on a different sheet than its table — the panel goes where
the reader looks, the data stays where it lives.

**Pivot slicers are not offered.** A slicer over a pivot table touches the
same cache machinery whose defects already bound `pivots:` (§14); they stay
out until [office.mbt#264](https://github.com/moonbitlang/office.mbt/issues/264)
is resolved.

## 22. Going the other way: `yxl extract`

An existing workbook becomes a starting spec instead of a retyping job.

```
yxl extract report.xlsx -o report.yxl.yaml          # a spec, plus its tables
yxl extract report.xlsx -o report.yxl.yaml --flat   # one file, whatever it costs
```

This is a **one-way migration aid, not a round trip**. What the spec format can
say is recovered; what it cannot is dropped, and each kind of loss is named once
on the way out. Treat the result as a starting point and edit it — that is what
it is for.

### It may write more than one file

A sheet that is nothing but a rectangle of plain values — no formulas, no styles,
no gaps — is written out as a **CSV beside the spec** and named by a `data:`
entry (§9), because a thousand `cells:` lines is not a spec anybody keeps. The
file lands next to the spec at the path the spec names it by:

```
report.yxl.yaml
data/sales.csv
assets/summary_e1.png
```

The rule for tables is deliberately narrow. A styled cell, a formula, a ragged
edge, or a region too small to be worth opening a second file all keep the whole
sheet inline — a wrong "yes" here would silently drop formatting `data:` cannot
carry, where a wrong "no" only leaves a long block. `--flat` turns it off
entirely, which is what to use when comparing two extractions.

**Pictures are always written out**, `--flat` or not: an image has no inline
form to fall back to. Its bytes come through unchanged, so the file beside the
spec is the picture the workbook held.

### What it recovers

Cell values, formulas, and mixed-font rich text. Styles, **interned**: a look
worn by forty cells becomes one `defs.styles` entry, because the file kept the
sharing even though it lost the name. Merged ranges. Column and row bands —
widths, heights, hidden, outline levels — with adjacent equal ones collapsed
back into a single entry. Frozen and split panes, gridlines, tab colours, sheet
order, hidden sheets, the active tab, and the 1904 date system.

Pictures, including the one tiled behind a sheet: the bytes come out unchanged,
and each is written beside the spec with the `images:` or `background:` entry
that names it.

The decorations too: notes, hyperlinks, data validations (with their prompts,
error dialogs, and — for a `date` rule — bounds turned back from serials into
written dates), conditional formats of every rule the format names, Excel
tables, and the auto filter's range.

The four things that float over a sheet rather than sitting in it: shapes (§18)
with their geometry, text, size, fill, outline, and anchor; sparklines (§19)
with their kind, points, bounds, weight, and any colour the file names outright;
form controls (§20) with what each writes into its linked cell; and slicers
(§21) with the table column each filters. Four details of these do not survive,
and each is listed below.

And what the workbook says about itself: named definitions (`defs.values` and
`defs.formulas`), the document properties including the custom ones, the
calculation settings, the default font, and each sheet's protection.

### What it does not, and why

- **Names are invented, because the file has none.** A style is given a
  descriptive name only on strong evidence — bold on a fill is `header`, a lone
  percentage format is `percent` — and a neutral `style`, `style_2`, … otherwise.
  A wrong name misleads where a meaningless one merely says nothing, and renaming
  means replacing every reference rather than one definition.
- **A number is left a number**, even under a date format. `type: date` would be
  a guess about intent, and the number plus its format compiles back to the
  identical cell.
- **A formula's cached result is left behind.** Excel recomputes it on open.
- **A shared formula is recovered at its master cell only.** The reader does not
  expose which cells follow it, so the rest arrive as the values they cached.
  A `formulas:` range (§3) is the spelling to restore by hand.
- **A picture's scale is not recovered.** The file records how big to draw it in
  absolute units rather than as a factor, and the Excel backend reports the
  factor back as `1` whatever it was — so a scaled picture cannot be told from an
  unscaled one, and every picture comes back at its natural size. `extract` says
  so on the way out rather than leaving it to be noticed.
- **A form control's size is not recovered.** The file records it in the
  control's VML, and the Excel backend's reader takes the anchor and the values
  from there but never the size — so every control comes back at Excel's
  default, and one that was sized cannot be told from one that was not.
- **The font on a line of shape text is not recovered**, for the same reason at
  the other end of the file: it is written into the drawing's `a:rPr` and not
  read back. A shape's words survive; how they were set does not.
- **A shape geometry Excel spells with a capital cannot come back.** The backend
  lowercases the `prst` token, so `roundRect` reads as `roundrect`, which names
  no geometry in §18's table and could not be told from any other. Those
  geometries are refused on the way in for the same reason; `extract` reports
  the shape rather than guessing which one it was.
- **The sheet a sparkline plots from is not recovered.** The file writes
  `'Data'!B2:E2` and the backend's reader keeps only what follows the `!`, so a
  sparkline that plotted another sheet comes back plotting this one — the same
  shape of answer with the wrong numbers in it. `extract` says so whenever a
  workbook has more than one sheet; with a single sheet nothing can be lost.
- **Charts and pivots are not recovered yet.** They are in the file and neither
  is a limit of the format: the Excel backend hands both back as raw XML parts,
  so recovering them means reading DrawingML and the pivot cache, which is a
  reader of its own rather than a translation.
- **A colour scale's stops are not kept**, only its colours: the schema places
  them at the range's own low and high, which is Excel's default and what an
  author writing the spec by hand would get.
- **A filter's saved criteria are not kept**, only the range it covers: which
  rows somebody last chose to hide is a view of the sheet, not a description
  of it.
- **Print setup is not recovered.** The Excel backend cannot report it per
  sheet: reading one sheet's setup leaks it to every later sheet, so a spec built
  on it would claim the wrong orientation.
- **A sheet-protection password is not recovered.** The file keeps a hash, not
  the word. It is reported, so a spec that needs one can have it set again
  rather than looking protected while opening to anyone.
- **A name defined for one sheet only is not recovered.** The spec's definitions
  are workbook-wide, and widening one would change which cells it resolves for.

### It checks its own work

Every extraction compiles the spec it produced and compares the cells against
the ones it read. A mismatch is reported and the exit code says so — the spec is
still written, because a starting point with a known gap beats none, but it
tells you rather than leaving it to be found in Excel.

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
date1904: false        # use Excel's 1904 date epoch
default_font: Calibri  # the workbook's default font face
```

| Key | Type | Notes |
|---|---|---|
| `sheets` | sequence | **Required.** Order here is tab order. |
| `active` | text | Must name a declared, **visible** sheet. |
| `params` | mapping | §7. |
| `defs` | mapping | §6. |
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

## 10. Validation, filters, and links

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

## 11. Diagnostics

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

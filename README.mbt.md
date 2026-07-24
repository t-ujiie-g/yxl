# yxl

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

**Manage Excel spreadsheets as version-controllable YAML.** `yxl` is a
[MoonBit](https://www.moonbitlang.com/) command-line **compiler**: you write a
declarative `*.yxl.yaml` spec, and `yxl build` turns it into a real,
Excel-compatible `.xlsx`.

Spreadsheets-as-code, with the properties code has:

- **Diffable & reviewable** — a workbook is text under Git.
- **DRY / single-source-of-truth** — a value, formula, or style written **once**
  and referenced many times is managed in one place, and compiles down to
  Excel's *native* sharing (shared strings, defined names, shared formulas, a
  single style id). Change it once, it changes everywhere.
- **Flexible structure** — split data and formatting across files for large
  workbooks, or inline everything for simple ones.
- **A single native command** — `yxl build report.yxl.yaml -o report.xlsx`.

The `.xlsx` bytes are produced by the mature
[`bobzhang/mbtexcel`](https://mooncakes.io/docs/bobzhang/mbtexcel) library (a
MoonBit port of Go's excelize); `yxl` is the language, the reuse/dedup engine,
the validator, and the CLI on top. It is not another spreadsheet *library* — it
is declarative authoring for people who'd rather edit YAML than write code.

> ⚠️ **Status: pre-release, schema not yet frozen.** `yxl build` works today —
> values, formulas, dates, rich text, styles, named definitions, layout, and
> print setup all compile. Modular specs (includes, external data) and CLI
> polish are still ahead, and the schema may change until v1.0. See
> [`ROADMAP.md`](./ROADMAP.md) for the phase plan and the living changelog.

## A taste

```yaml
# report.yxl.yaml
defs:                      # declared once, referenced by name
  styles:
    title:  { font: { bold: true, size: 16 }, align: { horizontal: center } }
    header: { font: { bold: true, color: "FFFFFF" }, fill: "1F3864" }
    total:  { font: { bold: true } }
  values:
    quarter: "Q3 FY26 Sales"

sheets:
  - name: Sales
    freeze: A4               # the header rows stay put while the data scrolls
    merges: [A1:B1]
    columns:
      - at: A
        width: 18
      - at: B
        width: 14
        format: "#,##0"      # a whole-column default format
    cells:
      A1: { value: { $ref: quarter }, style: title }
      A3: { value: Region, style: header }
      B3: { value: Revenue, style: header }
      A4: APAC
      B4: 2400000
      A5: EMEA
      B5: 1750000
      A6: { value: Total, style: total }
      B6: { formula: "SUM(B4:B5)", style: total }
    print:
      area: A1:B6
      orientation: landscape
      fit: { width: 1 }      # shrink to one page across
```

```bash
yxl build report.yxl.yaml -o report.xlsx
```

Each declared style compiles to a **single** Excel style id however many cells
wear it, and each `defs.values` entry to a **defined name** — so editing it in
Excel updates every reference. An unknown key, a bad cell reference, or a
dangling `$ref` fails the build with a diagnostic naming the file, never a
silently dropped value.

## How it works

```
report.yxl.yaml
   → parse (YAML → document tree)
   → load + validate + resolve references (typed model, diagnostics naming the file)
   → emit: intern shared styles, strings, and defined names   ← the DRY engine
     via a swappable backend (bobzhang/mbtexcel)
   → report.xlsx
```

The pipeline core is filesystem-free and unit-testable on strings and bytes; only
the CLI touches disk. The Excel backend sits behind a seam so it can be swapped
(see [`ROADMAP.md §7`](./ROADMAP.md), ADR-002).

## Packages

| Package | Purpose |
|---|---|
| `diag` | Diagnostics + subdomain errors with source spans |
| `units` | Type-safe cell references, colors, dates |
| `yaml` | YAML source → document tree |
| `model` | Typed intermediate representation |
| `loader` | Document tree → model: schema validation, reference resolution |
| `emit` | Model → `.xlsx` bytes (mbtexcel-backed), style/string interning |
| `cli` (`cmd/main`) | Argument parsing, file I/O, exit codes |

## Development

```bash
moon check --deny-warn      # type check
moon test                   # tests
moon fmt                    # format
moon info                   # regenerate the .mbti interface files
moon build --target native  # build the CLI
```

Direction, phase scope, architecture decisions (ADRs), and the changelog all
live in the single source of truth, [`ROADMAP.md`](./ROADMAP.md). Contributor and
AI-agent conventions are in [`AGENTS.md`](./AGENTS.md) (`CLAUDE.md` is a symlink
to it).

## License

Apache-2.0. See [`LICENSE`](./LICENSE).

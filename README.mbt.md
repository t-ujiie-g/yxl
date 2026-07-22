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

> ⚠️ **Status: early development, pre-release (Phase 0).** The foundation is
> being laid; the compiler is not yet functional. See
> [`ROADMAP.md`](./ROADMAP.md) for the phase plan and the living changelog.

## A taste (target design)

```yaml
# report.yxl.yaml
workbook:
  sheets:
    - name: Sales
      cells:
        A1: { text: "Q3 Sales Report", style: title, merge: "A1:C1" }
        A3: { text: Region, style: header }
        B3: { text: Revenue, style: header }
        A4: { text: APAC }
        B4: { number: 2400000, format: "#,##0" }
        A5: { text: Total, style: bold }
        B5: { formula: "SUM(B4:B4)", format: "#,##0" }

styles:            # declared once, referenced by name → one style id each
  title:  { bold: true, size: 16, align: center }
  header: { bold: true, fill: "1F3864", color: "FFFFFF", align: center }
  bold:   { bold: true }
```

```bash
yxl build report.yxl.yaml -o report.xlsx
```

*(Schema is under design — see `ROADMAP.md §8`. The above shows the intended
shape, not a frozen contract.)*

## How it works

```
report.yxl.yaml
   → parse + validate (typed model, diagnostics with file/line)
   → resolve references + intern shared values / formulas / styles   ← the DRY engine
   → emit via a swappable backend (bobzhang/mbtexcel)
   → report.xlsx
```

The pipeline core is filesystem-free and unit-testable on strings and bytes; only
the CLI touches disk. The Excel backend sits behind a seam so it can be swapped
(see [`ROADMAP.md §7`](./ROADMAP.md), ADR-002).

## Packages

Target layout (see [`ROADMAP.md §4`](./ROADMAP.md) for the full map):

| Package | Purpose |
|---|---|
| `diag` | Diagnostics + subdomain errors with source spans |
| `units` | Type-safe cell references, colors, dimensions |
| `yaml` | YAML source → document tree |
| `model` | Typed intermediate representation |
| `loader` | Document tree → model, schema validation, includes |
| `resolve` | Named references + reuse/dedup interning |
| `emit` | Model → `.xlsx` bytes (mbtexcel-backed) |
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

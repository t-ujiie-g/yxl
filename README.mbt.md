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
- **Flexible structure** — split data and formatting across files with
  `$include`, feed a region straight from a CSV or JSON table, or inline
  everything in one file. Same result either way.
- **One spec, many workbooks** — declare `params:` and override them per build
  with `--set region=EMEA`.
- **A single native command** — `yxl build report.yxl.yaml -o report.xlsx`.

The `.xlsx` bytes are produced by the mature
[`bobzhang/mbtexcel`](https://mooncakes.io/docs/bobzhang/mbtexcel) library (a
MoonBit port of Go's excelize); `yxl` is the language, the reuse/dedup engine,
the validator, and the CLI on top. It is not another spreadsheet *library* — it
is declarative authoring for people who'd rather edit YAML than write code.

> ⚠️ **Status: pre-release, schema not yet frozen.** `yxl build` works today —
> values, formulas, dates, rich text, styles, layout, print setup, multi-file
> specs, external CSV/JSON data, parameters, validations, conditional
> formatting, hyperlinks, notes, protection, Excel tables, charts, and images
> all compile, and the CLI has `--check`, `--set`, and stable exit codes. Still
> ahead: pivot tables and the schema freeze —
> **the schema may change until v1.0.** See [`ROADMAP.md`](./ROADMAP.md) for the
> phase plan and the living changelog.

## A taste

```yaml
# report.yxl.yaml
params:                      # overridable per build with --set
  region: APAC
  quarter: Q3

defs:                        # declared once, referenced by name
  styles:
    base:   { font: { name: Calibri, size: 11 } }
    title:  { extends: base, font: { bold: true, size: 16 } }
    header: { extends: base, font: { bold: true, color: "FFFFFF" }, fill: "1F3864" }
    total:  { extends: base, font: { bold: true } }

sheets:
  - name: "${region}"
    freeze: A4               # the header rows stay put while the data scrolls
    merges: [A1:B1]
    columns:
      - at: A
        width: 18
      - at: B
        width: 14
        format: "#,##0"      # a whole-column default format
    cells:
      A1: { value: "${quarter} ${region} sales", style: title }
      A3: { value: Region, style: header }
      B3: { value: Revenue, style: header }
      A7: { value: Total, style: total }
      B7: { formula: "SUM(B4:B6)", style: total }
    data:
      - at: A4
        csv: data/sales.csv  # the rows come from a file the spec never restates
    print:
      area: A1:B7
      orientation: landscape
      fit: { width: 1 }      # shrink to one page across
```

```bash
yxl build report.yxl.yaml -o q3-apac.xlsx
yxl build report.yxl.yaml -o q4-emea.xlsx --set region=EMEA --set quarter=Q4
```

Each declared style compiles to a **single** Excel style id however many cells
wear it, and each `defs.values` entry to a **defined name** — so editing it in
Excel updates every reference. An unknown key, a bad cell reference, a dangling
`$ref`, or a cycle among includes, styles, or parameters fails the build with a
diagnostic naming the file, never a silently dropped value.

## Install

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.sh | sh
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.ps1 | iex
```

Either fetches the [latest release](https://github.com/t-ujiie-g/yxl/releases)
for your platform, **verifies its SHA-256**, and installs `yxl` — into
`~/.local/bin`, or `%LOCALAPPDATA%\yxl\bin` on Windows. Pin a version or choose
a directory with `YXL_VERSION` and `YXL_INSTALL_DIR`:

```bash
YXL_VERSION=0.1.0 YXL_INSTALL_DIR=/usr/local/bin \
  curl -fsSL https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.sh | sh
```

Prebuilt binaries cover **Linux x86_64**, **macOS arm64** (Apple silicon), and
**Windows x86_64**. On an Intel Mac, or any other platform, build from source
below. Piping
a script into a shell is worth doing deliberately — [read
`install.sh`](./install.sh) first if you would rather, or install by hand from
the release assets, or build from source:

### From source

With [MoonBit](https://www.moonbitlang.com/download) installed:

```bash
git clone https://github.com/t-ujiie-g/yxl.git
cd yxl
moon build --target native --release
install -m 755 _build/native/release/build/cmd/main/main.exe ~/.local/bin/yxl
```

macOS marks downloaded binaries as quarantined; if Gatekeeper objects, clear it
with `xattr -d com.apple.quarantine ~/.local/bin/yxl`.

Paths may use either separator, so `yxl build specs\report.yaml` works on
Windows and a spec's own `$include: data/x.yaml` stays portable.

**One Windows limitation:** the *command line* cannot carry non-ASCII today —
`yxl build 売上\report.yaml` fails, because the runtime reads arguments as UTF-8
while Windows hands them over in the system code page
([upstream](https://github.com/moonbitlang/x): "TODO: Handle other encodings").
Paths *inside* a spec are unaffected — `$include: 表/theme.yaml` and
`csv: 売上/data.csv` work, since those come from the file, which is UTF-8. So
name the spec you pass on the command line in ASCII; everything it refers to can
be in any script.

## Using it

```bash
yxl build report.yxl.yaml -o report.xlsx     # compile
yxl build report.yxl.yaml --check            # validate, write nothing
yxl build report.yxl.yaml -o r.xlsx --set region=EMEA
yxl help                                     # full usage
```

The full schema is in [`docs/spec.md`](./docs/spec.md).

Exit codes are stable across releases:

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | the spec is invalid, or a file could not be read or written |
| `2` | the command line itself was wrong |

## Examples

[`examples/`](./examples) is a worked cookbook, and CI compiles every file in it
so the pages cannot drift from the compiler:

| Example | Shows |
|---|---|
| [`quickstart.yxl.yaml`](./examples/quickstart.yxl.yaml) | cell kinds, number formats, a formula |
| [`styling.yxl.yaml`](./examples/styling.yxl.yaml) | declare-once styles, `extends`, defined names, rich text, conditional formatting |
| [`layout.yxl.yaml`](./examples/layout.yxl.yaml) | merges, frozen headers, sized and grouped bands, sheet visibility, print setup, document properties, an image |
| [`modular.yxl.yaml`](./examples/modular.yxl.yaml) | `$include`, CSV / JSON `data:`, and an Excel table over the region they fill |
| [`parameters.yxl.yaml`](./examples/parameters.yxl.yaml) | `params:` with `${}` and `--set` |
| [`interactive.yxl.yaml`](./examples/interactive.yxl.yaml) | drop-downs and other validations, an auto filter, hyperlinks, notes |
| [`charts.yxl.yaml`](./examples/charts.yxl.yaml) | column, pie, and bar charts, series named from cells, one plotting another sheet |

```bash
yxl build examples/quickstart.yxl.yaml -o quickstart.xlsx
```

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
| `examples` | Test-only: compiles the `examples/` cookbook and asserts on it |

## Development

```bash
moon check --deny-warn      # type check
moon test                   # tests
moon fmt                    # format
moon info                   # regenerate the .mbti interface files
moon build --target native  # build the CLI
```

`main` is protected: land changes through a pull request, and CI must be green.
Tagging a commit `vX.Y.Z` builds the binaries and publishes the release — the
tag, `moon.mod`, and the version `yxl version` reports must agree, or the release
job stops before building.

Direction, phase scope, architecture decisions (ADRs), and the changelog all
live in the single source of truth, [`ROADMAP.md`](./ROADMAP.md). Contributor and
AI-agent conventions are in [`AGENTS.md`](./AGENTS.md) (`CLAUDE.md` is a symlink
to it); the spec format is [`docs/spec.md`](./docs/spec.md).

## License

Apache-2.0. See [`LICENSE`](./LICENSE).

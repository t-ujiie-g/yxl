---
name: yxl-authoring
description: Build and maintain Excel workbooks as yxl specs (*.yxl.yaml). Use when the user wants an .xlsx generated from YAML, wants a spreadsheet under version control, asks to create a report/workbook with yxl from scratch, or asks to edit, review, refresh, or troubleshoot an existing yxl spec. Covers the authoring workflow, the reuse patterns the format is built around, the edit-and-verify loop, and month-to-month operation. For migrating an existing .xlsx into a spec, see the extract-to-spec skill.
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

## Writing a spec from scratch

Start minimal and grow it under `--check`; do not draft a hundred lines and
debug them in one go.

1. **Skeleton first.** One sheet, a few `cells:`, `yxl build --check`. A spec
   is a mapping with one required key (`sheets:`, §1); everything else is
   opt-in.
2. **Data before decoration.** Lay in the values and formulas, then style.
   - A rectangle of rows is a `data:` entry (§9) — inline `values:` for small
     tables (diffs one line per row), `csv:`/`json:` for data that arrives
     from elsewhere. `cells:` is for scattered, individually-styled cells.
   - A calculation column is **one** `formulas:` range (§3), not N near-equal
     cells: `{ at: E2:E500, formula: "C2*D2" }` — the formula translates down
     the range like Excel's own fill.
3. **Declare once, reference everywhere (§6).** Anything used twice gets a
   name in `defs:` — styles (referenced by bareword), values and formulas
   (`{ $ref: name }`). This is not just tidiness: yxl compiles the sharing to
   Excel's native mechanisms (one style id, a defined name), so the file also
   gets smaller and Excel shows the name.
4. **Per-issue values are `params:` (§7).** The reporting month, a region, a
   title — `${name}` in the spec, `--set name=value` at build time. A lone
   `${n}` placeholder keeps the parameter's type; embedded in text it
   interpolates.
5. **Split when it earns it (§8).** `{ $include: path }` can replace any node.
   Split along what changes together (styles vs data vs layout), not by size.
6. **Layout is bands (§4)**, not per-cell settings: column widths, row
   heights, hidden ranges, outline groups. Merges, freeze/split panes, tab
   colours, and print setup are sheet keys (§2, §5).
7. Richer features each have a section and an example: validations, links,
   notes, conditional formatting (§10), Excel tables (§11), charts (§12),
   images (§13), pivots (§14), protection (§16), shapes (§18), sparklines
   (§19), form controls (§20), slicers (§21). Copy the shape from
   `examples/*.yxl.yaml` rather than improvising.

## Editing an existing spec

- **Read `defs:` before touching cells.** A look or value used across the
  workbook is defined once; edit the definition, not the forty places it
  lands. Conversely, never paste an inline copy of something `defs:` already
  names — that forks the single source the format exists to keep.
- **Respect the spec's own idiom.** If tables are `values:` rows, add a row,
  not a `cells:` entry; if a column is a `formulas:` range, widen `at:`
  instead of appending one-off formula cells. Keep the diff the shape a
  reviewer expects.
- **Sheet keys apply in written order** (§2): where a `data:` table and
  `cells:` overlap, the later key wins. Check ordering before "fixing" a value
  that seems ignored.
- **Renames are global.** A `defs` name or sheet name is referenced by text
  (`$ref`, formulas, `active:`); rename with a project-wide search, then
  `--check`.
- Run `yxl build --check` after every meaningful edit. Diagnostics name the
  file and the construct (`sheet 'Sales' cell 'B2' …`) — trust them over
  guessing. Some refusals are deliberate and documented: workbook-level
  `protect:` (backend defect, §16), shape geometries whose token carries a
  capital (§18), pivot layouts the backend miswrites (§14). Do not work
  around a refusal by dropping the feature silently — tell the user what was
  refused and why.

## Operating a spec month to month

The steady state a spec should reach: **refresh = data swap, redesign = spec
diff.**

- Data that arrives monthly lives in CSV/JSON files a `data:` entry names —
  replacing the file is the whole refresh. The issue date, title, and other
  per-run values are `params:` set at build time.
- Rebuild and spot-open the output. The compile is deterministic, but features
  Excel *interprets* (charts, pivots, conditional rules) deserve one human
  glance after a data shape changes — e.g. a `formulas:` or conditional range
  that no longer covers new rows. Ranges do not grow with data; widening them
  is a spec edit.
- Keep generated `.xlsx` out of version control; the spec and its data files
  are the source of truth. A CI job that runs `yxl build --check` (or a full
  build) on every change catches a broken spec before the month-end rush.
- Formula *results* are not in the file until Excel opens it — yxl emits, Excel
  computes. Do not chase "empty" formula cells in the raw bytes.

## Migrating an existing workbook

`yxl extract` turns an `.xlsx` into a starting spec, and the **extract-to-spec
skill** is the rewrite workflow that follows — classifying report vs data
sheets, restoring formula ranges the file could not keep, naming styles, and
verifying the result. Use it whenever the starting point is an existing
workbook rather than a blank page.

## Verify before calling it done

```bash
yxl build spec.yxl.yaml -o out.xlsx   # exit 0, no diagnostics
```

then open `out.xlsx` once in Excel or LibreOffice: no repair dialog, formulas
compute, the layout reads as intended. Exit codes are stable: `0` success, `1`
invalid spec or I/O failure, `2` bad command line.

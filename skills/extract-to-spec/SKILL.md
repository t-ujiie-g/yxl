---
name: extract-to-spec
description: Turn an existing Excel workbook (.xlsx) into a maintainable yxl spec. Use when the user wants a workbook under version control, wants to migrate a hand-maintained .xlsx to YAML, or has run `yxl extract` and asks what to do with its output. Covers classifying report sheets against data sheets, restoring formula ranges the file could not keep, naming styles, moving pasted data out to CSV, and verifying the rewrite compiles back to the workbook it came from.
---

# extract-to-spec: from a workbook to a spec you can maintain

`yxl extract` is a one-way migration aid: it recovers everything the yxl spec
format can express and names every drop. Its output is **correct but too
literal to maintain** — a real workbook extracts to megabytes of YAML, because
the file has already lost the structure a human would keep (which cells share
one formula, which sheets are pasted data, what a style *means*). This skill is
the rewrite that puts the structure back. The goal is a spec where a monthly
refresh is a CSV swap and a `git diff` of the spec reads as a list of design
decisions.

Ground truth for every schema detail is `docs/spec.md` in the yxl repository
(<https://github.com/t-ujiie-g/yxl>); section numbers below refer to it. Do not
guess schema keys — unknown keys are hard errors by design. This skill is the
*migration*; authoring from scratch and the month-to-month operation of a
finished spec are the **yxl-authoring** skill's territory, and once the rewrite
below is verified, hand over to it.

## The shape of the work

1. Extract, and read the loss report before the YAML.
2. Classify each sheet: **report** (designed) or **data** (pasted).
3. Data sheets become `data:` + CSV.
4. Report sheets get their structure back: `formulas:` ranges, named styles,
   bands.
5. Decide what the workbook-level leftovers mean: defined names, properties.
6. Verify: compile, re-extract, compare, and open the result in Excel.

Work sheet by sheet; keep the extracted output as the reference until the
rewrite of a sheet is verified, then delete the literal version of that sheet.

## 1. Extract, and read the report

```sh
yxl extract workbook.xlsx -o spec.yxl.yaml
```

- Plain-value rectangles land as CSVs beside the spec automatically; styled or
  formula-bearing sheets stay inline.
- **Every `dropped:` line is a decision the rewrite must make**, not noise.
  Typical drops and what to do:
  - *print setup* — not recoverable; re-add a `print:` block (§5) by hand where
    a sheet is actually printed.
  - *theme/palette colour* — pick the concrete `RRGGBB` the workbook shows and
    put it in the style.
  - *a conditional rule with nothing to apply* — the original rule changed
    nothing visible; usually delete-and-forget, occasionally a sign the rule's
    look lived in a theme colour worth restoring by hand.
  - *sheet-local defined names* — often legacy junk; see step 5.
- The final line matters: `everything else rebuilds the workbook as read`
  means the spec is a faithful starting point. A verify failure is reported
  per cell — investigate before rewriting on top of it.

## 2. Classify the sheets

Look at each sheet and decide which kind it is; the two kinds get opposite
treatments.

- **Data sheet**: a rectangle of values pasted from some source system —
  export dumps, last year's copy, master tables. Tell-tales: no formulas or a
  single derived column, uniform styling, hundreds-to-thousands of rows,
  often a `<name>` / `<name> (previous year)` pair.
- **Report sheet**: the designed surface — KPI grids, dashboards. Tell-tales:
  formulas everywhere (lookups into the data sheets), conditional formatting,
  merges, per-cell styling, print-shaped layout.

A sheet that mixes both (a data rectangle plus a derived column) is a data
sheet whose derived column moves into the spec as a `formulas:` range over the
table's region.

## 3. Data sheets → `data:` + CSV (§9)

For each data sheet, replace its inline `cells:` block with an anchored table:

```yaml
- name: Visitors
  data:
    - { at: A1, csv: data/visitors.csv }
```

- Write the CSV from the extracted values (or better, from the source system's
  own export, which is what will refresh it next month).
- CSV fields are typed by what they look like; quote text that would read as a
  number or boolean (`"007"`). Small tables can stay inline as `values:` rows,
  which keep YAML's types and diff line-per-row.
- Headers with styling stay in `cells:`; sheet keys apply in written order, so
  put the `data:` entry after any `cells:` it should not overwrite (§2).
- If the sheet needs column widths or a frozen header row, that is `columns:`
  bands and `freeze:` (§4, §2) — three lines, not a reason to keep the sheet
  inline.

## 4. Report sheets: put the structure back

Rewrite these by hand, using the extracted YAML as the answer sheet.

- **Restore formula ranges (§3).** This is the single biggest compression, and
  the one extract cannot do for you: the file stores a shared formula only at
  its master cell, so extract recovers `E2` as the formula and `E3:E500` as
  the values it last computed. Delete the cached values and declare the fill:

  ```yaml
  formulas:
    - { at: E2:E500, formula: "IFERROR(C2*D2, \"\")" }
  ```

  Find the ranges by reading the master-cell formulas extract kept and asking
  "which block of cached values under it follows the same shape". Spot-check
  two or three rows against the original workbook before deleting.
- **Name the styles (§6).** Extract has already interned duplicates into
  `defs.styles` under neutral names (`style`, `style_2`, …) and descriptive
  ones where the evidence was strong (`header`, `percent`). Rename the ones
  the sheet's design actually means (`kpi_good`, `section_title`) — renaming
  means updating every reference, so do it before the spec grows. Delete
  entries nothing references.
- **Bands, not per-cell layout (§4).** Column widths, row heights, hidden
  ranges, and outline levels are `columns:` / `rows:` bands; extract already
  collapsed equal neighbours, so mostly this is keeping what it wrote.
- **Keep the decorations declarative.** Conditional formats, validations,
  merges, filters, and freeze panes all have spec forms (§10); extract
  recovers them, so review rather than rewrite. Re-add the dropped `print:`
  blocks here.

## 5. Workbook-level leftovers

- **Defined names**: a workbook that has lived for years carries hundreds of
  dead names (`#REF!` targets, auto-generated `_xlnm` leftovers). Keep the
  ones formulas actually use — as `defs.values` / `defs.formulas` entries with
  meaningful names — and drop the rest deliberately. Extract does not recover
  sheet-local names; if one matters, widen it into a workbook-wide definition
  and note the change.
- **Parameters (§7)**: a value that changes per issue of the workbook (the
  reporting month, a title) is a `params:` entry substituted as `${name}`,
  which is what makes next month's file a one-line change or a `--set` flag.
- **Split the spec when it earns it (§8)**: `{ $include: path }` moves a
  sheet or a `defs:` block into its own file. Split along what changes
  together — styles that never change apart from design work, data blocks that
  change monthly.

## 6. Verify

```sh
yxl build spec.yxl.yaml -o rebuilt.xlsx
yxl extract rebuilt.xlsx -o check.yxl.yaml   # should verify clean
```

- Compare `check.yxl.yaml` against an extraction of the original where the
  rewrite claims equivalence — values and formulas should match; deliberate
  cleanups (dead names, do-nothing rules) are the diff you expect to see.
- Formula ranges compile to *shared* formulas, so the rebuilt file stores one
  formula where the original stored one — but the followers' cached values are
  gone until Excel opens the file. **Open `rebuilt.xlsx` in Excel** (or
  LibreOffice) once: formulas recompute, lookups resolve, nothing shows `#REF!`
  or a repair dialog.
- From then on, the spec is the source of truth: data refresh = replace the
  CSVs; design change = edit the spec and re-review the diff.

## Scope honesty

Things that do not survive extraction and are not restored by this skill:
charts and pivots (declare them fresh from §12/§14 if the workbook needs
them), VBA/macros (out of yxl's scope entirely), and the exact saved state of
filters (a view, not a description). Say so in the handover rather than
leaving them to be discovered.

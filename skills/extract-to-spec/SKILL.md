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

**The destination is that skill's *default architecture*** — an entry file that
is a table of contents, one file per sheet, the look named once, shared data
held in one master every other sheet references, and per-issue values in
`params:`. Read it before starting, and rewrite *towards* it: a migration that
lands somewhere else has spent its one chance to restructure. Unless the user
asks for a different shape, in which case build theirs.

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

Needs the `yxl` CLI (`yxl version` to check) — the yxl-authoring skill's
*Prerequisite* section has the install one-liners if it is missing.

```sh
yxl extract workbook.xlsx -o spec.yxl.yaml
```

- Plain-value rectangles land as CSVs beside the spec automatically; styled or
  formula-bearing sheets stay inline.
- **Every `dropped:` line is a decision the rewrite must make**, not noise.
  Typical drops and what to do:
  - *print setup* — not recoverable; re-add a `print:` block (§5) by hand where
    a sheet is actually printed.
  - *theme/palette colour* — fonts and fills resolve theirs to RGB
    automatically; this line means a colour the workbook's own theme does not
    define. Pick the concrete `RRGGBB` the workbook shows and put it in the
    style.
  - *a conditional rule with nothing to apply* — the original rule changed
    nothing visible; usually delete-and-forget, occasionally a sign the rule's
    look lived in a colour the theme could not resolve.
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
- **Look for the same list in more than one sheet** before writing the CSVs:
  the store names, the account codes, the region list. A hand-maintained
  workbook copies them, and drift between the copies is usually one of the bugs
  the migration is meant to fix. They become **one** master sheet with one CSV,
  declared an Excel table; the sheets that used a copy get a lookup against its
  name, or a drop-down sourced `from:` its cells. Confirm the copies really are
  the same list — where they differ, say which one you kept.

## 4. Report sheets: put the structure back

Rewrite these by hand, using the extracted YAML as the answer sheet.

- **Fold the remaining formula runs into ranges (§3).** Extract already writes
  a `formulas:` range wherever the file stored a shared formula over an
  unstyled block. What it leaves cell by cell is a run whose cells carry their
  own style — a `formulas:` range holds no styling, so it cannot fold one —
  and any column Excel wrote out formula by formula in the first place. Both
  look the same in the output: a column of `formula:` entries that differ only
  by row.

  ```yaml
  formulas:
    - { at: E2:E500, formula: "IFERROR(C2*D2, \"\")" }
  ```

  Move the styling to a `columns:` band (§4), which reaches every cell the
  range fills, then declare the fill. Spot-check two or three rows against the
  original workbook before deleting the per-cell entries.
- **Name the styles (§6).** Extract has already interned duplicates into
  `defs.styles` under neutral names (`style`, `style_2`, …) and descriptive
  ones where the evidence was strong (`header`, `percent`). Rename the ones
  the sheet's design actually means (`kpi_good`, `section_title`) — renaming
  means updating every reference, so do it before the spec grows. Delete
  entries nothing references.
- **Bands, not per-cell layout (§4).** Column widths, row heights, hidden
  ranges, and outline levels are `columns:` / `rows:` bands; extract already
  collapsed equal neighbours, so mostly this is keeping what it wrote. One
  thing to trim: a `width:` extract wrote for a column the original left at
  Excel's default (§22) — keeping it stops Excel auto-fitting that column.
  Suspect any band that is a bare `width:` on a column whose look is otherwise
  untouched.
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
- **The cells that resist becoming a rule are `overrides:` (§23)**, not the
  reason to abandon the rule. Every migration turns up a few: the row somebody
  hard-coded over a formula column, the one cell that ignores the parameter.
  Write the range or the parameter as the rule really is, then lift each holdout
  into a top-level `{ at: Sheet!E37, …, reason: … }` — with the reason you found
  in the original workbook, or a note that you could not find one. That block is
  the migration's own decision list, and it stays legible after you have gone.
- **Split the spec into the house layout (§8)**: `{ $include: path }` moves a
  sheet or a `defs:` block into its own file, leaving an entry spec that is a
  table of contents. A real workbook is past the size where one file is
  defensible, so this is the last step of every migration, not an optional one —
  `examples/workbook.yxl.yaml` is the shape to land on.

## 6. Verify

```sh
yxl build spec.yxl.yaml -o rebuilt.xlsx
yxl extract rebuilt.xlsx -o check.yxl.yaml   # should verify clean
```

- Compare `check.yxl.yaml` against an extraction of the original where the
  rewrite claims equivalence — values and formulas should match; deliberate
  cleanups (dead names, do-nothing rules) are the diff you expect to see.
- Formula ranges compile to *shared* formulas, so the rebuilt file stores one
  formula where the original stored one — but no cached values, so every
  calculated cell is empty until Excel opens the file. **Open `rebuilt.xlsx` in
  Excel** (or LibreOffice) once: formulas recompute, lookups resolve, nothing
  shows `#REF!` or a repair dialog.
- From then on, the spec is the source of truth: data refresh = replace the
  CSVs; design change = edit the spec and re-review the diff.

## Scope honesty

Things that do not survive extraction and are not restored by this skill:
pivots (declare them fresh from §14 if the workbook needs them), VBA/macros
(out of yxl's scope entirely), and the exact saved state of filters (a view,
not a description). Say so in the handover rather than leaving them to be
discovered.

**Charts do come back**, but read the loss report for them specifically: one
the schema cannot express — a combination chart, a stacked line, a kind outside
§12 — is refused whole and named, so a workbook whose charts matter may come
back with fewer than it had. Redeclare those from §12 rather than assuming the
count matched.

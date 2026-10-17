///|
/// A cell: a scalar shorthand or an expanded mapping (`docs/spec.md` §3).
fn load_cell(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
  defs~ : Defs,
) -> (@model.CellValue, @model.Style?) raise @diag.SchemaError {
  match node {
    // `A1: { $ref: name }` is the whole-cell shorthand for a named value.
    @yaml.Map(_) if as_ref(node) is Some(name) =>
      (resolve_value_ref(name, file~, reference~, defs~), None)
    @yaml.Map(entries) => load_expanded_cell(entries, file~, reference~, defs~)
    scalar => (scalar_value(scalar, file~, context="cell '\{reference}'"), None)
  }
}

///|
/// The keys the expanded form of a cell takes. An `overrides:` entry carries the
/// same grammar, so it reads them from here rather than repeating the list.
let cell_keys : Array[String] = [
  "value", "formula", "rich", "type", "format", "style",
]

///|
/// Those keys as a diagnostic's expected-list, after any its own construct adds
/// in front of them.
fn expected_cell_keys(before~ : Array[String] = []) -> String {
  or_list([..before, ..cell_keys].map(key => "'\{key}'"))
}

///|
fn load_expanded_cell(
  entries : Array[(String, @yaml.Node)],
  file~ : String,
  reference~ : String,
  defs~ : Defs,
) -> (@model.CellValue, @model.Style?) raise @diag.SchemaError {
  let mut value_node = None
  let mut type_ = None
  let mut format = None
  let mut format_cleared = @model.StyleAttrs::none()
  let mut formula = None
  let mut style_node = None
  let mut rich_node = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "value" => value_node = Some(node)
      "type" =>
        type_ = Some(
          expect_string(node, file~, context="cell '\{reference}' type"),
        )
      "format" => {
        let (code, cleared) = load_format(
          node,
          file~,
          context="cell '\{reference}' format",
        )
        format = code
        format_cleared = cleared
      }
      "formula" =>
        formula = Some(resolve_formula(node, file~, reference~, defs~))
      "style" => style_node = Some(node)
      "rich" => rich_node = Some(node)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in cell '\{reference}' (expected \{expected_cell_keys()})",
        )
    }
  }
  let (value, number_format) = if rich_node is Some(rich) {
    guard formula is None else {
      raise schema_error(
        file~,
        "cell '\{reference}' cannot combine 'rich' and 'formula'",
      )
    }
    guard value_node is None else {
      raise schema_error(
        file~,
        "cell '\{reference}' cannot combine 'rich' and 'value'",
      )
    }
    guard type_ is None else {
      raise schema_error(
        file~,
        "cell '\{reference}' cannot combine 'rich' and 'type'",
      )
    }
    (load_rich_text(rich, file~, reference~), format)
  } else {
    match formula {
      Some(formula) => {
        guard type_ is None else {
          raise schema_error(
            file~,
            "cell '\{reference}' cannot combine 'formula' and 'type'",
          )
        }
        let cached = match value_node {
          Some(node) =>
            Some(scalar_value(node, file~, context="cell '\{reference}'"))
          None => None
        }
        (@model.Formula(formula=strip_leading_equals(formula), cached~), format)
      }
      None => {
        guard value_node is Some(value_node) else {
          // A cell with a look and nothing in it: a shaded box, the ruled edge
          // of a table, the blank half of a merged heading. It stays blank to
          // `ISBLANK` and to `COUNTA` — the styling is all that is being asked
          // for, and `value: ""` would be a different cell.
          guard style_node is Some(_) ||
            format is Some(_) ||
            !format_cleared.is_empty() else {
            raise schema_error(
              file~,
              "cell '\{reference}' needs a 'value', a 'formula', or a 'style'",
            )
          }
          guard type_ is None else {
            raise schema_error(
              file~,
              "cell '\{reference}' cannot give a 'type' with no value to apply it to",
            )
          }
          return (
            @model.Blank,
            combine_style(
              style_node,
              format,
              file~,
              defs~,
              context="cell '\{reference}'",
              cleared=format_cleared,
            ),
          )
        }
        if as_ref(value_node) is Some(name) {
          // A `{ $ref: name }` value reuses a named definition; the cell's own
          // `format`/`style` still layer on via `combine_style` below.
          guard type_ is None else {
            raise schema_error(
              file~,
              "cell '\{reference}' cannot combine a '$ref' value with 'type'",
            )
          }
          (resolve_value_ref(name, file~, reference~, defs~), format)
        } else {
          let value = scalar_value(
            value_node,
            file~,
            context="cell '\{reference}'",
          )
          match type_ {
            None => (value, format)
            Some(name) => {
              let type_ = parse_value_type(
                name,
                file~,
                context="cell '\{reference}'",
                errors=true,
              )
              let value = type_.read(value, file~, place="cell '\{reference}'")
              (
                value,
                match format {
                  Some(_) => format
                  None => type_.default_format(value)
                },
              )
            }
          }
        }
      }
    }
  }
  (
    value,
    combine_style(
      style_node,
      number_format,
      file~,
      defs~,
      context="cell '\{reference}'",
      cleared=format_cleared,
    ),
  )
}

///|
/// Parse a cell's `rich:` sequence into a rich-text value: an ordered list of
/// runs, each a plain string or a `{ text, font }` mapping. Needs at least one
/// run.
fn load_rich_text(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.CellValue raise @diag.SchemaError {
  let items = match node {
    @yaml.Seq(items) => items
    _ =>
      raise schema_error(
        file~,
        "cell '\{reference}' rich text must be a sequence of runs",
      )
  }
  guard !items.is_empty() else {
    raise schema_error(
      file~,
      "cell '\{reference}' rich text needs at least one run",
    )
  }
  let runs = []
  for item in items {
    runs.push(load_rich_run(item, file~, owner="cell '\{reference}'"))
  }
  @model.RichText(runs)
}

///|
/// One rich-text run: a plain string (no font) or a `{ text, font }` mapping.
/// `owner` names the construct the run belongs to (`cell 'A1'`,
/// `shape at 'B2'`) in the diagnostics.
fn load_rich_run(
  node : @yaml.Node,
  file~ : String,
  owner~ : String,
) -> @model.RichRun raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => { text, font: None, }
    @yaml.Map(entries) => {
      let mut text = None
      let mut font = None
      for entry in entries {
        let (key, node) = entry
        match key {
          "text" =>
            text = Some(
              expect_string(
                node,
                file~,
                context="\{owner} rich text run 'text'",
              ),
            )
          "font" => {
            let (loaded, cleared) = load_font(
              node,
              file~,
              context="\{owner} rich text run",
            )
            guard cleared.is_empty() else {
              raise schema_error(
                file~,
                "\{owner} rich text run font cannot clear an attribute with null — a run inherits nothing",
              )
            }
            font = Some(loaded)
          }
          _ =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in \{owner} rich text run (expected 'text' or 'font')",
            )
        }
      }
      guard text is Some(text) else {
        raise schema_error(file~, "\{owner} rich text run needs a 'text'")
      }
      { text, font, }
    }
    _ =>
      raise schema_error(
        file~,
        "\{owner} rich text run must be text or a mapping",
      )
  }
}

///|
/// Excel stores formulas without the leading `=`; accept a spec that writes one.
fn strip_leading_equals(formula : String) -> String {
  if formula.has_prefix("=") {
    formula[1:].to_owned()
  } else {
    formula
  }
}

///|
/// Interpret a scalar node as a cell value. A non-scalar here (a nested sequence
/// or mapping in a `value:`) is an error.
fn scalar_value(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.CellValue raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => @model.Text(text)
    @yaml.Int(number) => @model.Number(number.to_double())
    @yaml.Float(number) => @model.Number(number)
    @yaml.Bool(flag) => @model.Bool(flag)
    @yaml.Null | @yaml.Seq(_) | @yaml.Map(_) =>
      raise not_scalar(file~, context~)
  }
}

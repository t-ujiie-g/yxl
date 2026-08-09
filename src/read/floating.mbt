///|
/// The form controls on a sheet.
fn read_controls(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit raise {
  for control in backend.get_form_controls(sheet.name) {
    if read_control(control, notes) is Some(recovered) {
      sheet.add_control(recovered)
    }
  }
}

///|
/// One form control, or `None` where it sits nowhere the schema can name.
fn read_control(
  control : @xlsx.FormControl,
  notes : Notes,
) -> @model.FormControl? {
  guard @units.CellRef::parse_a1(control.cell) is Some(at) else { return None }
  // The backend canonicalizes the VML's `ObjectType` to exactly these seven,
  // and refuses to build a control from anything else — a list or combo box
  // never reaches us at all, which is why there is nothing to note here.
  let kind : @model.FormControlKind = match control.control_type {
    "Button" => Button
    "CheckBox" => CheckBox
    "OptionButton" => OptionButton
    "ScrollBar" => ScrollBar
    "SpinButton" => SpinButton
    "GroupBox" => GroupBox
    "Label" => Label
    other => {
      notes.drop(
        "a form control of type '\{other}', which the spec cannot name",
      )
      return None
    }
  }
  // Excel's own "Format Control" dialog shows a different set of fields per
  // kind and the schema follows it, so each is kept only where it means
  // something. What is kept is what the loader would accept, not what the file
  // holds.
  let on = control.control_type
  let ranged = kind is (ScrollBar | SpinButton)
  let text = keep(
    if control.text.is_empty() {
      None
    } else {
      Some(control.text)
    },
    !ranged,
    "text",
    on~,
    notes,
  )
  let checked = keep(
    control.checked,
    kind is (CheckBox | OptionButton),
    "checked",
    on~,
    notes,
  )
  let link = match
    keep(
      control.cell_link,
      ranged || kind is (CheckBox | OptionButton),
      "link",
      on~,
      notes,
    ) {
    // A qualified reference is not one the schema takes: it writes into a cell
    // on the control's own sheet.
    Some(reference) => @units.CellRef::parse_a1(reference)
    None => None
  }
  let mut min = keep(control.min_val, ranged, "min", on~, notes)
  let mut max = keep(control.max_val, ranged, "max", on~, notes)
  // The loader refuses a range that runs backwards, so a file holding one loses
  // both bounds rather than producing a spec that will not load.
  if min is Some(low) && max is Some(high) && low > high {
    notes.drop(
      "a form control's 'min' above its 'max', which the spec refuses as a range that runs backwards",
    )
    min = None
    max = None
  }
  // The size lives in the VML anchor's *far* corner, and the backend's parser
  // reads the anchor's first two coordinates only, so a control comes back
  // without a size whatever it was given. The note says *any* size because a
  // control that was never sized loses nothing, and the two cannot be told
  // apart from here.
  if control.width is None && control.height is None {
    notes.drop(
      "any size on a form control, which the file records in its VML and the Excel backend does not read back — a control comes back at Excel's default size, and one that was sized cannot be told from one that was not",
    )
  }
  Some({
    at,
    kind,
    text,
    checked,
    link,
    width: control.width,
    height: control.height,
    min,
    max,
    step: keep(control.inc_change, ranged, "step", on~, notes),
    page: keep(control.page_change, kind is ScrollBar, "page", on~, notes),
    value: keep(control.current_val, ranged, "value", on~, notes),
    horizontal: keep(control.horizontally, ranged, "horizontal", on~, notes),
  })
}

///|
/// A control's field where the schema allows it on that kind, and `None` — with
/// a note — where it does not. Writing one out anyway would produce a spec the
/// loader refuses, which is a worse answer than a spec that says less.
fn[T] keep(
  value : T?,
  allowed : Bool,
  what : String,
  on~ : String,
  notes : Notes,
) -> T? {
  guard value is Some(_) else { return None }
  guard !allowed else { return value }
  notes.drop(
    "'\{what}' on a form control that is a '\{on}', which the spec allows only on the kinds whose dialog offers it",
  )
  None
}

///|
/// The slicers on a sheet.
fn read_slicers(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit raise {
  for slicer in backend.get_slicers(sheet.name) {
    guard @units.CellRef::parse_a1(slicer.cell) is Some(at) else { continue }
    if slicer.table_name.is_empty() || slicer.source_name.is_empty() {
      // The schema names a slicer by the table and column it filters; without
      // both there is nothing to write down that would compile.
      notes.drop(
        "a slicer that names no table column, which the spec has no way to place",
      )
      continue
    }
    let sized = both_or_neither(
      slicer.width,
      slicer.height,
      default_slicer_size,
    )
    sheet.add_slicer({
      at,
      table: slicer.table_name,
      column: slicer.source_name,
      caption: if slicer.caption.is_empty() {
        None
      } else {
        Some(slicer.caption)
      },
      // 200 x 200 is the backend's own default, so saying it adds nothing and
      // an author who wrote it gets the same panel back either way.
      width: sized.0,
      height: sized.1,
      header: slicer.display_header,
    })
  }
}

///|
/// The defined names the workbook's slicers own.
///
/// A slicer's cache is a defined name the backend writes as part of placing it
/// (`Slicer_Region`), which the spec neither declares nor should: writing the
/// slicer back out writes the name back out too. The names come off the slicers
/// themselves rather than off the spelling convention, so a workbook whose
/// slicer names collided and were numbered is still recognised.
fn slicer_caches(backend : @xlsx.Workbook) -> @set.Set[String] {
  let caches : @set.Set[String] = Set([])
  for name in backend.get_sheet_list() {
    let slicers = backend.get_slicers(name) catch {
      // A sheet the backend will not answer for holds no name we could keep
      // out, and the read that follows raises for it in its own words.
      _ => continue
    }
    for slicer in slicers {
      if !slicer.cache.is_empty() {
        caches.add(slicer.cache)
      }
    }
  }
  caches
}

///|
/// The panel size the backend gives a slicer that asks for none.
let default_slicer_size : Int = 200

///|
/// A size worth writing down, as the pair the schema takes.
///
/// Both dimensions or neither: the schema refuses one alone, since it would
/// pair silently with the backend's default for the other. So a size equal to
/// that default in *both* dimensions is dropped, and one that differs in either
/// is kept whole.
fn both_or_neither(
  width : Int,
  height : Int,
  default_size : Int,
) -> (Int?, Int?) {
  if width == default_size && height == default_size {
    (None, None)
  } else {
    (Some(width), Some(height))
  }
}

///|
/// The shapes floating over a sheet.
fn read_shapes(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit {
  guard backend.sheet(sheet.name) is Some(source) else { return }
  let shapes = []
  for shape in source.shapes() {
    if read_shape(shape, notes) is Some(recovered) {
      shapes.push(recovered)
    }
  }
  // The backend answers in its own order; a spec is read top to bottom.
  shapes.sort_by((left, right) => {
    if left.at.row != right.at.row {
      left.at.row - right.at.row
    } else {
      left.at.col - right.at.col
    }
  })
  for shape in shapes {
    sheet.add_shape(shape)
  }
}

///|
/// One shape, or `None` where its geometry is not one the schema names.
fn read_shape(shape : @xlsx.Shape, notes : Notes) -> @model.Shape? {
  guard @units.CellRef::parse_a1(shape.cell) is Some(at) else { return None }
  guard preset_spelling(shape.shape_type) is Some(preset) else {
    // The backend lowercases the `prst` token on the way out, so a geometry
    // Excel spells with a capital — `roundRect`, `rightArrow` — comes back as a
    // token naming nothing, and there is no telling which one it was.
    notes.drop(
      "a shape whose geometry reads back as '\{shape.shape_type}', which names none the spec knows — the Excel backend lowercases the geometry token, so one spelled with a capital cannot be recovered",
    )
    return None
  }
  let text = read_shape_text(shape, notes)
  let line_color = read_color(Some(shape.line_color), notes)
  // The schema writes an outline as a colour, optionally with a width, so a
  // width over a colour the file left to the theme has nowhere to go.
  let line_width = if shape.line_width == default_shape_line_width {
    None
  } else if line_color is None {
    notes.drop(
      "a shape's outline width over an outline colour the file leaves to the theme, which the spec writes only as part of a colour",
    )
    None
  } else {
    Some(shape.line_width)
  }
  // The backend's own default is a 160-pixel square and a 1-point line, so
  // neither is worth writing down; an author who asked for them gets them.
  let sized = both_or_neither(shape.width, shape.height, default_shape_size)
  Some({
    at,
    preset,
    text,
    width: sized.0,
    height: sized.1,
    fill: read_color(Some(shape.fill_color), notes),
    line_color,
    line_width,
    alt_text: if shape.alt_text.is_empty() {
      None
    } else {
      Some(shape.alt_text)
    },
    positioning: match shape.positioning {
      OneCell => Move
      TwoCell => MoveAndSize
      Absolute => Fixed
    },
  })
}

///|
/// What a shape says. The backend keeps it as one paragraph run per line, and
/// hands the runs back stripped of their fonts.
fn read_shape_text(shape : @xlsx.Shape, notes : Notes) -> @model.ShapeText? {
  let lines = []
  for run in shape.paragraph {
    if run.font is Some(_) {
      // Unreachable today; see the note below, which claims the opposite.
      notes.drop("a font on a line of shape text, reported but not recovered")
    }
    lines.push(@model.RichRun::{ text: run.text, font: None })
  }
  if lines.is_empty() {
    // A shape written with a plain `text` rather than runs still comes back as
    // one run, so an empty paragraph really is a shape that says nothing.
    return if shape.text.is_empty() { None } else { Some(Plain(shape.text)) }
  }
  // The file records each line's font in `a:rPr`, and the backend's drawing
  // parser does not read it, so shape text comes back in the shape's default
  // font whatever it was set to — and, as with a control's size, text that was
  // never styled cannot be told from text that was.
  notes.drop(
    "any font on a line of shape text, which the file records and the Excel backend does not read back — a shape's text comes back unstyled, and one that was styled cannot be told from one that was not",
  )
  match lines {
    [only] => Some(Plain(only.text))
    _ => Some(Lines(lines))
  }
}

///|
/// The backend's default shape size in pixels, and its default outline width in
/// points.
let default_shape_size : Int = 160

///|
let default_shape_line_width : Double = 1.0

///|
/// The schema's spelling of a DrawingML preset token, or `None` for one it does
/// not name.
fn preset_spelling(token : String) -> String? {
  for preset in @model.shape_presets {
    if preset.1 == token {
      return Some(preset.0)
    }
  }
  None
}

///|
/// The sparkline groups on a sheet.
///
/// `qualified_ranges` says whether a data range could have named another sheet
/// — false for a one-sheet workbook, where nothing can have been lost.
fn read_sparklines(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  qualified_ranges~ : Bool,
  notes : Notes,
) -> Unit {
  guard backend.sheet(sheet.name) is Some(source) else { return }
  for group in source.sparkline_groups() {
    if read_sparkline_group(group, qualified_ranges~, notes) is Some(recovered) {
      sheet.add_sparkline_group(recovered)
    }
  }
}

///|
/// One group, or `None` where it plots nothing the schema can place.
fn read_sparkline_group(
  group : @xlsx.SparklineGroup,
  qualified_ranges~ : Bool,
  notes : Notes,
) -> @model.SparklineGroup? {
  let cells : Array[@model.SparklineCell] = []
  for sparkline in group.sparklines {
    guard @units.CellRef::parse_a1(sparkline.location) is Some(at) else {
      continue
    }
    guard @model.CellRange::parse(sparkline.range_ref) is Some(range) else {
      notes.drop(
        "a sparkline plotting '\{sparkline.range_ref}', which is not a range the spec can name",
      )
      continue
    }
    cells.push({ at, data: { sheet: None, range } })
  }
  guard !cells.is_empty() else { return None }
  if qualified_ranges {
    // The file writes `'Data'!B2:E2`, and the backend's reader keeps only what
    // follows the `!`. A sparkline that plotted another sheet is therefore
    // indistinguishable from one that plotted this one, and would come back
    // pointing at whatever happens to sit at those cells here.
    notes.drop(
      "the sheet a sparkline plots from, which the Excel backend strips off the range it reads back — a sparkline that plotted another sheet comes back plotting this one",
    )
  }
  let kind : @model.SparklineKind = match group.sparkline_type {
    Line => Line
    Column => Column
    WinLoss => WinLoss
  }
  let options = group.options
  // Markers and a line weight belong to a line sparkline; the schema refuses
  // them elsewhere, following Excel's own dialog.
  let line = kind is Line
  let markers = options.markers && line
  let weight = if line { options.line_weight } else { None }
  if (options.markers && !line) || (options.line_weight is Some(_) && !line) {
    notes.drop(
      "a marker or line weight on a sparkline that is not a line, which the spec allows only on the kind that draws one",
    )
  }
  let mut min = options.manual_min
  let mut max = options.manual_max
  if min is Some(low) && max is Some(high) && low > high {
    notes.drop(
      "a sparkline's 'min' above its 'max', which the spec refuses as a range that runs backwards",
    )
    min = None
    max = None
  }
  Some({
    kind,
    cells,
    markers,
    high: options.high,
    low: options.low,
    min,
    max,
    weight,
    // A colour the file names by theme is one the spec cannot write down; only
    // a plain `rgb` is a colour in its own right. An unset sparkline colour is
    // always a theme one, so this is also what keeps the defaults out.
    color: sparkline_color(options.color_series, notes),
    markers_color: sparkline_color(options.color_markers, notes),
    high_color: sparkline_color(options.color_high, notes),
    low_color: sparkline_color(options.color_low, notes),
    axis: options.display_x_axis,
  })
}

///|
/// A sparkline colour, and only where the file names one outright.
///
/// The theme index beside it is deliberately *not* resolved, unlike a font's or
/// a fill's: Excel gives every sparkline group four colours it never asked for
/// — high, low, first, last — as theme references, so resolving them would put
/// four `RRGGBB` values on every group in the spec to say what the default
/// already says. An unset colour reads as "whatever the theme paints", which is
/// what the group meant.
fn sparkline_color(
  color : @xlsx.SparklineColor?,
  notes : Notes,
) -> @units.Color? {
  guard color is Some(color) else { return None }
  read_color(color.rgb, notes)
}

///|
/// A sheet's `shapes:` block.
fn shapes(sheet : @model.Sheet) -> @yaml.Node {
  let rendered = []
  for shape in sheet.shapes {
    let entries = [
      ("at", @yaml.Str(shape.at.to_a1())),
      ("kind", @yaml.Str(shape.preset)),
    ]
    if shape.text is Some(text) {
      entries.push(("text", shape_text(text)))
    }
    if size(width=shape.width, height=shape.height) is Some(node) {
      entries.push(("size", node))
    }
    if shape.fill is Some(color) {
      entries.push(("fill", @yaml.Str(color.hex())))
    }
    // The outline is a bare colour unless there is a width to carry with it —
    // and a width without a colour is not something the schema can say, which
    // is why the reader drops one rather than leaving it here to be lost.
    if shape.line_color is Some(color) {
      entries.push(
        (
          "line",
          match shape.line_width {
            Some(width) =>
              @yaml.Map([
                ("color", @yaml.Str(color.hex())),
                ("width", number(width)),
              ])
            None => @yaml.Str(color.hex())
          },
        ),
      )
    }
    if shape.alt_text is Some(alt) {
      entries.push(("alt", @yaml.Str(alt)))
    }
    positioning(shape.positioning, entries)
    rendered.push(@yaml.Map(entries))
  }
  @yaml.Seq(rendered)
}

///|
/// What a shape says: one string, or one entry per line.
fn shape_text(text : @model.ShapeText) -> @yaml.Node {
  match text {
    Plain(text) => @yaml.Str(text)
    Lines(lines) => {
      let rendered = []
      for line in lines {
        rendered.push(rich_run(line))
      }
      @yaml.Seq(rendered)
    }
  }
}

///|
/// A sheet's `sparklines:` block.
fn sparklines(sheet : @model.Sheet) -> @yaml.Node {
  let rendered = []
  for group in sheet.sparklines {
    let entries = []
    match group.cells {
      [only] => {
        entries.push(("at", @yaml.Str(only.at.to_a1())))
        entries.push(("data", @yaml.Str(sheet_range(only.data))))
      }
      cells => {
        let placed = []
        for cell in cells {
          placed.push(
            @yaml.Map([
              ("at", @yaml.Str(cell.at.to_a1())),
              ("data", @yaml.Str(sheet_range(cell.data))),
            ]),
          )
        }
        entries.push(("cells", @yaml.Seq(placed)))
      }
    }
    // A line is the schema's default kind.
    match group.kind {
      Line => ()
      Column => entries.push(("type", @yaml.Str("column")))
      WinLoss => entries.push(("type", @yaml.Str("win_loss")))
    }
    for
      flag in [
        ("markers", group.markers),
        ("high", group.high),
        ("low", group.low),
      ] {
      if flag.1 {
        entries.push((flag.0, @yaml.Bool(true)))
      }
    }
    if group.min is Some(min) {
      entries.push(("min", @yaml.Int(min.to_int64())))
    }
    if group.max is Some(max) {
      entries.push(("max", @yaml.Int(max.to_int64())))
    }
    if group.weight is Some(weight) {
      entries.push(("weight", number(weight)))
    }
    if group.color is Some(color) {
      entries.push(("color", @yaml.Str(color.hex())))
    }
    let points = []
    for
      point in [
        ("markers", group.markers_color),
        ("high", group.high_color),
        ("low", group.low_color),
      ] {
      if point.1 is Some(color) {
        points.push((point.0, @yaml.Str(color.hex())))
      }
    }
    if !points.is_empty() {
      entries.push(("colors", @yaml.Map(points)))
    }
    if group.axis {
      entries.push(("axis", @yaml.Bool(true)))
    }
    rendered.push(@yaml.Map(entries))
  }
  @yaml.Seq(rendered)
}

///|
/// A sheet's `controls:` block.
fn controls(sheet : @model.Sheet) -> @yaml.Node {
  let rendered = []
  for control in sheet.controls {
    let entries = [
      ("at", @yaml.Str(control.at.to_a1())),
      (
        "kind",
        @yaml.Str(
          match control.kind {
            Button => "button"
            CheckBox => "check_box"
            OptionButton => "option_button"
            ScrollBar => "scroll_bar"
            SpinButton => "spin_button"
            GroupBox => "group_box"
            Label => "label"
          },
        ),
      ),
    ]
    if control.text is Some(text) {
      entries.push(("text", @yaml.Str(text)))
    }
    if control.checked is Some(checked) {
      entries.push(("checked", @yaml.Bool(checked)))
    }
    if control.link is Some(link) {
      entries.push(("link", @yaml.Str(link.to_a1())))
    }
    if size(width=control.width, height=control.height) is Some(node) {
      entries.push(("size", node))
    }
    for
      bound in [
        ("min", control.min),
        ("max", control.max),
        ("step", control.step),
        ("page", control.page),
        ("value", control.value),
      ] {
      if bound.1 is Some(number) {
        entries.push((bound.0, @yaml.Int(number.to_int64())))
      }
    }
    if control.horizontal is Some(horizontal) {
      entries.push(("horizontal", @yaml.Bool(horizontal)))
    }
    rendered.push(@yaml.Map(entries))
  }
  @yaml.Seq(rendered)
}

///|
/// A sheet's `slicers:` block.
fn slicers(sheet : @model.Sheet) -> @yaml.Node {
  let rendered = []
  for slicer in sheet.slicers {
    let entries = [
      ("at", @yaml.Str(slicer.at.to_a1())),
      ("table", @yaml.Str(slicer.table)),
      ("column", @yaml.Str(slicer.column)),
    ]
    if slicer.caption is Some(caption) {
      entries.push(("caption", @yaml.Str(caption)))
    }
    if size(width=slicer.width, height=slicer.height) is Some(node) {
      entries.push(("size", node))
    }
    if slicer.header is Some(header) {
      entries.push(("header", @yaml.Bool(header)))
    }
    rendered.push(@yaml.Map(entries))
  }
  @yaml.Seq(rendered)
}

///|
/// A `size:` block, or `None` where there is nothing to say.
///
/// The schema takes both dimensions together or neither, since one alone would
/// pair silently with a backend default — and both the loader and the reader
/// hold to that, so a half-set size is a model nothing builds.
fn size(width~ : Int?, height~ : Int?) -> @yaml.Node? {
  guard width is Some(width) && height is Some(height) else { return None }
  Some(
    @yaml.Map([
      ("width", @yaml.Int(width.to_int64())),
      ("height", @yaml.Int(height.to_int64())),
    ]),
  )
}

///|
/// `move` is Excel's default and the schema's, so it is left unsaid.
fn positioning(
  positioning : @model.ImagePositioning,
  entries : Array[(String, @yaml.Node)],
) -> Unit {
  match positioning {
    Move => ()
    MoveAndSize => entries.push(("positioning", @yaml.Str("move_and_size")))
    Fixed => entries.push(("positioning", @yaml.Str("fixed")))
  }
}

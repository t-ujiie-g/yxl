// Cycle detection, shared by the three things in a spec that can refer to one
// another: an include naming a file that (transitively) includes it, a style
// extending one that extends it, and a parameter whose default uses one that
// uses it. Each resolves depth-first carrying the chain of names it is inside,
// and reports the whole chain so the offending edge is findable.

///|
/// The diagnostic for a chain that closed on itself. `kind` names what is
/// looping ("include", "style inheritance", "parameter"), and `chain` is the
/// names currently being resolved, outermost first.
fn cycle_error(
  chain : Array[String],
  repeated : String,
  kind~ : String,
  file~ : String,
) -> @diag.SchemaError {
  schema_error(file~, "\{kind} cycle: \{render_cycle(chain, repeated)}")
}

///|
/// The chain as `a.yaml -> b.yaml -> a.yaml`, ending on the name that closes
/// the loop.
fn render_cycle(chain : Array[String], repeated : String) -> String {
  let names = [..chain, repeated]
  let joined = StringBuilder::new()
  for index, name in names {
    if index > 0 {
      joined.write_string(" -> ")
    }
    joined.write_string(name)
  }
  joined.to_string()
}

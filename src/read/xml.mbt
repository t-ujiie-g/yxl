///|
/// One element: its resolved namespace, its local name, its attributes by local
/// name, its element children, and the text directly inside it.
priv struct XmlElement {
  ns : String
  name : String
  attributes : Map[String, String]
  children : Array[XmlElement]
  text : String
}

///|
/// The document's root element, or `None` if the text is not XML this reader
/// can make sense of.
fn parse_xml(source : String) -> XmlElement? {
  let scanner : XmlScanner = {
    chars: source.iter().collect(),
    at: 0,
    scopes: [],
  }
  scanner.document()
}

///|
/// The first child in this namespace with this local name.
fn XmlElement::child(
  self : XmlElement,
  ns : String,
  name : String,
) -> XmlElement? {
  for candidate in self.children {
    if candidate.ns == ns && candidate.name == name {
      return Some(candidate)
    }
  }
  None
}

///|
/// Every direct child in this namespace with this local name, in document
/// order.
fn XmlElement::children_named(
  self : XmlElement,
  ns : String,
  name : String,
) -> Array[XmlElement] {
  self.children.filter(child => child.ns == ns && child.name == name)
}

///|
/// Every element anywhere beneath this one with this namespace and local name,
/// in document order. The `<a:t>` runs of a title are reached this way: how
/// deeply DrawingML wraps them in paragraphs and runs is not something to
/// hard-code.
fn XmlElement::descendants(
  self : XmlElement,
  ns : String,
  name : String,
) -> Array[XmlElement] {
  let found = []
  fn walk(element : XmlElement) -> Unit {
    for child in element.children {
      if child.ns == ns && child.name == name {
        found.push(child)
      }
      walk(child)
    }
  }

  walk(self)
  found
}

///|
/// An attribute's value, by local name.
fn XmlElement::attribute(self : XmlElement, name : String) -> String? {
  self.attributes.get(name)
}

///|
/// The reader's position, and the namespace prefixes in scope where it stands.
priv struct XmlScanner {
  chars : Array[Char]
  mut at : Int
  scopes : Array[Map[String, String]]
}

///|
/// The prolog, then the root element.
fn XmlScanner::document(self : XmlScanner) -> XmlElement? {
  self.skip_prolog()
  self.element()
}

///|
/// Whitespace, the XML declaration, comments, and a doctype — everything that
/// may precede the root element.
fn XmlScanner::skip_prolog(self : XmlScanner) -> Unit {
  self.skip_whitespace()
  while self.looking_at("<?") || self.looking_at("<!") {
    if self.looking_at("<!--") {
      guard self.skip_past("-->") else { return }
    } else {
      // A processing instruction or a doctype with no internal subset. A
      // doctype that carries one would end at the wrong `>`; a chart part has
      // no doctype at all, and one that did is not a chart part.
      guard self.skip_past(">") else { return }
    }
    self.skip_whitespace()
  }
}

///|
/// One element and everything inside it, with the scanner sitting on its `<`.
fn XmlScanner::element(self : XmlScanner) -> XmlElement? {
  guard self.looking_at("<") else { return None }
  self.at += 1
  guard self.read_name() is Some(raw_name) && !raw_name.is_empty() else {
    return None
  }
  let declarations = Map([])
  let raw_attributes = []
  let mut self_closing = false
  let mut closed = false
  while !closed {
    self.skip_whitespace()
    if self.looking_at("/>") {
      self.at += 2
      self_closing = true
      closed = true
    } else if self.looking_at(">") {
      self.at += 1
      closed = true
    } else {
      guard self.read_name() is Some(attribute) && !attribute.is_empty() else {
        return None
      }
      self.skip_whitespace()
      guard self.looking_at("=") else { return None }
      self.at += 1
      self.skip_whitespace()
      guard self.read_quoted() is Some(value) else { return None }
      if attribute == "xmlns" {
        declarations[""] = value
      } else if attribute.has_prefix("xmlns:") {
        declarations[attribute[6:].to_owned()] = value
      } else {
        raw_attributes.push((attribute, value))
      }
    }
  }
  self.scopes.push(declarations)
  let (ns, name) = self.resolve(raw_name, is_attribute=false)
  let attributes = Map([])
  for entry in raw_attributes {
    let (_, local_name) = self.resolve(entry.0, is_attribute=true)
    attributes[local_name] = entry.1
  }
  let children = []
  let text = StringBuilder::new()
  if !self_closing {
    guard self.content(children, text) else {
      self.scopes.pop() |> ignore
      return None
    }
  }
  self.scopes.pop() |> ignore
  Some({ ns, name, attributes, children, text: text.to_string(), })
}

///|
/// Everything between an element's `>` and its closing tag. `false` means the
/// document ran out or held something this reader will not read.
fn XmlScanner::content(
  self : XmlScanner,
  children : Array[XmlElement],
  text : StringBuilder,
) -> Bool {
  while self.at < self.chars.length() {
    if self.looking_at("</") {
      self.at += 2
      guard self.read_name() is Some(_) else { return false }
      self.skip_whitespace()
      guard self.looking_at(">") else { return false }
      self.at += 1
      return true
    } else if self.looking_at("<!--") {
      guard self.skip_past("-->") else { return false }
    } else if self.looking_at("<![CDATA[") {
      self.at += 9
      let start = self.at
      guard self.skip_past("]]>") else { return false }
      for index in start..<(self.at - 3) {
        text.write_char(self.chars[index])
      }
    } else if self.looking_at("<?") {
      guard self.skip_past("?>") else { return false }
    } else if self.looking_at("<") {
      guard self.element() is Some(child) else { return false }
      children.push(child)
    } else {
      let start = self.at
      while self.at < self.chars.length() && self.chars[self.at] != '<' {
        self.at += 1
      }
      text.write_string(self.decode(start, self.at))
    }
  }
  // Ran off the end with the element still open.
  false
}

///|
/// A prefixed or bare name split into the namespace it resolves to and its
/// local part. An unprefixed *attribute* is in no namespace, which is not the
/// same as being in the default one (XML 1.0 §6.2) — hence the flag.
fn XmlScanner::resolve(
  self : XmlScanner,
  raw : String,
  is_attribute~ : Bool,
) -> (String, String) {
  let colon = raw.find(":")
  match colon {
    Some(index) => {
      let prefix = raw[0:index].to_owned()
      let local_name = raw[index + 1:].to_owned()
      (self.lookup(prefix), local_name)
    }
    None => if is_attribute { ("", raw) } else { (self.lookup(""), raw) }
  }
}

///|
/// What a prefix is bound to where the scanner stands: the innermost binding
/// wins, and an unbound prefix resolves to no namespace, which matches nothing.
fn XmlScanner::lookup(self : XmlScanner, prefix : String) -> String {
  for index in 0..<self.scopes.length() {
    let scope = self.scopes[self.scopes.length() - 1 - index]
    if scope.get(prefix) is Some(uri) {
      return uri
    }
  }
  ""
}

///|
/// A name, from the scanner's position: letters, digits, and the punctuation
/// XML allows in one. Deliberately looser than `NameStartChar`, since a name
/// this accepts and the spec does not is one no chart part contains.
fn XmlScanner::read_name(self : XmlScanner) -> String? {
  let start = self.at
  while self.at < self.chars.length() {
    let ch = self.chars[self.at]
    guard ch is ('a'..='z' | 'A'..='Z' | '0'..='9' | ':' | '_' | '-' | '.') else {
      break
    }
    self.at += 1
  }
  guard self.at > start else { return None }
  let name = StringBuilder::new()
  for index in start..<self.at {
    name.write_char(self.chars[index])
  }
  Some(name.to_string())
}

///|
/// A quoted attribute value, with its entities decoded.
fn XmlScanner::read_quoted(self : XmlScanner) -> String? {
  guard self.at < self.chars.length() else { return None }
  let quote = self.chars[self.at]
  guard quote is ('"' | '\'') else { return None }
  self.at += 1
  let start = self.at
  while self.at < self.chars.length() && self.chars[self.at] != quote {
    self.at += 1
  }
  guard self.at < self.chars.length() else { return None }
  let value = self.decode(start, self.at)
  self.at += 1
  Some(value)
}

///|
/// The characters in `[start, end)` with the five predefined entities and
/// numeric character references resolved. An entity this does not know is left
/// as written: a chart part holds none, and mangling one would be worse than
/// carrying it through.
fn XmlScanner::decode(self : XmlScanner, start : Int, end : Int) -> String {
  let out = StringBuilder::new()
  let mut index = start
  while index < end {
    guard self.chars[index] == '&' else {
      out.write_char(self.chars[index])
      index += 1
      continue
    }
    let mut close = index + 1
    while close < end && self.chars[close] != ';' {
      close += 1
    }
    guard close < end else {
      out.write_char('&')
      index += 1
      continue
    }
    let entity = StringBuilder::new()
    for inner in (index + 1)..<close {
      entity.write_char(self.chars[inner])
    }
    match entity.to_string() {
      "lt" => out.write_char('<')
      "gt" => out.write_char('>')
      "amp" => out.write_char('&')
      "quot" => out.write_char('"')
      "apos" => out.write_char('\'')
      other =>
        match character_reference(other) {
          Some(ch) => out.write_char(ch)
          None => {
            out.write_char('&')
            out.write_string(other)
            out.write_char(';')
          }
        }
    }
    index = close + 1
  }
  out.to_string()
}

///|
/// `#65` or `#x41` as the character it stands for.
fn character_reference(body : String) -> Char? {
  guard body.has_prefix("#") else { return None }
  let (digits, base) = if body.has_prefix("#x") || body.has_prefix("#X") {
    (body[2:], 16)
  } else {
    (body[1:], 10)
  }
  guard !digits.is_empty() else { return None }
  let code = @string.parse_int(digits.to_owned(), base~) catch {
    _ => return None
  }
  guard code > 0 && code <= 0x10FFFF else { return None }
  Some(Int::unsafe_to_char(code))
}

///|
/// Whether the text at the scanner starts with `literal`.
fn XmlScanner::looking_at(self : XmlScanner, literal : String) -> Bool {
  let mut offset = 0
  for ch in literal {
    guard self.at + offset < self.chars.length() &&
      self.chars[self.at + offset] == ch else {
      return false
    }
    offset += 1
  }
  true
}

///|
/// Move past the next occurrence of `literal`, landing after it. `false` if it
/// is not there at all.
fn XmlScanner::skip_past(self : XmlScanner, literal : String) -> Bool {
  while self.at < self.chars.length() {
    if self.looking_at(literal) {
      self.at += literal.char_length()
      return true
    }
    self.at += 1
  }
  false
}

///|
/// Move past any whitespace.
fn XmlScanner::skip_whitespace(self : XmlScanner) -> Unit {
  while self.at < self.chars.length() &&
        self.chars[self.at] is (' ' | '\t' | '\n' | '\r') {
    self.at += 1
  }
}

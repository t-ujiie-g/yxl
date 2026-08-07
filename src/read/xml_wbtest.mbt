// Whitebox tests for the small XML reader. It is package-private and has one
// caller, but the two properties the chart reader leans on — that nesting is
// tracked and that prefixes are resolved to namespaces — are exactly what a
// looser scan gets wrong, so they are pinned here rather than only through a
// chart.

///|
/// The one namespace these tests bind, standing in for the chart part's.
const NS : String = "urn:test"

///|
test "an element yields its namespace, name, attributes, and text" {
  guard parse_xml(
      (
        #|<t:root xmlns:t="urn:test" a="1" b="two">hello</t:root>
      ),
    )
    is Some(root) else {
    fail("did not parse")
  }
  assert_eq(root.ns, NS)
  assert_eq(root.name, "root")
  assert_eq(root.attribute("a"), Some("1"))
  assert_eq(root.attribute("b"), Some("two"))
  assert_eq(root.attribute("c"), None)
  assert_eq(root.text, "hello")
}

///|
test "a prefix is resolved to its namespace, whatever it is spelled" {
  // The same document under two prefixes reads identically. A scan that matched
  // on the literal `c:` would read one and miss the other, and Excel is free to
  // write either.
  for
    source in [
      (
        #|<c:chart xmlns:c="urn:test"><c:ser/></c:chart>
      ),
      (
        #|<x:chart xmlns:x="urn:test"><x:ser/></x:chart>
      ),
      (
        #|<chart xmlns="urn:test"><ser/></chart>
      ),
    ] {
    guard parse_xml(source) is Some(root) else { fail("did not parse") }
    assert_eq(root.ns, NS)
    assert_eq(root.name, "chart")
    assert_true(root.child(NS, "ser") is Some(_))
  }
}

///|
test "a prefix rebound inside the document only applies to that subtree" {
  guard parse_xml(
      (
        #|<r xmlns:p="urn:test"><p:a/><s xmlns:p="urn:other"><p:a/></s><p:a/></r>
      ),
    )
    is Some(root) else {
    fail("did not parse")
  }
  // Two `p:a` in the outer namespace, and the middle one somewhere else.
  assert_eq(root.children_named(NS, "a").length(), 2)
  guard root.child("", "s") is Some(inner) else { fail("missing s") }
  assert_eq(inner.children_named(NS, "a").length(), 0)
  assert_eq(inner.children_named("urn:other", "a").length(), 1)
}

///|
test "a child is found only one level down, a descendant at any depth" {
  guard parse_xml(
      (
        #|<r xmlns="urn:test"><ser><tx>outer</tx><dLbls><tx>inner</tx></dLbls></ser></r>
      ),
    )
    is Some(root) else {
    fail("did not parse")
  }
  guard root.child(NS, "ser") is Some(series) else { fail("missing ser") }
  // This is the distinction the chart reader depends on: a series' own name and
  // the one on its data labels are both `tx`, and only nesting tells them apart.
  assert_eq(series.children_named(NS, "tx").length(), 1)
  assert_eq(series.child(NS, "tx").map(node => node.text), Some("outer"))
  assert_eq(series.descendants(NS, "tx").map(node => node.text), [
    "outer", "inner",
  ])
}

///|
test "an unprefixed attribute is in no namespace, not the default one" {
  // XML 1.0 §6.2. It matters only in that attributes are keyed by local name
  // here; the test pins the rule so a later change has to mean it.
  guard parse_xml(
      (
        #|<r xmlns="urn:test" val="7"/>
      ),
    )
    is Some(root) else {
    fail("did not parse")
  }
  assert_eq(root.ns, NS)
  assert_eq(root.attribute("val"), Some("7"))
}

///|
test "entities and character references are decoded, in text and attributes" {
  guard parse_xml(
      (
        #|<r a="&lt;&amp;&gt;&quot;&apos;&#65;&#x42;">1 &lt; 2 &amp;&#x263A;</r>
      ),
    )
    is Some(root) else {
    fail("did not parse")
  }
  assert_eq(root.attribute("a"), Some("<&>\"'AB"))
  assert_eq(root.text, "1 < 2 &☺")
}

///|
test "an entity this reader does not know is carried through as written" {
  guard parse_xml(
      (
        #|<r>&nbsp;x</r>
      ),
    )
    is Some(root) else {
    fail("did not parse")
  }
  assert_eq(root.text, "&nbsp;x")
}

///|
test "comments, processing instructions, and CDATA" {
  guard parse_xml(
      (
        #|<?xml version="1.0"?><!-- above --><r><!-- inside --><?pi data?><![CDATA[a<b]]>c</r>
      ),
    )
    is Some(root) else {
    fail("did not parse")
  }
  assert_eq(root.name, "r")
  // CDATA is text and is not re-decoded; the comment and the PI leave nothing.
  assert_eq(root.text, "a<bc")
}

///|
test "self-closing and empty elements" {
  guard parse_xml(
      (
        #|<r><a val="1"/><b></b></r>
      ),
    )
    is Some(root) else {
    fail("did not parse")
  }
  assert_eq(root.children.length(), 2)
  assert_eq(root.child("", "a").bind(node => node.attribute("val")), Some("1"))
  assert_eq(root.child("", "b").map(node => node.text), Some(""))
}

///|
test "single-quoted attribute values, and whitespace around the equals sign" {
  guard parse_xml(
      (
        #|<r a = 'one' b='two'/>
      ),
    )
    is Some(root) else {
    fail("did not parse")
  }
  assert_eq(root.attribute("a"), Some("one"))
  assert_eq(root.attribute("b"), Some("two"))
}

///|
test "text that is not XML this reader can follow is None, never a guess" {
  // Every one of these would be a wrong answer if the reader recovered
  // *something* from it; the caller reports the chart instead.
  for
    source in [
      "", "not xml at all", "<r>", "<r><a></r>", "<r a></r>", "<r a=></r>", "<r a=\"unterminated></r>",
      "<!-- only a comment -->",
    ] {
    assert_eq(parse_xml(source).map(node => node.name), None)
  }
}

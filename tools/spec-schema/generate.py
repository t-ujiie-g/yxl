#!/usr/bin/env python3
"""Build `docs/yxl.schema.json` out of `docs/spec.md`.

The reference is the source of the *vocabulary*: every key a spec may hold,
every enumeration it may name, and the sentence describing each — lifted from
the tables, example blocks, and lists of `docs/spec.md`. This file supplies the
*shapes* those keys take, which prose cannot state precisely. The two are
cross-checked on every run: a key documented but unshaped, or shaped but
undocumented, fails the build rather than shipping a schema that disagrees with
the page it was made from.

  generate.py                    write docs/yxl.schema.json
  generate.py --check            fail if the committed file is out of date
  generate.py --validate FILE…   validate spec files against the schema
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "docs" / "spec.md"
SCHEMA = ROOT / "docs" / "yxl.schema.json"

SCHEMA_URL = (
    "https://raw.githubusercontent.com/t-ujiie-g/yxl/main/docs/yxl.schema.json"
)


class Drift(Exception):
    """The reference and this generator disagree about the spec format."""


# --------------------------------------------------------------------------
# Reading docs/spec.md
# --------------------------------------------------------------------------

HEADING = re.compile(r"^#{2,3}\s+(.*?)\s*$")
CELL_SPLIT = re.compile(r"(?<!\\)\|")
BACKTICKED = re.compile(r"`([^`]+)`")
NAME = re.compile(r"^[A-Za-z0-9_]+$")


class Reference:
    """`docs/spec.md`, addressed by heading."""

    def __init__(self, text: str) -> None:
        self.sections: dict[str, str] = {}
        heading, body = None, []
        for line in text.splitlines():
            match = HEADING.match(line)
            if match:
                if heading is not None:
                    self.sections[heading] = "\n".join(body)
                heading, body = match.group(1), []
            else:
                body.append(line)
        if heading is not None:
            self.sections[heading] = "\n".join(body)

    def section(self, heading: str) -> str:
        if heading not in self.sections:
            raise Drift(f"docs/spec.md has no section '{heading}'")
        return self.sections[heading]

    # -- tables ------------------------------------------------------------

    def tables(self, heading: str) -> list[list[list[str]]]:
        found, rows = [], []
        for line in self.section(heading).splitlines():
            if line.lstrip().startswith("|"):
                cells = [
                    cell.strip().replace("\\|", "|")
                    for cell in CELL_SPLIT.split(line.strip())[1:-1]
                ]
                if not all(set(cell) <= set("-: ") for cell in cells):
                    rows.append(cells)
            elif rows:
                found.append(rows)
                rows = []
        if rows:
            found.append(rows)
        return found

    def _key_table(self, heading: str, table: int) -> list[list[str]]:
        tables = self.tables(heading)
        if table >= len(tables):
            raise Drift(f"'{heading}' has no key table #{table + 1}")
        rows = tables[table]
        if rows[0][0] != "Key":
            raise Drift(
                f"table #{table + 1} of '{heading}' is not a key table"
                f" (its first column is '{rows[0][0]}')"
            )
        return rows

    def keys(
        self, heading: str, table: int = 0, belongs: bool = False
    ) -> dict[str, str]:
        """A key table's `key -> description`, in the order documented.

        One row may document several keys (`` `columns` / `rows` ``); each takes
        the row's description. The description is the row's last cell, which is
        `Notes` in every table shaped this way. `belongs` picks up the middle
        column of the one table that has something else to say there — which
        kinds of form control admit the key (§20).
        """
        rows = self._key_table(heading, table)
        documented: dict[str, str] = {}
        for row in rows[1:]:
            description = row[-1]
            if belongs and row[1] != "all":
                description += f" Only on: {row[1]}."
            for key in BACKTICKED.findall(row[0]):
                documented[key] = description
        return documented

    def types(self, heading: str, table: int = 0) -> dict[str, str]:
        """A key table's `Type` column, which states nested keys as `{ a, b }`."""
        rows = self._key_table(heading, table)
        if rows[0][1] != "Type":
            raise Drift(f"the key table of '{heading}' has no 'Type' column")
        return {
            key: row[1] for row in rows[1:] for key in BACKTICKED.findall(row[0])
        }

    def column(self, heading: str, table: int, column: int) -> list[str]:
        """The keys a matrix table marks with a tick in one column."""
        rows = self.tables(heading)[table]
        marked = []
        for row in rows[1:]:
            if row[column] not in ("—", "-", ""):
                marked += BACKTICKED.findall(row[0])
        return marked

    # -- example blocks ----------------------------------------------------

    def example(self, heading: str, *path: str) -> list[str]:
        """The keys written under `path` in a section's first YAML example.

        The sections that document a construct by showing it — `print:`,
        `properties:`, `calc:` — are as much of an inventory as a table is,
        so they are read as one.
        """
        wanted = list(path)
        depth = len(wanted)
        stack: list[str] = []
        keys: list[str] = []
        for line in self._first_yaml_block(heading).splitlines():
            body = line.split("#", 1)[0].rstrip()
            match = re.match(r"^(\s*)(?:-\s+)?([A-Za-z_][A-Za-z0-9_]*):(.*)$", body)
            if not match:
                continue
            indent, key, value = len(match.group(1)), match.group(2), match.group(3)
            del stack[indent // 2 :]
            stack.append(key)
            # The path is matched as a suffix, so a construct is addressed by
            # its own name however deep the example nests it.
            if stack[:-1][-depth:] == wanted:
                keys.append(key)
            elif stack[-depth:] == wanted:
                keys += braced(value)
        return keys

    def comment(self, heading: str, key: str) -> str:
        """The `# …` an example writes beside a key, which often spells it out."""
        for line in self._first_yaml_block(heading).splitlines():
            if re.match(rf"^\s*(?:-\s+)?{key}:", line) and "#" in line:
                return line.split("#", 1)[1]
        raise Drift(f"'{heading}' writes no comment beside '{key}'")

    def _first_yaml_block(self, heading: str) -> str:
        block = re.search(
            r"^```ya?ml\n(.*?)^```", self.section(heading), re.S | re.M
        )
        if not block:
            raise Drift(f"'{heading}' has no YAML example")
        return block.group(1)

    def alternatives(self, heading: str, key: str) -> list[str]:
        """The `key: a | b | c` an example writes to show a key's spellings."""
        pattern = rf"^\s*(?:-\s+)?{key}:\s*(.*)$"
        for line in self._first_yaml_block(heading).splitlines():
            match = re.match(pattern, line)
            if match:
                written = match.group(1)
                if "#" in written and "|" not in written.split("#", 1)[0]:
                    written = written.split("#", 1)[1]
                if "|" in written:
                    return [word.strip() for word in written.split("|")]
        raise Drift(f"'{heading}' does not spell out the values of '{key}'")

    # -- prose lists -------------------------------------------------------

    def listed(self, heading: str, after: str = "", stop: str = "") -> list[str]:
        """The names a paragraph gives in backticks, in the order written."""
        text = self.section(heading)
        if after:
            if after not in text:
                raise Drift(f"'{heading}' no longer says '{after}'")
            text = text.split(after, 1)[1]
        text = text.lstrip("\n").split("\n\n", 1)[0]
        return names(text, stop=stop)


def names(text: str, stop: str = "") -> list[str]:
    """The identifier-shaped backticked names in a run of prose."""
    if stop and stop in text:
        text = text.split(stop, 1)[0]
    return [word for word in BACKTICKED.findall(text) if NAME.match(word)]


def keyish(text: str) -> list[str]:
    """`names`, but reading `` `bar_only: true` `` as the key it names."""
    return [
        word
        for word in (token.split(":")[0].strip() for token in BACKTICKED.findall(text))
        if NAME.match(word)
    ]


def braced(text: str) -> list[str]:
    """The keys of the first `{ a, b, c }` a description writes out.

    The reference states a nested mapping's keys this way throughout — a font
    is `` `{ bold, italic, … }` ``, a size `` `{ width, height }` `` — so the
    inventory of those mappings is documented too, not merely their existence.
    """
    inside = re.search(r"\{([^{}]*)\}", text)
    if not inside:
        return []
    fields = []
    for written in inside.group(1).split(","):
        # `{ from: range }` names one key and the kind of value it takes.
        field = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)", written)
        if field:
            fields.append(field.group(1))
    return fields


def numbered_ranges(text: str) -> list[str]:
    """`` `TableStyleLight1`–`TableStyleLight21` `` expanded to every name."""
    styles: list[str] = []
    for prefix, first, last in re.findall(
        r"`([A-Za-z]+)(\d+)`[–-]`(?:[A-Za-z]+)?(\d+)`", text
    ):
        styles += numbered(prefix, int(last))[int(first) - 1 :]
    if not styles:
        raise Drift(f"no numbered style range in: {collapse(text)}")
    return styles


# --------------------------------------------------------------------------
# JSON Schema pieces
# --------------------------------------------------------------------------


def ref(name: str) -> dict:
    return {"$ref": f"#/definitions/{name}"}


def described(schema: dict, description: str) -> dict:
    """A subschema carrying the reference's own words.

    A `$ref` is wrapped rather than annotated: draft-07 ignores everything
    beside a `$ref`, which would drop the description an editor shows on hover.
    """
    text = collapse(description)
    if not text:
        return schema
    annotation = {"description": text, "markdownDescription": text}
    if "$ref" in schema:
        return {"allOf": [schema], **annotation}
    return {**schema, **annotation}


def collapse(markdown: str) -> str:
    return re.sub(r"\s+", " ", markdown).strip()


def obj(
    properties: dict[str, dict],
    *,
    documented: dict[str, str] | list[str] | None = None,
    required: tuple[str, ...] = (),
    description: str = "",
    where: str = "",
    includable: bool = True,
) -> dict:
    """One mapping of the spec format, checked against its documentation.

    `documented` is what `docs/spec.md` says the mapping holds; `properties` is
    what this generator knows how to shape. The two must name the same keys —
    that agreement is the whole point of generating the schema from the page.

    Every mapping may be written as `{ $include: path }` instead (§8). Where the
    mapping has no required key that is one more property it may carry, which
    keeps an unknown key reported as an unknown key; where it has one, the
    include cannot satisfy it and the two forms have to be offered as
    alternatives.
    """
    if documented is not None:
        if not isinstance(documented, dict):
            # A section that documents a mapping by showing it names its keys
            # and no more; the description then has nowhere to come from.
            documented = dict.fromkeys(documented, "")
        missing = [key for key in documented if key not in properties]
        extra = [key for key in properties if key not in documented]
        if missing or extra:
            raise Drift(
                f"{where or 'a mapping'} disagrees with docs/spec.md:"
                + (f" documented but unshaped: {missing}." if missing else "")
                + (f" shaped but undocumented: {extra}." if extra else "")
            )
        properties = {
            key: described(properties[key], text)
            for key, text in documented.items()
        }
    schema: dict = {"type": "object", "additionalProperties": False}
    if description:
        schema["description"] = collapse(description)
    schema["properties"] = properties
    if not includable:
        if required:
            schema["required"] = list(required)
        return schema
    properties["$include"] = INCLUDE_PATH
    if required:
        # Not a plain `required`: an include *replaces* the mapping, so it
        # cannot carry the keys the mapping demands. Stating the choice this way
        # rather than as two whole alternative schemas is what keeps a misspelt
        # key reported as a misspelt key.
        schema["anyOf"] = [{"required": list(required)}, {"required": ["$include"]}]
    return schema


INCLUDE_PATH = {
    "type": "string",
    "description": "Another document, pasted in place of this node (§8).",
}


def node(schema: dict) -> dict:
    """Any node may be written as `{ $include: path }` instead (§8)."""
    return {"anyOf": [schema, ref("include")]}


def seq(items: dict, description: str = "") -> dict:
    # The items need no include alternative of their own: a mapping carries
    # `$include` as one of its own keys, and that is what a split file replaces.
    schema = {"type": "array", "items": items}
    if description:
        schema["description"] = collapse(description)
    return node(schema)


def enum(values: list[str]) -> dict:
    return {"anyOf": [{"type": "string", "enum": values}, ref("parameterized")]}


def numbered(prefix: str, upto: int) -> list[str]:
    return [f"{prefix}{index}" for index in range(1, upto + 1)]


# --------------------------------------------------------------------------
# The spec format, shaped
# --------------------------------------------------------------------------

DEFINITIONS: dict[str, dict] = {
    "include": obj(
        {"$include": INCLUDE_PATH},
        required=("$include",),
        includable=False,
        description="A node replaced entirely by another document (§8).",
    ),
    "parameterized": {
        "type": "string",
        "pattern": r"\$\{",
        "description": "A string holding a ${parameter} (§7).",
    },
    "text": {"type": "string"},
    "number": {"anyOf": [{"type": "number"}, ref("parameterized")]},
    "integer": {"anyOf": [{"type": "integer"}, ref("parameterized")]},
    "boolean": {"anyOf": [{"type": "boolean"}, ref("parameterized")]},
    "scalar": {"type": ["string", "number", "boolean", "null"]},
    "color": {
        "anyOf": [
            {"type": "string", "pattern": "^[0-9A-Fa-f]{6}$"},
            ref("parameterized"),
        ],
        "description": "A hex colour, RRGGBB.",
    },
    "cell": {
        "anyOf": [
            {"type": "string", "pattern": "^[A-Za-z]{1,3}[0-9]+$"},
            ref("parameterized"),
        ],
        "description": "An A1 cell reference.",
    },
    "range": {
        "anyOf": [
            {
                "type": "string",
                "pattern": "^[A-Za-z]{1,3}[0-9]+:[A-Za-z]{1,3}[0-9]+$",
            },
            ref("parameterized"),
        ],
        "description": "A TopLeft:BottomRight range.",
    },
    "qualified_range": {
        "anyOf": [
            {
                "type": "string",
                "pattern": (
                    "^(('[^']*'|[^'!]+)!)?"
                    "[A-Za-z]{1,3}[0-9]+:[A-Za-z]{1,3}[0-9]+$"
                ),
            },
            ref("parameterized"),
        ],
        "description": "A range, optionally naming a declared sheet.",
    },
    "qualified_cell": {
        "anyOf": [
            {
                "type": "string",
                "pattern": "^('[^']*'|[^'!]+)![A-Za-z]{1,3}[0-9]+$",
            },
            ref("parameterized"),
        ],
        "description": "A sheet-qualified cell, Sales!E37.",
    },
    "path": {"type": "string", "description": "A path, / or \\ separated."},
    "value_ref": obj(
        {"$ref": {"type": "string"}},
        required=("$ref",),
        includable=False,
        description="A name declared under defs (§6).",
    ),
}


def build(doc: Reference) -> dict:
    define = DEFINITIONS.copy()

    # -- §6 styles ---------------------------------------------------------

    attributes = doc.keys("Style attributes")
    align = attributes["align"]
    border = attributes["border"]
    define["font"] = obj(
        {
            "bold": ref("boolean"),
            "italic": ref("boolean"),
            "underline": ref("boolean"),
            "strike": ref("boolean"),
            "size": ref("number"),
            "name": ref("text"),
            "color": ref("color"),
        },
        documented=braced(attributes["font"]),
        where="a font",
    )
    horizontal, vertical = align.split("Horizontal:")[1].split("Vertical:")
    define["align"] = obj(
        {
            "horizontal": enum(names(horizontal)),
            "vertical": enum(names(vertical)),
            "wrap": ref("boolean"),
        },
        documented=braced(align),
        where="an alignment",
    )
    edges, line_styles = border.split("Styles:")
    define["border_edge"] = {
        "anyOf": [
            enum(names(line_styles)),
            obj(
                {"style": enum(names(line_styles)), "color": ref("color")},
                documented=["style", "color"],
                where="a border edge",
            ),
        ]
    }
    define["border"] = {
        "anyOf": [
            enum(names(line_styles)),
            obj(
                {edge: ref("border_edge") for edge in names(edges)},
                documented=names(edges),
                where="a border",
            ),
        ]
    }
    define["protection"] = obj(
        {"locked": ref("boolean"), "hidden": ref("boolean")},
        documented=braced(attributes["protection"]),
        where="a style's protection",
    )
    define["style_body"] = obj(
        {
            "extends": ref("text"),
            "font": ref("font"),
            "fill": {"anyOf": [ref("color"), obj({"color": ref("color")})]},
            "border": ref("border"),
            "protection": ref("protection"),
            "format": ref("text"),
            "align": ref("align"),
        },
        documented=attributes,
        where="a style",
    )
    define["style"] = {
        "anyOf": [{"type": "string"}, ref("style_body")],
        "description": "A declared style's name, or an inline style (§6).",
    }

    # -- §3 cells ----------------------------------------------------------

    expanded = doc.keys("The expanded form")
    define["rich_run"] = {
        "anyOf": [
            {"type": "string"},
            obj(
                {"text": ref("text"), "font": ref("font")},
                documented=braced(expanded["rich"]),
                where="a rich-text run",
            ),
        ]
    }
    cell_facets = {
        "value": {"anyOf": [ref("scalar"), ref("value_ref")]},
        "formula": {"anyOf": [ref("text"), ref("value_ref")]},
        "rich": seq(ref("rich_run")),
        "type": enum(names(expanded["type"], stop="—")),
        "format": ref("text"),
        "style": ref("style"),
    }
    define["cell_body"] = obj(
        dict(cell_facets), documented=expanded, where="a cell"
    )
    define["cell_value"] = {
        "anyOf": [ref("scalar"), ref("value_ref"), ref("cell_body")],
        "description": "A scalar, a { $ref: name }, or the expanded form (§3).",
    }
    # An A1-keyed mapping cannot carry `$include` as a key of its own — the
    # addresses are the key space — so the whole node takes the alternative.
    define["cells"] = node(
        {
            "type": "object",
            "description": "Cells by A1 address (§3).",
            "propertyNames": {"$ref": "#/definitions/cell"},
            "additionalProperties": ref("cell_value"),
        }
    )
    define["formula_range"] = obj(
        {"at": ref("range"), "formula": ref("text")},
        documented=doc.keys("Filled formula ranges"),
        required=("at", "formula"),
        where="a formulas entry",
    )

    # -- §4 bands ----------------------------------------------------------

    band = {
        "at": {
            "anyOf": [
                {
                    "type": "string",
                    "pattern": "^([A-Za-z]{1,3}(-[A-Za-z]{1,3})?|[0-9]+(-[0-9]+)?)$",
                },
                {"type": "integer"},
                ref("parameterized"),
            ]
        },
        "style": ref("style"),
        "format": ref("text"),
        "hidden": ref("boolean"),
        "group": ref("integer"),
        "width": ref("number"),
        "height": ref("number"),
    }
    bands = "4. Column and row bands"
    define["column_band"] = obj(
        {key: band[key] for key in doc.column(bands, 0, 1)},
        documented=doc.column(bands, 0, 1),
        required=("at",),
        description="A span of columns and what it looks like (§4).",
        where="a columns band",
    )
    define["row_band"] = obj(
        {key: band[key] for key in doc.column(bands, 0, 2)},
        documented=doc.column(bands, 0, 2),
        required=("at",),
        description="A span of rows and what it looks like (§4).",
        where="a rows band",
    )

    # -- §5 print ----------------------------------------------------------

    printing = "5. Print setup"
    define["margins"] = obj(
        {side: ref("number") for side in doc.example(printing, "print", "margins")},
        documented=doc.example(printing, "print", "margins"),
        description="Page margins, in inches (§5).",
        where="print margins",
    )
    define["fit"] = obj(
        {side: ref("integer") for side in doc.example(printing, "print", "fit")},
        documented=doc.example(printing, "print", "fit"),
        description="Pages across and down; 0 leaves that axis unconstrained.",
        where="a print fit",
    )
    define["print"] = obj(
        {
            "area": ref("range"),
            "orientation": enum(doc.alternatives(printing, "orientation")),
            "margins": ref("margins"),
            "scale": ref("integer"),
            "fit": ref("fit"),
            "header": ref("text"),
            "footer": ref("text"),
            "breaks": seq(ref("cell")),
        },
        documented=doc.example(printing, "print"),
        description="What Excel prints, and how (§5).",
        where="print setup",
    )

    # -- §9 data -----------------------------------------------------------

    define["data"] = obj(
        {
            "at": ref("cell"),
            "values": seq(seq(ref("scalar"))),
            "csv": ref("path"),
            "json": ref("path"),
            "columns": seq(ref("text")),
        },
        documented=doc.keys("9. Tabular data"),
        required=("at",),
        description="A table of rows, anchored at a cell (§9).",
        where="a data entry",
    )

    # -- §10 decorations ---------------------------------------------------

    checks = doc.keys("Validations")
    comparisons = doc.listed(
        "Validations",
        after="The comparison is exactly one of",
        stop="`error.style`",
    )
    pair = {"type": "array", "items": ref("scalar"), "minItems": 2, "maxItems": 2}
    define["comparison"] = obj(
        {
            key: pair if key.endswith("between") else ref("scalar")
            for key in comparisons
        },
        documented=comparisons,
        description="A bound, or a pair of them (§10).",
        where="a comparison",
    )
    define["validation"] = obj(
        {
            "at": ref("range"),
            "list": {
                "anyOf": [
                    seq(ref("scalar")),
                    obj(
                        {"from": ref("qualified_range")},
                        documented=braced(checks["list"]),
                        where="a list source",
                    ),
                ]
            },
            "whole": ref("comparison"),
            "decimal": ref("comparison"),
            "text_length": ref("comparison"),
            "date": ref("comparison"),
            "allow_blank": ref("boolean"),
            "prompt": obj(
                {"title": ref("text"), "body": ref("text")},
                documented=braced(checks["prompt"]),
                where="a validation prompt",
            ),
            "error": obj(
                {
                    "title": ref("text"),
                    "body": ref("text"),
                    "style": enum(doc.listed("Validations", after="`error.style` is")),
                },
                documented=braced(checks["error"]),
                where="a validation error",
            ),
        },
        documented=checks,
        required=("at",),
        description="What cells will accept (§10).",
        where="a validation",
    )
    define["link"] = {
        "anyOf": [
            ref("text"),
            obj(
                {
                    "url": ref("text"),
                    "to": ref("text"),
                    "tip": ref("text"),
                },
                documented=doc.keys("Links"),
                where="a link",
            ),
        ]
    }
    define["comment"] = {
        "anyOf": [
            ref("text"),
            obj(
                {"text": ref("text"), "author": ref("text")},
                documented=doc.keys("Notes"),
                required=("text",),
                where="a note",
            ),
        ]
    }
    rules = doc.keys("Conditional formatting")
    extent = {
        "anyOf": [
            ref("integer"),
            obj(
                {"count": ref("integer"), "percent": ref("boolean")},
                documented=braced(rules["top"]),
                where="a top/bottom rule",
            ),
        ]
    }
    define["conditional"] = obj(
        {
            "at": ref("range"),
            "cell": ref("comparison"),
            "formula": ref("text"),
            "text": obj(
                {key: ref("scalar") for key in names(rules["text"])},
                documented=names(rules["text"]),
                where="a text rule",
            ),
            "top": extent,
            "bottom": extent,
            "duplicate": ref("boolean"),
            "unique": ref("boolean"),
            "color_scale": obj(
                {stop: ref("color") for stop in names(rules["color_scale"])},
                documented=names(rules["color_scale"]),
                required=("low", "high"),
                where="a colour scale",
            ),
            "data_bar": obj(
                {"color": ref("color"), "bar_only": ref("boolean")},
                documented=keyish(rules["data_bar"]),
                where="a data bar",
            ),
            "icon_set": {
                "anyOf": [
                    enum(doc.listed("The icon sets")),
                    obj(
                        {
                            "style": enum(doc.listed("The icon sets")),
                            "reverse": ref("boolean"),
                            "icons_only": ref("boolean"),
                        },
                        documented=braced(doc.comment("Conditional formatting", "icon_set")),
                        where="an icon set",
                    ),
                ]
            },
            "style": ref("style"),
            "format": ref("text"),
            "stop_if_true": ref("boolean"),
        },
        documented=rules,
        required=("at",),
        description="Formatting decided by the value (§10).",
        where="a conditional format",
    )

    # -- §11 tables --------------------------------------------------------

    tables = doc.keys("11. Tables")
    define["table"] = obj(
        {
            "at": ref("range"),
            "name": ref("text"),
            "style": enum(numbered_ranges(tables["style"])),
            "banded_rows": ref("boolean"),
            "banded_columns": ref("boolean"),
            "first_column": ref("boolean"),
            "last_column": ref("boolean"),
        },
        documented=tables,
        required=("at",),
        description="A region declared to be an Excel table (§11).",
        where="a table",
    )

    # -- §12 charts --------------------------------------------------------

    charts = doc.keys("12. Charts")
    chart_types = doc.types("12. Charts")
    define["size"] = obj(
        {"width": ref("integer"), "height": ref("integer")},
        documented=braced(chart_types["size"]),
        required=("width", "height"),
        description="A size in whole pixels.",
        where="a size",
    )
    define["axis"] = obj(
        {"title": ref("text"), "min": ref("number"), "max": ref("number")},
        documented=braced(chart_types["x_axis"]),
        description="An axis title and its manual bounds (§12).",
        where="an axis",
    )
    define["series"] = obj(
        {
            "values": ref("qualified_range"),
            "categories": ref("qualified_range"),
            "name": ref("text"),
            "name_from": {"anyOf": [ref("cell"), ref("qualified_cell")]},
        },
        documented=doc.keys("Series"),
        required=("values",),
        description="One plotted series (§12).",
        where="a chart series",
    )
    define["chart"] = obj(
        {
            "at": ref("cell"),
            "type": enum(doc.listed("12. Charts", after="**Types:**")),
            "series": seq(ref("series")),
            "title": ref("text"),
            "legend": enum(doc.alternatives("12. Charts", "legend")),
            "size": ref("size"),
            "x_axis": ref("axis"),
            "y_axis": ref("axis"),
        },
        documented=charts,
        required=("at", "type", "series"),
        description="A picture of cells that already exist (§12).",
        where="a chart",
    )

    # -- §13 images --------------------------------------------------------

    images = doc.keys("13. Images")
    positioning = enum(doc.column("13. Images", 1, 0))
    define["offset"] = obj(
        {"x": ref("integer"), "y": ref("integer")},
        documented=braced(doc.types("13. Images")["offset"]),
        required=("x", "y"),
        description="Pixels in from the cell's corner.",
        where="an offset",
    )
    define["image"] = obj(
        {
            "at": ref("cell"),
            "file": ref("path"),
            "alt": ref("text"),
            "scale": {
                "anyOf": [
                    ref("number"),
                    obj(
                        {"x": ref("number"), "y": ref("number")},
                        documented=braced(doc.types("13. Images")["scale"]),
                        where="an image scale",
                    ),
                ]
            },
            "offset": ref("offset"),
            "positioning": positioning,
        },
        documented=images,
        required=("at", "file"),
        description="A picture floating above the grid (§13).",
        where="an image",
    )

    # -- §14 pivots --------------------------------------------------------

    pivots = doc.keys("14. Pivot tables")
    define["pivot_field"] = {
        "anyOf": [
            ref("text"),
            obj(
                {"field": ref("text"), "name": ref("text")},
                documented=braced(pivots["rows"]),
                required=("field",),
                where="a pivot field",
            ),
        ]
    }
    define["pivot_value"] = {
        "anyOf": [
            ref("text"),
            obj(
                {
                    "field": ref("text"),
                    "function": enum(doc.listed("14. Pivot tables", after="**Functions:**")),
                    "name": ref("text"),
                },
                documented=braced(pivots["values"]),
                required=("field",),
                where="a pivot value",
            ),
        ]
    }
    define["pivot"] = obj(
        {
            "at": ref("range"),
            "source": ref("qualified_range"),
            "rows": seq(ref("pivot_field")),
            "columns": seq(ref("pivot_field")),
            "values": seq(ref("pivot_value")),
            "name": ref("text"),
            "style": enum(numbered_ranges(pivots["style"])),
            "row_grand_totals": ref("boolean"),
            "column_grand_totals": ref("boolean"),
        },
        documented=pivots,
        required=("at", "source"),
        description="A pivot table Excel recomputes on open (§14).",
        where="a pivot",
    )

    # -- §15 properties and calculation ------------------------------------

    document_properties = "15. Document properties and calculation"
    define["properties"] = obj(
        {
            key: (
                {
                    "type": "object",
                    "additionalProperties": ref("scalar"),
                    "description": "Properties of your own naming.",
                }
                if key == "custom"
                else ref("text")
            )
            for key in doc.example(document_properties, "properties")
        },
        documented=doc.example(document_properties, "properties"),
        description="What the file says about itself (§15).",
        where="document properties",
    )
    define["calc"] = obj(
        {
            "mode": enum(doc.alternatives(document_properties, "mode")),
            "on_load": ref("boolean"),
        },
        documented=doc.example(document_properties, "calc"),
        description="When Excel recalculates (§15).",
        where="calculation settings",
    )

    # -- §16 protection ----------------------------------------------------

    define["protect"] = obj(
        {
            "password": ref("text"),
            "allow": obj(
                {
                    permission: ref("boolean")
                    for permission in doc.listed("16. Protection", after="The full list:")
                },
                documented=doc.listed("16. Protection", after="The full list:"),
                description="What a reader may still do (§16).",
                where="a protection allowance",
            ),
        },
        documented=doc.example("16. Protection", "protect"),
        description="Protection: locked cells stay locked (§16).",
        where="protection",
    )

    # -- §18 shapes --------------------------------------------------------

    shapes = doc.keys("18. Shapes")
    define["shape"] = obj(
        {
            "at": ref("cell"),
            "kind": enum(doc.listed("18. Shapes", after="`kind` is one of:")),
            "text": {"anyOf": [ref("text"), seq(ref("rich_run"))]},
            "size": ref("size"),
            "fill": ref("color"),
            "line": {
                "anyOf": [
                    ref("color"),
                    obj(
                        {"color": ref("color"), "width": ref("number")},
                        documented=braced(doc.types("18. Shapes")["line"]),
                        where="a shape outline",
                    ),
                ]
            },
            "alt": ref("text"),
            "positioning": positioning,
        },
        documented=shapes,
        required=("at", "kind"),
        description="A box or other geometry over the grid (§18).",
        where="a shape",
    )

    # -- §19 sparklines ----------------------------------------------------

    sparklines = doc.keys("19. Sparklines")
    define["sparkline_cell"] = obj(
        {"at": ref("cell"), "data": ref("qualified_range")},
        documented=braced(doc.types("19. Sparklines")["cells"]),
        required=("at", "data"),
        where="a sparkline",
    )
    define["sparkline_group"] = obj(
        {
            "at": ref("cell"),
            "data": ref("qualified_range"),
            "cells": seq(ref("sparkline_cell")),
            "type": enum(names(sparklines["type"], stop="—")),
            "markers": ref("boolean"),
            "high": ref("boolean"),
            "low": ref("boolean"),
            "min": ref("integer"),
            "max": ref("integer"),
            "weight": ref("number"),
            "color": ref("color"),
            "colors": obj(
                {
                    mark: ref("color")
                    for mark in braced(doc.types("19. Sparklines")["colors"])
                },
                documented=braced(doc.types("19. Sparklines")["colors"]),
                where="sparkline colours",
            ),
            "axis": ref("boolean"),
        },
        documented=sparklines,
        description="A group of one-cell charts, scaled as one (§19).",
        where="a sparkline group",
    )

    # -- §20 form controls -------------------------------------------------

    define["control"] = obj(
        {
            "at": ref("cell"),
            "kind": enum(doc.listed("20. Form controls", after="**Kinds:**")),
            "size": ref("size"),
            "text": ref("text"),
            "checked": ref("boolean"),
            "link": ref("cell"),
            "min": ref("integer"),
            "max": ref("integer"),
            "step": ref("integer"),
            "value": ref("integer"),
            "page": ref("integer"),
            "horizontal": ref("boolean"),
        },
        documented=doc.keys("20. Form controls", belongs=True),
        required=("at", "kind"),
        description="A control writing into its linked cell (§20).",
        where="a form control",
    )

    # -- §21 slicers -------------------------------------------------------

    define["slicer"] = obj(
        {
            "at": ref("cell"),
            "table": ref("text"),
            "column": ref("text"),
            "caption": ref("text"),
            "size": ref("size"),
            "header": ref("boolean"),
        },
        documented=doc.keys("21. Slicers"),
        required=("at", "table", "column"),
        description="A table's filter as a panel of buttons (§21).",
        where="a slicer",
    )

    # -- §23 overrides -----------------------------------------------------

    define["override"] = obj(
        {"at": ref("qualified_cell"), "reason": ref("text"), **cell_facets},
        documented=doc.keys("23. Overrides"),
        required=("at",),
        description="A deliberate one-off deviation, applied last (§23).",
        where="an override",
    )

    # -- §2 sheets ---------------------------------------------------------

    sheets = doc.keys("2. Sheets")
    define["sheet"] = obj(
        {
            "name": ref("text"),
            "cells": ref("cells"),
            "formulas": seq(ref("formula_range")),
            "data": seq(ref("data")),
            "columns": seq(ref("column_band")),
            "rows": seq(ref("row_band")),
            "merges": seq(ref("range")),
            "visibility": enum(doc.alternatives("2. Sheets", "visibility")),
            "freeze": ref("cell"),
            "split": obj(
                {"x": ref("number"), "y": ref("number")},
                documented=braced(doc.types("2. Sheets")["split"]),
                where="a split",
            ),
            "gridlines": ref("boolean"),
            "tab_color": ref("color"),
            "print": ref("print"),
            "filter": ref("range"),
            "validations": seq(ref("validation")),
            "links": node(
                {
                    "type": "object",
                    "propertyNames": {"$ref": "#/definitions/cell"},
                    "additionalProperties": ref("link"),
                }
            ),
            "conditional": seq(ref("conditional")),
            "comments": node(
                {
                    "type": "object",
                    "propertyNames": {"$ref": "#/definitions/cell"},
                    "additionalProperties": ref("comment"),
                }
            ),
            "tables": seq(ref("table")),
            "charts": seq(ref("chart")),
            "images": seq(ref("image")),
            "shapes": seq(ref("shape")),
            "background": ref("path"),
            "sparklines": seq(ref("sparkline_group")),
            "controls": seq(ref("control")),
            "slicers": seq(ref("slicer")),
            "pivots": seq(ref("pivot")),
            "protect": ref("protect"),
        },
        documented=sheets,
        required=("name",),
        description="One sheet of the workbook (§2).",
        where="a sheet",
    )

    # -- §1 the document ---------------------------------------------------

    document = obj(
        {
            "sheets": seq(ref("sheet")),
            "active": ref("text"),
            "params": node(
                {
                    "type": "object",
                    "additionalProperties": ref("scalar"),
                }
            ),
            "defs": ref("defs"),
            "overrides": seq(ref("override")),
            "properties": ref("properties"),
            "calc": ref("calc"),
            "protect": node(ref("protect")),
            "date1904": ref("boolean"),
            "default_font": ref("text"),
        },
        documented=doc.keys("1. Document"),
        required=("sheets",),
        where="the document",
    )
    define["defs"] = obj(
        {
            "styles": node(
                {"type": "object", "additionalProperties": ref("style")}
            ),
            "values": node(
                {"type": "object", "additionalProperties": ref("scalar")}
            ),
            "formulas": node(
                {"type": "object", "additionalProperties": ref("text")}
            ),
        },
        documented=doc.example("6. Definitions and references", "defs"),
        description="Declared once, referenced by name (§6).",
        where="defs",
    )

    return {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "$id": SCHEMA_URL,
        "title": "yxl spec",
        "description": (
            "A yxl workbook spec (*.yxl.yaml). Generated from docs/spec.md by"
            " tools/spec-schema/generate.py — edit the reference, not this file."
        ),
        **document,
        "definitions": dict(sorted(define.items())),
    }


# --------------------------------------------------------------------------
# Running it
# --------------------------------------------------------------------------


def render(reference: Path) -> str:
    return json.dumps(
        build(Reference(reference.read_text(encoding="utf-8"))),
        indent=2,
        ensure_ascii=False,
    ) + "\n"


# Specs the schema must accept, and specs it must refuse. A schema that has
# quietly become `{}` still passes every corpus there is; only a refusal proves
# it is doing anything. Each refusal is a mistake an author actually makes.
ACCEPTED = {
    "a parameter where a number goes": "sheets: [{name: S, columns: [{at: B, width: '${w}'}]}]",
    "a row band selected by number": "sheets: [{name: S, rows: [{at: 1, height: 28}]}]",
    "a null field in a data block": "sheets: [{name: S, data: [{at: A1, values: [[1, null]]}]}]",
    "rich text runs": "sheets: [{name: S, cells: {A1: {rich: [a, {text: b, font: {bold: true}}]}}}]",
    "a style and nothing else": "sheets: [{name: S, cells: {B3: {style: shaded}}}]",
    "a quoted sheet name in an override": (
        "sheets: [{name: Q3 data, cells: {A1: 1}}]\n"
        "overrides: [{at: \"'Q3 data'!A1\", value: 2, reason: r}]"
    ),
    "a validation sourced from cells": (
        "sheets: [{name: S, validations: [{at: A1:A9, list: {from: 'St!A1:A3'}}]}]"
    ),
    "an included sheet": "sheets: [{$include: sheets/summary.yaml}]",
    "an included cells block": "sheets: [{name: S, cells: {$include: data/q3.yaml}}]",
    "an included document": "$include: real.yxl.yaml",
}

REFUSED = {
    "a misspelt sheet key": "sheets: [{name: S, celsl: {A1: 1}}]",
    "a misspelt top-level key": "sheets: [{name: S}]\nshets: []",
    "a misspelt cell facet": "sheets: [{name: S, cells: {A1: {valeu: 1}}}]",
    "a sheet with no name": "sheets: [{cells: {A1: 1}}]",
    "a document with no sheets": "params: {region: APAC}",
    "an address that is not one": "sheets: [{name: S, cells: {AA: 1}}]",
    "an icon set Excel refuses": (
        "sheets: [{name: S, conditional: [{at: A1:A9, icon_set: 5Boxes}]}]"
    ),
    "a chart type that is not one": (
        "sheets: [{name: S, charts: [{at: A1, type: colum, series: [{values: A1:A2}]}]}]"
    ),
    "a table style that is not one": (
        "sheets: [{name: S, tables: [{at: A1:B2, style: TableStyleMedium99}]}]"
    ),
    "a permission that is misspelt": (
        "sheets: [{name: S, protect: {allow: {sortt: true}}}]"
    ),
    "text where a width goes": "sheets: [{name: S, columns: [{at: B, width: wide}]}]",
    "a data block with no anchor": "sheets: [{name: S, data: [{csv: sales.csv}]}]",
    "an override that names no sheet": (
        "sheets: [{name: S, cells: {E37: 1}}]\noverrides: [{at: E37, value: 2}]"
    ),
}


def selftest(schema: dict) -> int:
    import jsonschema
    import yaml

    jsonschema.Draft7Validator.check_schema(schema)
    validator = jsonschema.Draft7Validator(schema)
    wrong = 0
    for cases, should_hold in ((ACCEPTED, True), (REFUSED, False)):
        for label, spec in cases.items():
            errors = list(validator.iter_errors(yaml.safe_load(spec)))
            if bool(errors) is should_hold:
                wrong += 1
                print(
                    f"the schema {'refuses' if errors else 'accepts'} {label},"
                    f" which it should {'accept' if should_hold else 'refuse'}",
                    file=sys.stderr,
                )
    print(f"{len(ACCEPTED)} accepted, {len(REFUSED)} refused, {wrong} wrong")
    return wrong


def validate(schema: dict, paths: list[str]) -> int:
    import jsonschema
    import yaml

    validator = jsonschema.Draft7Validator(schema)
    failed = 0
    for path in paths:
        with open(path, encoding="utf-8") as spec:
            document = yaml.safe_load(spec)
        errors = sorted(validator.iter_errors(document), key=lambda e: e.path)
        for error in errors[:5]:
            where = "/".join(str(part) for part in error.absolute_path)
            print(f"{path}: {where or '(root)'}: {error.message}", file=sys.stderr)
        if errors:
            failed += 1
        else:
            print(f"ok  {path}")
    return failed


def main(argv: list[str]) -> int:
    parse = argparse.ArgumentParser(description=__doc__)
    parse.add_argument(
        "--check",
        action="store_true",
        help="fail if the committed schema is not what docs/spec.md says",
    )
    parse.add_argument(
        "--selftest",
        action="store_true",
        help="check the schema still accepts and refuses what it must",
    )
    parse.add_argument(
        "--validate",
        nargs="+",
        metavar="SPEC",
        help="validate spec files against the schema",
    )
    args = parse.parse_args(argv)

    try:
        generated = render(REFERENCE)
    except Drift as drift:
        print(f"{REFERENCE.relative_to(ROOT)}: {drift}", file=sys.stderr)
        return 1

    if args.selftest:
        return 1 if selftest(json.loads(generated)) else 0

    if args.validate:
        return 1 if validate(json.loads(generated), args.validate) else 0

    if args.check:
        if not SCHEMA.exists() or SCHEMA.read_text(encoding="utf-8") != generated:
            print(
                f"{SCHEMA.relative_to(ROOT)} is not what docs/spec.md says."
                " Run tools/spec-schema/generate.py and commit the result.",
                file=sys.stderr,
            )
            return 1
        print(f"{SCHEMA.relative_to(ROOT)} is up to date")
        return 0

    SCHEMA.write_text(generated, encoding="utf-8")
    print(f"wrote {SCHEMA.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

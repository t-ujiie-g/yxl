// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add <user>/<module>

name = "t-ujiie-g/yxl"

version = "0.7.1"

readme = "README.mbt.md"

repository = "https://github.com/t-ujiie-g/yxl"

license = "Apache-2.0"

keywords = [ "yaml", "excel", "xlsx", "spreadsheet", "cli", "compiler" ]

// A native command-line compiler; the CLI reads/writes files on disk.

preferred_target = "native"

// Packages live under src/ (ADR-008). Only cli, include and cmd/main are
// importable by other modules; the compiler is under internal/ (ADR-028).

source = "src"

description = "A YAML-driven Excel (.xlsx) compiler and CLI — manage spreadsheets as version-controllable YAML with reuse/dedup, built on bobzhang/mbtexcel."

import {
  "moonbitlang/mbtexcel@0.3.1",
  "moonbit-community/yaml@0.0.6",
  "moonbitlang/x@0.5.6",
  "moonbit-community/flate@0.10.0",
}

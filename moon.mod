// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add <user>/<module>

name = "t-ujiie-g/yxl"

version = "0.3.6"

readme = "README.mbt.md"

repository = ""

license = "Apache-2.0"

keywords = [ "yaml", "excel", "xlsx", "spreadsheet", "cli", "compiler" ]

// A native command-line compiler; the CLI reads/writes files on disk.

preferred_target = "native"

// Packages live under src/ (ADR-008): diag, units, yaml, model, loader,
// resolve, emit, and the cli entry at cmd/main.

source = "src"

description = "A YAML-driven Excel (.xlsx) compiler and CLI — manage spreadsheets as version-controllable YAML with reuse/dedup, built on bobzhang/mbtexcel."

import {
  "bobzhang/mbtexcel@0.1.9",
  "moonbit-community/yaml@0.0.6",
  "moonbitlang/x@0.4.50",
}

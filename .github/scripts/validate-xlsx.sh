#!/usr/bin/env bash
#
# Check that each given `.xlsx` is a package Excel will open without offering to
# repair it — the failure `moon test` structurally cannot catch, because it
# re-opens our bytes with the library that wrote them (ROADMAP §5, Tier 3).
#
# The judgement comes from the Open XML SDK's own validator, which is what
# Microsoft's tooling uses: every part against the ECMA-376 schema, plus the
# SDK's semantic rules. See `tools/openxml-validator/`.
#
#   .github/scripts/validate-xlsx.sh out/*.xlsx
#
# Findings are compared against `tools/openxml-validator/known-defects.txt`, the
# list of violations that are the *backend's* and cannot be fixed from here.
# Anything else fails — and so does a known defect that has stopped happening,
# because a waiver nobody has to remove is a waiver that outlives its reason.

set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
project="$root/tools/openxml-validator/OpenXmlValidator.csproj"
validator="$root/tools/openxml-validator/bin/Release/net8.0/openxml-validator.dll"
known="$root/tools/openxml-validator/known-defects.txt"

if [ "$#" -eq 0 ]; then
  echo "usage: ${BASH_SOURCE[0]} <file.xlsx>..." >&2
  exit 2
fi

export DOTNET_NOLOGO=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1

if [ ! -f "$validator" ]; then
  dotnet build "$project" --configuration Release -p:UseAppHost=false >/dev/null
fi

found=$(mktemp)
expected=$(mktemp)
names=$(mktemp)
trap 'rm -f "$found" "$expected" "$names"' EXIT

# stdout is the progress log and goes straight through; stderr is the findings,
# which are what gets compared.
dotnet "$validator" "$@" 2>"$found" || true

# The waiver covers the whole corpus, so a run over part of it must compare
# against that part — otherwise validating one workbook by hand fails for the
# findings the other nine did not make. A block belongs to the file named on
# its unindented first line; `#` comments and blank lines document the waiver
# rather than form part of it.
for file in "$@"; do basename -- "$file"; done >"$names"

# A waiver names a workbook by its basename, and so does every finding the
# validator prints — so two inputs sharing one are indistinguishable here, and
# a waiver written for one would silently cover the other. Refuse the run
# rather than resolve it: the corpora are ours to name, and the collision is
# always a rename away.
if duplicates=$(sort "$names" | uniq -d) && [ -n "$duplicates" ]; then
  {
    echo "two inputs share a basename, which a waiver cannot tell apart:"
    echo "$duplicates" | sed 's/^/  /'
    echo "rename one — see tools/openxml-validator/known-defects.txt."
  } >&2
  exit 2
fi

grep -v -e '^#' -e '^[[:space:]]*$' "$known" |
  awk '
    NR == FNR { validated[$0] = 1; next }
    /^[^[:space:]]/ { keep = ($0 in validated) }
    keep
  ' "$names" - >"$expected"

if diff -u --label "known-defects.txt" "$expected" \
        --label "this run" "$found"; then
  waived=$(grep -c '^[^ ]' "$expected" || true)
  if [ "$waived" -gt 0 ]; then
    echo "valid, waiving $waived workbook(s) whose only findings are the backend's"
  fi
  exit 0
fi

cat >&2 <<'EOF'

The Open XML validity of the examples changed.

  Lines marked `+` are findings this run made and the waiver does not cover:
  a workbook yxl now writes that Excel would offer to repair. Fix it.

  Lines marked `-` are findings the waiver expects and this run did not make.
  If the backend fixed it, delete those lines from
  tools/openxml-validator/known-defects.txt (and the ROADMAP entry that
  explains them) in the same change.
EOF
exit 1

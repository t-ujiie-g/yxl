#!/usr/bin/env bash
# Package a built CLI into the archive a release publishes.
#
#   .github/scripts/package.sh <version> <target>
#
# Writes `yxl-<version>-<target>.{zip,tar.gz}` and a `.sha256` beside it into
# the current directory. Windows gets a .zip and a .exe — what its users can
# open and run without extra tools; everyone else gets a tarball.
#
# This lives in a script rather than inline in release.yml so CI can run it on
# every pull request. Packaging that only ever executes on a tag push is
# packaging nobody has tested: the missing `shasum` below reached a release tag
# precisely because nothing before it exercised this path on Windows.

set -euo pipefail

version=${1:?usage: package.sh <version> <target>}
target=${2:?usage: package.sh <version> <target>}

binary=_build/native/release/build/cmd/main/main.exe
[ -f "$binary" ] || {
  echo "package.sh: $binary is missing — build with 'moon build --target native --release' first" >&2
  exit 1
}

staging="yxl-$version-$target"
rm -rf "$staging"
mkdir "$staging"
cp README.md LICENSE "$staging/"
cp -r examples "$staging/"

case "${RUNNER_OS:-$(uname -s)}" in
  Windows | MINGW* | MSYS* | CYGWIN*)
    cp "$binary" "$staging/yxl.exe"
    archive="$staging.zip"
    rm -f "$archive"
    powershell -NoProfile -Command \
      "Compress-Archive -Path '$staging' -DestinationPath '$archive'"
    ;;
  *)
    cp "$binary" "$staging/yxl"
    chmod +x "$staging/yxl"
    archive="$staging.tar.gz"
    tar czf "$archive" "$staging"
    ;;
esac

# The runners do not agree on which checksum tool exists: Linux and Git Bash
# carry GNU `sha256sum`, macOS carries Perl's `shasum` and no sha256sum.
if command -v sha256sum >/dev/null 2>&1; then
  sum=$(sha256sum -b "$archive" | cut -d' ' -f1)
elif command -v shasum >/dev/null 2>&1; then
  sum=$(shasum -a 256 -b "$archive" | cut -d' ' -f1)
else
  echo "package.sh: neither sha256sum nor shasum is available" >&2
  exit 1
fi
# Written by hand rather than taken from the tool's own output so the format is
# the same on every platform. The `*` marks binary mode, which is what makes a
# later `sha256sum -c` read the archive correctly on Windows too.
printf '%s *%s\n' "$sum" "$archive" >"$archive.sha256"

echo "$archive"
echo "$sum"

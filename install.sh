#!/usr/bin/env sh
# Install the yxl CLI.
#
#   curl -fsSL https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.sh | sh
#
# Environment:
#   YXL_VERSION      version to install, e.g. 0.1.0 (default: the latest release)
#   YXL_INSTALL_DIR  where to put the binary (default: $HOME/.local/bin)
#
# The download is checked against the .sha256 published beside it; a mismatch
# aborts. Piping a script from the internet into a shell is a decision worth
# making deliberately — `curl -fsSLO …/install.sh` and read this first if you
# would rather.

set -eu

REPO="t-ujiie-g/yxl"
INSTALL_DIR="${YXL_INSTALL_DIR:-$HOME/.local/bin}"

# Colour only when stderr is a terminal, so piped output stays plain.
if [ -t 2 ]; then
  BOLD=$(printf '\033[1m') RED=$(printf '\033[31m') DIM=$(printf '\033[2m') OFF=$(printf '\033[0m')
else
  BOLD='' RED='' DIM='' OFF=''
fi

say() { printf '%s\n' "$*" >&2; }
die() { printf '%syxl: %s%s\n' "$RED" "$*" "$OFF" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "this installer needs '$1', which is not on your PATH"
}

need uname
need tar
# Errors are silenced because every caller below reports a better one, naming
# the URL and what it was for.
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL "$1" -o "$2" 2>/dev/null; }
  read_url() { curl -fsSL "$1" 2>/dev/null; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" "$1" 2>/dev/null; }
  read_url() { wget -qO- "$1" 2>/dev/null; }
else
  die "this installer needs 'curl' or 'wget', and found neither"
fi

# --- which build ------------------------------------------------------------

os=$(uname -s)
arch=$(uname -m)
case "$os" in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) die "unsupported operating system '$os' — build from source: https://github.com/$REPO#from-source" ;;
esac
case "$arch" in
  x86_64 | amd64) arch=x86_64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) die "unsupported architecture '$arch' — build from source: https://github.com/$REPO#from-source" ;;
esac
target="$os-$arch"
# Releases carry these three; anything else builds from source. An arm64 binary
# cannot run on an Intel Mac, so there is no fallback to substitute here.
case "$target" in
  linux-x86_64 | macos-arm64 | macos-x86_64) ;;
  *) die "no released binary for $target — build from source: https://github.com/$REPO#from-source" ;;
esac

version="${YXL_VERSION:-}"
if [ -z "$version" ]; then
  say "${DIM}Looking up the latest release…${OFF}"
  version=$(
    read_url "https://api.github.com/repos/$REPO/releases/latest" |
      sed -n 's/.*"tag_name" *: *"v\{0,1\}\([^"]*\)".*/\1/p' |
      head -n 1
  ) || true
  [ -n "$version" ] || die "could not determine the latest release — set YXL_VERSION=x.y.z to pin one"
fi
version="${version#v}"

# --- download, verify, install ----------------------------------------------

name="yxl-$version-$target"
base="https://github.com/$REPO/releases/download/v$version"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

say "${BOLD}Installing yxl $version ($target)${OFF}"
fetch "$base/$name.tar.gz" "$tmp/$name.tar.gz" ||
  die "could not download $base/$name.tar.gz (is v$version released for $target?)"
fetch "$base/$name.tar.gz.sha256" "$tmp/$name.tar.gz.sha256" ||
  die "could not download the checksum for $name.tar.gz"

if command -v sha256sum >/dev/null 2>&1; then
  checksum() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  checksum() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  die "this installer needs 'sha256sum' or 'shasum' to verify the download"
fi
expected=$(cut -d' ' -f1 <"$tmp/$name.tar.gz.sha256")
actual=$(checksum "$tmp/$name.tar.gz")
[ "$expected" = "$actual" ] ||
  die "checksum mismatch for $name.tar.gz — expected $expected, got $actual"

tar xzf "$tmp/$name.tar.gz" -C "$tmp"
[ -f "$tmp/$name/yxl" ] || die "the archive did not contain the expected yxl binary"

mkdir -p "$INSTALL_DIR"
# Replace by rename so a running yxl is never half-overwritten.
cp "$tmp/$name/yxl" "$tmp/yxl.new"
chmod 755 "$tmp/yxl.new"
mv -f "$tmp/yxl.new" "$INSTALL_DIR/yxl"

# Running it confirms the binary matches this machine, not just its name.
installed=$("$INSTALL_DIR/yxl" version 2>/dev/null) ||
  die "installed $INSTALL_DIR/yxl, but it would not run on this machine"

say ""
say "  ${BOLD}$installed${OFF} → $INSTALL_DIR/yxl"
case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    say "  Try: yxl help"
    ;;
  *)
    say ""
    say "  ${BOLD}$INSTALL_DIR is not on your PATH.${OFF} Add it to your shell profile:"
    say "    export PATH=\"$INSTALL_DIR:\$PATH\""
    ;;
esac
say ""

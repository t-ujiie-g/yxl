# Install the yxl CLI on Windows.
#
#   irm https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.ps1 | iex
#
# Environment:
#   YXL_VERSION      version to install, e.g. 0.1.0 (default: the latest release)
#   YXL_INSTALL_DIR  where to put the binary (default: %LOCALAPPDATA%\yxl\bin)
#
# The download is checked against the .sha256 published beside it; a mismatch
# aborts. Piping a script from the internet into a shell is a decision worth
# making deliberately — download this and read it first if you would rather.

$ErrorActionPreference = "Stop"
$repo = "t-ujiie-g/yxl"

$installDir = if ($env:YXL_INSTALL_DIR) { $env:YXL_INSTALL_DIR } else { "$env:LOCALAPPDATA\yxl\bin" }

function Fail($message) {
  Write-Host "yxl: $message" -ForegroundColor Red
  exit 1
}

# Releases carry x86_64 only. An arm64 Windows machine runs it under emulation,
# so this is a warning rather than a refusal.
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne "AMD64") {
  Write-Host "yxl: no native build for $arch; installing the x86_64 build, which Windows will emulate." -ForegroundColor Yellow
}
$target = "windows-x86_64"

$version = $env:YXL_VERSION
if (-not $version) {
  Write-Host "Looking up the latest release..." -ForegroundColor DarkGray
  try {
    $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing
    $version = $latest.tag_name -replace '^v', ''
  } catch {
    Fail "could not determine the latest release - set YXL_VERSION=x.y.z to pin one"
  }
}
$version = $version -replace '^v', ''

$name = "yxl-$version-$target"
$base = "https://github.com/$repo/releases/download/v$version"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
  Write-Host "Installing yxl $version ($target)" -ForegroundColor White
  try {
    Invoke-WebRequest -Uri "$base/$name.zip" -OutFile "$tmp\$name.zip" -UseBasicParsing
    Invoke-WebRequest -Uri "$base/$name.zip.sha256" -OutFile "$tmp\$name.zip.sha256" -UseBasicParsing
  } catch {
    Fail "could not download $base/$name.zip (is v$version released for $target?)"
  }

  $expected = ((Get-Content "$tmp\$name.zip.sha256" -Raw).Trim() -split '\s+')[0]
  $actual = (Get-FileHash "$tmp\$name.zip" -Algorithm SHA256).Hash.ToLower()
  if ($expected.ToLower() -ne $actual) {
    Fail "checksum mismatch for $name.zip - expected $expected, got $actual"
  }

  Expand-Archive -Path "$tmp\$name.zip" -DestinationPath $tmp -Force
  $binary = Join-Path $tmp "$name\yxl.exe"
  if (-not (Test-Path $binary)) { Fail "the archive did not contain the expected yxl.exe" }

  New-Item -ItemType Directory -Path $installDir -Force | Out-Null
  Copy-Item $binary (Join-Path $installDir "yxl.exe") -Force

  # Running it confirms the binary matches this machine, not just its name.
  $installed = & (Join-Path $installDir "yxl.exe") version
  if ($LASTEXITCODE -ne 0) { Fail "installed yxl.exe, but it would not run on this machine" }

  Write-Host ""
  Write-Host "  $installed" -NoNewline -ForegroundColor White
  Write-Host " -> $installDir\yxl.exe"

  $onPath = ($env:PATH -split ';') -contains $installDir
  if ($onPath) {
    Write-Host "  Try: yxl help"
  } else {
    Write-Host ""
    Write-Host "  $installDir is not on your PATH. Add it for this user with:" -ForegroundColor White
    Write-Host "    [Environment]::SetEnvironmentVariable('PATH', `"`$env:PATH;$installDir`", 'User')"
    Write-Host "  then open a new terminal."
  }
  Write-Host ""
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

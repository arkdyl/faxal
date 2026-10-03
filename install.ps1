# Installs faxal on Windows (PowerShell).
#
#   From a checkout of this repository (needs a C compiler: MinGW-w64 gcc, or clang):
#       .\install.ps1
#   From the web (downloads the latest release):
#       irm https://raw.githubusercontent.com/arkdyl/faxal/main/install.ps1 | iex
#
# Options (environment variables): FAXAL_BASE_URL, FAXAL_HOME (default %LOCALAPPDATA%\faxal), CC.

$ErrorActionPreference = "Stop"
function Say($m) { Write-Host "faxal: $m" }

$home_dir = if ($env:FAXAL_HOME) { $env:FAXAL_HOME } else { Join-Path $env:LOCALAPPDATA "faxal" }
$bin = Join-Path $home_dir "bin"
$share = Join-Path $home_dir "share\faxal"
New-Item -ItemType Directory -Force $bin, $share | Out-Null

$here = if ($PSScriptRoot) { $PSScriptRoot } else { "" }
$source = ""
$prebuilt = $false
if ($here -and (Test-Path (Join-Path $here "native\dist\faxal.c"))) {
  $source = Join-Path $here "native\dist\faxal.c"
  Say "building from $source"
} else {
  if (-not $env:FAXAL_BASE_URL) { $env:FAXAL_BASE_URL = "https://github.com/arkdyl/faxal/releases/latest/download" }
  Say "downloading from $env:FAXAL_BASE_URL"
  try {
    Invoke-WebRequest "$env:FAXAL_BASE_URL/faxal-windows-x86_64.exe" -OutFile (Join-Path $bin "faxal.exe")
    $prebuilt = $true
    Invoke-WebRequest "$env:FAXAL_BASE_URL/faxal.c" -OutFile (Join-Path $share "faxal.c") -ErrorAction SilentlyContinue
  } catch {
    $source = Join-Path $env:TEMP "faxal.c"
    Invoke-WebRequest "$env:FAXAL_BASE_URL/faxal.c" -OutFile $source
  }
}

if (-not $prebuilt) {
  $cc = $env:CC
  if (-not $cc) { foreach ($c in "gcc", "clang", "cc") { if (Get-Command $c -ErrorAction SilentlyContinue) { $cc = $c; break } } }
  if (-not $cc) { throw "no C compiler found. Install MinGW-w64 (for example: winget install BrechtSanders.WinLibs.POSIX.UCRT) and run this again" }
  Say "compiling with $cc"
  & $cc -O2 -std=c11 -o (Join-Path $bin "faxal.exe") $source
  if ($LASTEXITCODE -ne 0) { throw "the build failed" }
  Copy-Item $source (Join-Path $share "faxal.c") -Force
}

& (Join-Path $bin "faxal.exe") -e 'print("ok")' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "the installed faxal does not run" }
Say "installed: $bin\faxal.exe"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$bin*") {
  [Environment]::SetEnvironmentVariable("Path", "$bin;$userPath", "User")
  Say "added $bin to your PATH (open a new terminal to use it)"
}

#!/usr/bin/env powershell

<#
.SYNOPSIS
  Installs Git and a Chocolatey "ruby" package matching a major.minor prefix.

.DESCRIPTION
  Chocolatey's "ruby" package versions carry an extra packaging-revision
  suffix (e.g. "3.4.10.1") that changes over time, so an exact patch version
  like "3.4.8" isn't guaranteed to exist. This resolves -RubyVersion (a
  major.minor prefix such as "3.4" or "3.1") to the newest matching
  Chocolatey package version at image build time instead of hardcoding one.

  Kept as a standalone script (rather than an inline `RUN` one-liner) so the
  quoting needed for the Chocolatey OData query and PowerShell string/regex
  literals doesn't have to survive being re-flattened through Docker's
  Windows shell-form command concatenation.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $RubyVersion
)

$ErrorActionPreference = 'Stop'

choco install git --no-progress
if ($LASTEXITCODE -ne 0) { throw "choco install git failed with exit code $LASTEXITCODE" }

$feed = Invoke-RestMethod "https://community.chocolatey.org/api/v2/FindPackagesById()?id='ruby'"
$resolved = $feed |
    ForEach-Object { $_.properties.Version } |
    Where-Object { $_ -eq $RubyVersion -or $_ -like "$RubyVersion.*" } |
    Sort-Object { [version]($_ -replace '^(\d+\.\d+\.\d+)\.(\d+)$', '$1.$2') } |
    Select-Object -Last 1

if (-not $resolved) {
    throw "No Chocolatey 'ruby' package found matching version '$RubyVersion'"
}
Write-Output "Resolved Chocolatey ruby package version '$RubyVersion' -> '$resolved'"

choco install ruby --version=$resolved --no-progress
if ($LASTEXITCODE -ne 0) { throw "choco install ruby failed with exit code $LASTEXITCODE" }

# The Chocolatey "ruby" package doesn't ship (or run) the MSYS2/MINGW devkit
# toolchain that "ridk install" normally sets up, and several gems pulled in
# below (json, racc, libyajl2, ffi, ffi-yajl) need it to compile native
# extensions. Buildkite's "rubydistros" agents provide this out of the box;
# this image needs to install it explicitly. "ridk install" is an
# interactive-only menu with no reliable non-interactive/piped mode on
# Windows, so instead install MSYS2 directly to C:\msys64 - one of the
# default locations RubyInstaller's Msys2Installation#iterate_msys_paths
# auto-detects - and provision the MINGW toolchain via pacman.
choco install msys2 -y --no-progress --params "/InstallDir:C:\msys64 /NoUpdate"
if ($LASTEXITCODE -ne 0) { throw "choco install msys2 failed with exit code $LASTEXITCODE" }

$msysBash = "C:\msys64\usr\bin\bash.exe"

# Ruby built for the x64-mingw-ucrt platform (what Chocolatey's ruby package
# targets) needs the "ucrt64" MINGW toolchain, not the older "mingw64" one.
& $msysBash -lc "pacman -Syu --noconfirm"
if ($LASTEXITCODE -ne 0) { throw "pacman -Syu failed with exit code $LASTEXITCODE" }
& $msysBash -lc "pacman -S --needed --noconfirm base-devel mingw-w64-ucrt-x86_64-toolchain"
if ($LASTEXITCODE -ne 0) { throw "pacman toolchain install failed with exit code $LASTEXITCODE" }

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

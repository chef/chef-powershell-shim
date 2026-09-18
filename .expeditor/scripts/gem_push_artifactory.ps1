#!/usr/bin/env powershell

#Requires -Version 5

#####
##  Builds the chef-powershell DLL's and gem, then pushes the gem to the
##  internal Artifactory gems repo. Runs on Buildkite, where
##  .buildkite/hooks/pre-command has already exported ARTIFACTORY_LITA_PASSWORD.
#####

$ErrorActionPreference = "Stop"

if (-not $env:ARTIFACTORY_LITA_PASSWORD) {
  Write-Host "CRITICAL: ARTIFACTORY_LITA_PASSWORD environment variable not found" -ForegroundColor Red
  Write-Host "This variable should be set by .buildkite/hooks/pre-command for the gem_validate/release pipeline" -ForegroundColor Red
  exit 1
}

$project_root = "$(git rev-parse --show-toplevel)"

Write-Output "--- :key: Deriving Artifactory API key from injected credentials"
$credentials = "lita:$($env:ARTIFACTORY_LITA_PASSWORD)"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($credentials)
$env:GEM_HOST_API_KEY = "Basic $([System.Convert]::ToBase64String($bytes))"
$credentials = $null
Write-Output "`r"

$env:HAB_ORIGIN = "chef"
$env:CHEF_LICENSE = "accept-no-persist"
$env:HAB_LICENSE = "accept-no-persist"
$env:HAB_NONINTERACTIVE = "true"
$env:HAB_BLDR_CHANNEL = "base-2025"
$env:HAB_REFRESH_CHANNEL = "base-2025"
$env:FORCE_FFI_YAJL = "ext"
$env:PROJECT_NAME = "chef-powershell"
# TODO: confirm this is the correct internal Artifactory host and local gems repo name for chef-powershell
$env:ARTIFACTORY_ENDPOINT = "https://artifactory-internal.ps.chef.co/artifactory"
$env:ARTIFACTORY_GEM_REPO = "omnibus-gems-local"

Write-Output "--- :muscle: Setting the Project Root"
Set-Location $project_root
Write-Output "`r"

if (Test-Path -PathType leaf "/hab/cache/keys/$env:HAB_ORIGIN-*.sig.key") {
  Write-Output "--- :key: Using existing '$env:HAB_ORIGIN' origin key"
}
else {
  Write-Output "--- :key: Generating '$env:HAB_ORIGIN' origin key"
  hab origin key generate $env:HAB_ORIGIN
}
Write-Output "`r"

Write-Output "--- :construction: Building 64-bit PowerShell DLLs"
hab pkg build habitat --refresh-channel base-2025
if (-not $?) { throw "unable to build" }
Write-Output "`r"

Write-Output "--- :mag: Loading details of the build"
. results/last_build.ps1
if (-not $?) { throw "unable to determine details about this build" }

Write-Output "--- :screwdriver: Installing $pkg_ident"
hab pkg install results/$pkg_artifact
if (-not $?) { throw "unable to install this build" }
Write-Output "`r"

Write-Output "--- :hammer_and_wrench: Capturing the installation path"
$x64 = hab pkg path $env:HAB_ORIGIN/chef-powershell-shim
Write-Output "`r"

Write-Output "--- :truck: Copying compiled DLL's into the gem"
$arch = if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { "AMD64" }
$x64_bin_path = "$project_root\chef-powershell\bin\ruby_bin_folder\$arch"

if (Test-Path -PathType Container $x64_bin_path) {
  Get-ChildItem -Path $x64_bin_path -Recurse | Foreach-Object { Remove-Item -Recurse -Path $_.FullName -Force }
}
else {
  New-Item -Path $x64_bin_path -ItemType Directory -Force | Out-Null
}
Copy-Item "$x64\bin\*" -Destination $x64_bin_path -Force -Recurse
Write-Output "`r"

Write-Output "--- :package: Building the chef-powershell gem"
Set-Location "$project_root\chef-powershell"
gem build chef-powershell.gemspec
if (-not $?) { throw "gem build failed" }
Write-Output "`r"

Write-Output "--- :rocket: Pushing gem(s) to Artifactory"
gem install artifactory -v 3.0.17 --no-document
if (-not $?) { throw "unable to install the artifactory gem" }

ruby "$project_root\.expeditor\scripts\gem_push_artifactory.rb"
if (-not $?) { throw "Failed to push gem(s) to Artifactory" }

Write-Output "--- :white_check_mark: Gem push to Artifactory completed successfully"

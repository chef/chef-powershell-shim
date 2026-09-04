[CmdletBinding()]
param(
    [switch]$Publish,
    [switch]$Force
)

#########
## Purpose:
##  This script builds the chef-powershell gem and optionally publishes it to RubyGems.org.
##  By default, it builds the DLLs and gem locally without publishing.
##
## Options:
##  -Publish : Push the built gem to RubyGems.org (default: $false)
##  -Force   : Skip interactive confirmation prompt when -Publish is specified
##
## Assumptions:
##  1) You have access to https://rubygems.org/gems/chef-powershell (if publishing)
##  2) You have already merged changes to Main and updated your local main branch
##
#########

$ErrorActionPreference = "Stop"

$project_name = "chef-powershell"

Write-Output "--- Cleaning up old Hab directories for a minty fresh build experience"
# Is there a c:\hab directory? If so, nuke it.
if (Test-Path -Path c:\hab) {
    Remove-Item -LiteralPath c:\hab -Recurse -Force #-ErrorAction SilentlyContinue
}
Write-Output "`r"

Write-Output "--- Making sure we're in the correct spot"
$project_root = (git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Failed to determine git repository root. Are you in a git repository?"
}
Set-Location -Path $project_root
Write-Output "`r"

Write-Output "--- Is Habitat actually installed?"
# Is hab installed?
if (-not (Get-Command -Name Hab -ErrorAction SilentlyContinue)) {
    Write-Output "--- No, Installing Habitat via Choco"
    choco install habitat -y
    if (-not $?) { throw "unable to install Habitat" }
    Write-Output "`r"
}
Write-Output "`r"

Write-Output "--- Comparing local version to published version, updating the local version as appropriate"
try {
    $file = (Get-Content $("$project_root\chef-powershell\lib\chef-powershell\version.rb"))
}
catch {
    Write-Error "Failed to Get the Version from version.rb"
}
[version]$LocalVersion = [regex]::matches($file, "\s*VERSION\s=\s\`"(\d*.\d*.\d*)\`"\s*").groups[1].value

$rubygem = gem search chef-powershell
[version]$rubygemsversion = [regex]::matches($rubygem, "\s*chef-powershell\s*\((\d*.\d*.\d*)\)\s*").groups[1].value

if ($LocalVersion -eq $rubygemsversion) {
    . $("$project_root\.expeditor\update_version.ps1")
}
Write-Output "`r"

# compile
# check for existing hab folders and delete
Write-Output "--- Testing for existing hab folders and cleaning them up"
$hpath = "c:\hab"
if (Test-Path $hpath) {
    Remove-Item -LiteralPath $hpath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "--- Setting up Habitat to build PowerShell DLL's"
$env:HAB_ORIGIN = "ci"
$env:HAB_LICENSE = "accept-no-persist"
$env:FORCE_FFI_YAJL = "ext"

if (Test-Path -PathType leaf "/hab/cache/keys/ci-*.sig.key") {
    Write-Output "--- :key: Using existing fake '$env:HAB_ORIGIN' origin key"
}
else {
    Write-Output "--- :key: Generating fake '$env:HAB_ORIGIN' origin key"
    hab origin key generate $env:HAB_ORIGIN
}
Write-Output "`r"

Write-Output "--- :construction: Building 64-bit PowerShell DLL's"
hab pkg build Habitat --refresh-channel base-2025
if (-not $?) { throw "unable to build" }
Write-Output "`r"

. results/last_build.ps1
if (-not $?) { throw "unable to determine details about this build" }

Write-Output "--- :hammer_and_wrench: Installing 64-bit $pkg_ident"
hab pkg install results/$pkg_artifact
if (-not $?) { throw "unable to install this build" }
Write-Output "`r"

Write-Output "--- :hammer_and_wrench: Capturing the x64 installation path"
$x64 = hab pkg path ci/chef-powershell-shim
Write-Output "`r"

. results/last_build.ps1
if (-not $?) { throw "unable to determine details about this build" }

Write-Output "--- :hammer_and_wrench: Installing 32-bit $pkg_ident"
# Hab throws an Access Denied sometimes if we install immediately after the build. 5 seconds seems to be enough.
Start-Sleep -Seconds 5
hab pkg install results/$pkg_artifact
if (-not $?) { throw "unable to install this build" }
Write-Output "`r"

Write-Output "--- :cleanup, cleanup, everybody, everywhere: Deleting existing DLL's in the chef-powershell Directory and copying the newly compiled ones down"
$arch = if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { "AMD64" }
$x64_bin_path = $("$project_root/chef-powershell/bin/ruby_bin_folder/$arch")

if (Test-Path -PathType Container $x64_bin_path) {
    Get-ChildItem -Path $x64_bin_path -Recurse | Foreach-object { Remove-item -Recurse -path $_.FullName -Force }
    Copy-Item "$x64\bin\*" -Destination $x64_bin_path -Force -Recurse
}
else {
    New-Item -Path $x64_bin_path -ItemType Directory -Force
    Copy-Item "$x64\bin\*" -Destination $x64_bin_path -Force -Recurse
}
Write-Output "`r"

Write-Output "--- Moving to the chef-powershell gem directory"
Set-Location "$project_root\chef-powershell"
Write-Output "`r"

Write-Output "--- Verifying gem code and running tests"
bundle update
bundle exec rake gem_check
if (-not $?) { throw "Gem verification failed! Aborting build." }
Write-Output "`r"

Write-Output "--- Running smoke test for built DLLs"
bundle exec ruby smoke_test_dlls.rb "$x64\bin"
if (-not $?) { throw "DLL smoke test failed! Aborting build." }
Write-Output "`r"

Write-Output "--- Building the gem"
gem build $("$project_name.gemspec")
if (-not $?) { throw "Gem Build failed" }
Write-Output "`r"

try {
    $file = (Get-Content $("$project_root\chef-powershell\lib\chef-powershell\version.rb"))
}
catch {
    Write-Error "Failed to Get the Version from version.rb"
}
[string]$Version = [regex]::matches($file, "\s*VERSION\s=\s\`"(\d*.\d*.\d*)\`"\s*").groups[1].value
$gemFile = $([string]$project_root + "\" + [string]$project_name + "\" + [string]$project_name + "-" + [string]$Version + ".gem" )

if (-not $Publish) {
    Write-Output "--- :white_check_mark: Gem successfully built at: $gemFile"
    Write-Output "--- NOTE: To publish this gem to RubyGems.org, re-run with the -Publish switch:"
    Write-Output "---       .\.expeditor\manual_gem_release.ps1 -Publish"
    Write-Output "`r"
    exit 0
}

Write-Output "--- Pushing the gem to RubyGems.org"
if (-not $Force) {
    $confirm = Read-Host "ARE YOU SURE you want to push $gemFile to RubyGems.org? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Output "Release aborted by user."
        exit 0
    }
}

gem push $($gemFile)
if (-not $?) { throw "Gem Push failed" }
Write-Output "`r"

Write-Output "--- Fin! You have successfully uploaded your spiffy new gem. Go play!"

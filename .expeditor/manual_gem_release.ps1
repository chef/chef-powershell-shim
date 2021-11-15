#########
## Purpose:
##  This script is written as manual process for bulding and publishing the chef-powershell gem.
##  There is currently no process to build a gem on a Windows image.
##
## Assumptions:
##  1) You have access to https://rubygems.org/gems/chef-powershell
##  2) You have already had the changes to your build branch merged back to Main and you have updated your local main branch - Main should match your local build branch
##  3) This script will create a temp branch, check out to it, build the dll's and the gem locally and then will publish your gem to Rubygems.org
##  4) Clearly that will create some churn as we'd like to push to Artifactory internally until a given gem is stable. Not possible currently
##  5) You'll need to build and test your completed gem locally and then push directly to Rubygems for now.
##
#########

$ErrorActionPreference = "Stop"

$project_name = "chef-powershell"

Write-Output "--- Making sure we're in the correct spot"
$project_root = [IO.Path]::GetFullPath("chef-powershell-shim")
Set-Location -Path $project_root
Write-Output "`r"

Write-Output "-- Is Habitat actually installed?"
# Is hab installed?
if(-not (Get-Command -Name Hab)){
    Write-Output "--- No, Installing Habitat via Choco"
    choco install habitat -y
    if (-not $?) { throw "unable to install Habitat" }
    Write-Output "`r"
}
Write-Output "`r"

Write-Output "--- Cleaning up old Hab directories for a minty fresh build experience"
# Is there a c:\hab directory? If so, nuke it.
if (Test-Path -Path c:\hab){
    Remove-Item -LiteralPath c:\hab -Recurse -Force -ErrorAction SilentlyContinue
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

if($LocalVersion -eq $rubygemsversion){
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
hab pkg build Habitat
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

Write-Output "--- :construction: Building 32-bit PowerShell DLL's"
hab pkg build -R Habitat-x86
if (-not $?) { throw "unable to build" }
Write-Output "`r"

. results/last_build.ps1
if (-not $?) { throw "unable to determine details about this build" }

Write-Output "--- :hammer_and_wrench: Installing 32-bit $pkg_ident"
# Hab throws an Access Denied sometimes if we install immediately after the build. 5 seconds seems to be enough.
Start-Sleep -Seconds 5
hab pkg install results/$pkg_artifact
if (-not $?) { throw "unable to install this build" }
Write-Output "`r"

Write-Output "--- :hammer_and_wrench: Capturing the x86 installation path"
$x86 = hab pkg path ci/chef-powershell-shim-x86
Write-Output "`r"

Write-Output "--- :cleanup, cleanup, everybody, everywhere: Deleting existing DLL's in the chef-powershell Directory and copying the newly compiled ones down"
$x64_bin_path = $("$project_root/chef-powershell/bin/ruby_bin_folder/AMD64")
$x86_bin_path = $("$project_root/chef-powershell/bin/ruby_bin_folder/x86")

if (Test-Path -PathType Container $x64_bin_path) {
    Get-ChildItem -Path $x64_bin_path -Recurse | Foreach-object { Remove-item -Recurse -path $_.FullName -Force }
    Copy-Item "$x64\bin\*" -Destination $x64_bin_path -Force -Recurse
}
else {
    New-Item -Path $x64_bin_path -ItemType Directory -Force
    Copy-Item "$x64\bin\*" -Destination $x64_bin_path -Force -Recurse
}
Write-Output "`r"

if (Test-Path -PathType Container $x86_bin_path) {
    Get-ChildItem -Path $x86_bin_path -Recurse | Foreach-object { Remove-item -Recurse -path $_.FullName -Force }
    Copy-Item "$x86\bin\*" -Destination $x86_bin_path -Force -Recurse
}
else {
    New-Item -Path $x86_bin_path -ItemType Directory -Force
    Copy-Item "$x86\bin\*" -Destination $x86_bin_path -Force -Recurse
}
Write-Output "`r"

Write-Output "--- :Moving to the chef-powershell gem directory"
Set-Location "$project_root\chef-powershell"
Write-Output "`r"

Write-Output "--- Finally building the gem"
gem build $("$project_name.gemspec")
if (-not $?) { throw "Gem Build failed" }
Write-Output "`r"

Write-Output "--- pushing the gem to RubyGems.org"

try {
    $file = (Get-Content $("$project_root\chef-powershell\lib\chef-powershell\version.rb"))
}
catch {
    Write-Error "Failed to Get the Version from version.rb"
}
[string]$Version = [regex]::matches($file, "\s*VERSION\s=\s\`"(\d*.\d*.\d*)\`"\s*").groups[1].value
$gemfIle = $($project_root + "\" + $project_name + "\" + $project_name + "-" + $Version + ".gem" )
gem push $($gemfIle)
if (-not $?) { throw "Gem Push failed" }
Write-Output "`r"

Write-Output "--- Fin! You have successfully uploaded your spiffy new gem. Go play!"
﻿#!/usr/bin/env powershell

#Requires -Version 5

#####
##  To Run this script manually, clone this: https://github.com/chef/chef-powershell-shim.git
##  Then CD to the directory where that cloned repo lives.
##  Call this script from that directory with Dot notation - ". .c:\foo\build_dems.ps1"
##  Watch the magic unfold!
#####

$ErrorActionPreference = "Stop"

Write-Output "--- Removing existing Ruby instances"
$currentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$rubies = Get-ChildItem -Path "C:\ruby*"
foreach ($ruby in $rubies){
  Remove-Item -LiteralPath $ruby.FullName -Recurse -Force -ErrorAction SilentlyContinue
  $updatedpath = ($currentPath.Split(';') | Where-Object { $_ -ne $ruby.FullName }) -join ';'
}
[Environment]::SetEnvironmentVariable('PATH', $updatedpath, [EnvironmentVariableTarget]::Machine)
Write-Output "`r"

Write-Output "=== Starting the PowerShell Gem build process === "
Write-Output "`r"
Write-Output "--- system details"
$Properties = 'Caption', 'CSName', 'Version', 'BuildType', 'OSArchitecture'
Get-CimInstance Win32_OperatingSystem | Select-Object $Properties | Format-Table -AutoSize

Write-Output "--- Installing Habitat via Choco"
choco install habitat -y
if (-not $?) { throw "unable to install Habitat"}
Write-Output "`r"

Write-Output "--- Installing the latest Chef-Client"
choco install chef-client -y
if (-not $?) { throw "unable to install Chef-Client" }
Write-Output "`r"

Write-Output "--- Refreshing the build environment to pick up Hab binaries"
refreshenv
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User") + ";c:\opscode\chef\embedded\bin"
Write-Output "`r"

Write-Output "--- Correcting a gem build problem, moving header files around"
$filename = "ansidecl.h"
$locale = Get-ChildItem -path c:\opscode -Include $filename -Recurse -ErrorAction Ignore
$parent_folder = $locale.Directory.Parent.FullName
$child_folder = $parent_folder + "\x86_64-w64-mingw32\include"
Copy-Item $locale.FullName -Destination $child_folder -ErrorAction Continue
Write-Output "`r"

Write-Output "--- Updating Gems in the PowerShell Shim root directory"
bundle update
if (-not $?) { throw "Bundle Update failed"}
Write-Output "`r"

Write-Output "--- Setting up Habitat to build PowerShell DLL's"
$env:HAB_ORIGIN = "ci"
$env:HAB_LICENSE= "accept-no-persist"
$env:FORCE_FFI_YAJL="ext"

if (Test-Path -PathType leaf "/hab/cache/keys/ci-*.sig.key") {
    Write-Output "--- :key: Using existing fake '$env:HAB_ORIGIN' origin key"
} else {
    Write-Output "--- :key: Generating fake '$env:HAB_ORIGIN' origin key"
    hab origin key generate $env:HAB_ORIGIN
}
Write-Output "`r"

$project_root = "$(git rev-parse --show-toplevel)"
Set-Location $project_root

Write-Output "--- :construction: Building 64-bit PowerShell DLL's"
hab pkg build Habitat
if (-not $?) { throw "unable to build"}
Write-Output "`r"

. results/last_build.ps1
if (-not $?) { throw "unable to determine details about this build"}

Write-Output "--- :hammer_and_wrench: Installing 64-bit $pkg_ident"
hab pkg install results/$pkg_artifact
if (-not $?) { throw "unable to install this build"}
Write-Output "`r"

Write-Output "--- :hammer_and_wrench: Capturing the x64 installation path"
$x64 = hab pkg path ci/chef-powershell-shim
Write-Output "`r"

Write-Output "--- :construction: Building 32-bit PowerShell DLL's"
hab pkg build -R Habitat-x86
if (-not $?) { throw "unable to build"}
Write-Output "`r"

. results/last_build.ps1
if (-not $?) { throw "unable to determine details about this build"}

Write-Output "--- :hammer_and_wrench: Installing 32-bit $pkg_ident"
# Hab throws an Access Denied sometimes if we install immediately after the build. 5 seconds seems to be enough.
Start-Sleep -Seconds 5
hab pkg install results/$pkg_artifact
if (-not $?) { throw "unable to install this build"}
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
} else {
  New-Item -Path $x64_bin_path -ItemType Directory -Force
  Copy-Item "$x64\bin\*" -Destination $x64_bin_path -Force -Recurse
}
Write-Output "`r"

if (Test-Path -PathType Container $x86_bin_path) {
  Get-ChildItem -Path $x86_bin_path -Recurse| Foreach-object {Remove-item -Recurse -path $_.FullName -Force }
  Copy-Item "$x86\bin\*" -Destination $x86_bin_path -Force -Recurse
} else {
  New-Item -Path $x86_bin_path -ItemType Directory -Force
  Copy-Item "$x86\bin\*" -Destination $x86_bin_path -Force -Recurse
}
Write-Output "`r"

Write-Output "--- :Moving to the chef-powershell gem directory"
Set-Location "$project_root\chef-powershell"
Write-Output "`r"

Write-Output "--- :gem majesty: Installing Gems for the Chef-PowerShell Gem"
gem install bundler:2.2.29
gem install libyajl2-gem
gem install chef-powershell
if (-not $?) { throw "unable to install this build"}
Write-Output "`r"

Write-Output "--- Installing Node via Choco"
choco install nodejs -y
if (-not $?) { throw "unable to install Node"}
Write-Output "`r"

Write-Output "--- Refreshing the build environment to pick up Node.js binaries"
refreshenv
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User") + ";c:\opscode\chef\embedded\bin"
Write-Output "`r"

Write-Output "--- Installing CSPell via NPM, Getting Ready to SpellCheck the Gem code"
npm install -g cspell
if (-not $?) { throw "unable to install CSpell"}
Write-Output "`r"

Write-Output "--- Setting up Environment Variables for Ruby and Chef PowerShell"
$temp = Get-Location
$full_path = [string]$temp.path + "\bin\ruby_bin_folder\$env:PROCESSOR_ARCHITECTURE\"
[Environment]::SetEnvironmentVariable("CHEF_POWERSHELL_BIN", $full_path)
$gem_path = [string]$temp.path + "vendor\bundle\ruby\3.0.0"
[Environment]::SetEnvironmentVariable("GEM_PATH", $gem_path)
[Environment]::SetEnvironmentVariable("GEM_ROOT", $gem_path)
[Environment]::SetEnvironmentVariable("BUNDLE_GEMFILE", "$($temp.path)\Gemfile")
Write-Output "`r"

Write-Output "--- Updating Gem Configuration in the Chef-PowerShell child directory"
bundle config set --local without omnibus_package
bundle config set --local path 'vendor/bundle'
bundle install --jobs=3 --retry=3
if (-not $?) { throw "Unable to install gem configuration" }
Write-Output "`r"

Write-Output "--- Removing any existing Chef PowerShell DLL's since they'll conflict with rspec"
# remove the existing chef.powershell.dll and chef.powershell.wrapper.dll files under embedded\bin
$file = get-command bundle
$parent_folder = Split-Path -Path $file.Source
if (Test-Path $($parent_folder + "\chef.powershell.dll")){
  Remove-item -path $($parent_folder + "\chef.powershell.dll")
  Remove-item -path $($parent_folder + "\chef.powershell.wrapper.dll")
}
Write-Output "`r"

Write-Output "--- :finally verifying the gem code"
bundle exec rake gem_check
if (-not $?) { throw "Bundle Gem failed"}
Write-Output "`r"

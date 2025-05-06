#!/usr/bin/env powershell

#Requires -Version 5

#####
##  To Run this script manually, clone this: https://github.com/chef/chef-powershell-shim.git
##  Then CD to the directory where that cloned repo lives.
##  Call this script from that directory with Dot notation - ". .c:\foo\build_dems.ps1"
##  Watch the magic unfold!
#####

$ErrorActionPreference = "Stop"

Write-Output "--- :ruby: Removing existing Ruby instances"

$rubies = Get-ChildItem -Path "C:\ruby*"
foreach ($ruby in $rubies){
  Remove-Item -LiteralPath $ruby.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "`r"

# Need to set this variable to keep the build from failing while trying to resolve nonsense sdk paths
$env:MSBuildEnableWorkloadResolver = "false"

# setting the channel in this way gets access to the LTS channel and falls back to stable if the plan doesn't live there.
Write-Output "--- :shovel: Setting the BLDR and REFRESH Channels to LTS"
$env:HAB_BLDR_CHANNEL="LTS-2024"
$env:HAB_REFRESH_CHANNEL = "LTS-2024"
Write-Output "`r"

Write-Output "--- :screwdriver: Installing Habitat via Choco"
choco install habitat -y
if (-not $?) { throw "unable to install Habitat"}
Write-Output "`r"

Write-Output "--- :screwdriver: Installing the latest Chef-Client"
choco install chef-client -y
if (-not $?) { throw "unable to install Chef-Client" }
Write-Output "`r"

Write-Output "--- :chopsticks: Refreshing the build environment to pick up Hab binaries"
Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
refreshenv
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User") + ";c:\opscode\chef\embedded\bin"
Write-Output "`r"

Write-Output "--- :building_construction: Correcting a gem build problem, moving header files around"
$filename = "ansidecl.h"
$locale = Get-ChildItem -path c:\opscode -Include $filename -Recurse -ErrorAction Ignore
Write-Output "Copying ansidecl.h to the correct folder"
$parent_folder = $locale.Directory.Parent.FullName[1]
$child_folder = $parent_folder + "\x86_64-w64-mingw32\include"
Write-Output "`r"
Copy-Item $parent_folder -Destination $child_folder -ErrorAction Continue
Write-Output "`r"

Write-Output "--- :construction: Setting up Habitat to build PowerShell DLL's"
$env:HAB_ORIGIN = "core"
$env:HAB_LICENSE= "accept-no-persist"
$env:FORCE_FFI_YAJL="ext"
if (Test-Path -PathType leaf "/hab/cache/keys/core-*.sig.key") {
    Write-Output "--- :key: Using existing fake '$env:HAB_ORIGIN' origin key"
} else {
    Write-Output "--- :key: Generating fake '$env:HAB_ORIGIN' origin key"
    hab origin key generate $env:HAB_ORIGIN
}
Write-Output "`r"

Write-Output "--- :muscle: Setting the Project Root"
$project_root = "$(git rev-parse --show-toplevel)"
Set-Location $project_root
Write-Output "We should still be in c:\workdir. Are we? : $($project_root)"
Write-Output "`r"


Write-Output "--- :construction: Building 64-bit PowerShell DLLs"
hab pkg build Habitat --refresh-channel LTS-2024
if (-not $?) { throw "unable to build"}
Write-Output "`r"

Write-Output "--- :mag: Loading Details of 64-bit build"
. results/last_build.ps1
if (-not $?) { throw "unable to determine details about this build"}
Write-Output "`r"

Write-Output "--- :screwdriver: Installing 64-bit $pkg_ident"
hab pkg install results/$pkg_artifact
$pkg_artifact = $null
if (-not $?) { throw "unable to install this build"}
Write-Output "`r"

Write-Output "--- :hammer_and_wrench: Capturing the x64 installation path"
$x64 = hab pkg path core/chef-powershell-shim
Write-Output "Hab thinks it installed my 64-bit dlls here : $x64"
Test-Path -Path $x64
Write-Output "`r"


Write-Output "--- :muscle: cleanup, cleanup, everybody, everywhere: Deleting existing DLL's in the chef-powershell Directory and copying the newly compiled ones down"
$x64_bin_path = $("$project_root\chef-powershell\bin\ruby_bin_folder\AMD64")

if (Test-Path -PathType Container $x64_bin_path) {
  Write-Output "My 64-bit path WAS found here : $x64_bin_path"
  Get-ChildItem -Path $x64_bin_path -Recurse | Foreach-object { Remove-item -Recurse -path $_.FullName -Force }
  New-Item -Path $x64_bin_path -ItemType Directory -Force
  Copy-Item "$x64\bin\*" -Destination $x64_bin_path -Force -Recurse
}
else{
  Write-Output "My 64-bit path was NOT found, now building here : $x64_bin_path"
  New-Item -Path $x64_bin_path -ItemType Directory -Force
  Copy-Item "$x64\bin\*" -Destination $x64_bin_path -Force -Recurse
}

Write-Output "--- :truck: Moving to the chef-powershell gem directory"
Set-Location "$project_root\chef-powershell"
Write-Output "We are now here : $(Get-Location)"
Write-Output "`r"

Write-Output "--- :bank: Installing Gems for the Chef-PowerShell Gem"
gem install bundler
if (-not $?) { throw "unable to install this build"}
Write-Output "`r"

Write-Output "--- :bank: Installing Node via Choco"
choco install nodejs -y
if (-not $?) { throw "unable to install Node"}
Write-Output "`r"

Write-Output "--- :bank: Refreshing the build environment to pick up Node.js binaries"
refreshenv
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User") + ";c:\opscode\chef\embedded\bin"
Write-Output "`r"

Write-Output "--- :bank: Installing CSPell via NPM, Getting Ready to SpellCheck the Gem code"
npm install -g cspell
if (-not $?) { throw "unable to install CSpell"}
Write-Output "`r"

Write-Output "--- :mag: Find or Set the Chef_PowerShell_Bin Environment Variable"
if (-not(Test-Path env:CHEF_POWERSHELL_BIN)){
  # We are currently located in c:\workdir\chef-powershell
  # $project_root = (Get-ChildItem c:\workdir -Recurse | Where-Object { $_.PSIsContainer -and $_.Name.EndsWith($("$project_name-shim")) } | Select-Object -First 1).FullName
  $ps_root = Get-Location
  $full_path = $("$ps_root\bin\ruby_bin_folder\$env:PROCESSOR_ARCHITECTURE\")
  if (Test-Path -Path $full_path){
    Write-Output "The bin path is correct"
  }
  else {
    Write-Output "The bin path is incorrect"
  }
  [Environment]::SetEnvironmentVariable("CHEF_POWERSHELL_BIN", $full_path)
}
Write-Output "`r"

Write-Output "--- :building_construction: Setting up Environment Variables for Ruby and Chef PowerShell"
$temp = Get-Location
$gem_path = [string]$temp.path + "\vendor\bundle\ruby\3.4.0"
[Environment]::SetEnvironmentVariable("GEM_PATH", $gem_path)
[Environment]::SetEnvironmentVariable("GEM_ROOT", $gem_path)
[Environment]::SetEnvironmentVariable("BUNDLE_GEMFILE", "$($temp.path)\Gemfile")
Write-Output "`r"

Write-Output "--- :put_litter_in_its_place: Removing any existing Chef PowerShell DLL's since they'll conflict with rspec"
# remove the existing chef.powershell.dll and chef.powershell.wrapper.dll files under embedded\bin
$file = get-command bundle
$parent_folder = Split-Path -Path $file.Source
Write-Output "Removing files from here : $parent_folder"
if (Test-Path $($parent_folder + "\chef.powershell.dll")){
  Remove-item -path $($parent_folder + "\chef.powershell.dll")
  Remove-item -path $($parent_folder + "\chef.powershell.wrapper.dll")
}
Write-Output "`r"

Write-Output "--- :point_right: finally verifying the gem code (chefstyle, spellcheck, spec)"
bundle update
bundle exec rake gem_check
if (-not $?) { throw "Bundle Gem failed"}

Write-Output "`r"

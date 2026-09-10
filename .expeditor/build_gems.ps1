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
$env:HAB_BLDR_CHANNEL="base-2025"
$env:HAB_REFRESH_CHANNEL = "base-2025"
Write-Output "`r"

Write-Host "--- :screwdriver: Installing Habitat"
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/habitat-sh/habitat/main/components/hab/install.ps1'))
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
$env:HAB_ORIGIN = "chef"
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
hab pkg build Habitat --refresh-channel base-2025
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
$arch = if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { "AMD64" }
$x64_bin_path = $("$project_root\chef-powershell\bin\ruby_bin_folder\$arch")

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
# Use the LTS package (not the rolling "nodejs" package) to avoid picking up
# pre-release/alpha builds (e.g. 26.8.0-alpha.x), which cspell's engines check
# rejects with "Unsupported NodeJS version" even though it's technically newer
# than the minimum supported version.
choco install nodejs-lts -y
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
[Environment]::SetEnvironmentVariable("BUNDLE_GEMFILE", "$($temp.path)\Gemfile")
Write-Output "`r"

Write-Output "--- :gem: Pre-installing uri gem into vendor bundle to bootstrap Bundler on Ruby 3.1"
$ruby_version = (ruby -e "puts RbConfig::CONFIG['ruby_version']").Trim()
$vendor_dir = "$($temp.path)\vendor\bundle\ruby\$ruby_version"
New-Item -ItemType Directory -Force -Path $vendor_dir | Out-Null
gem install uri --install-dir $vendor_dir --no-document
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

# There are ~100 released chef-infra-client patch versions per major line, so we
# resolve the newest one for a given major version at run time via the Habitat
# Depot API rather than hardcoding a patch version that will inevitably go stale.
# `hab pkg install chef/chef-infra-client/18` does not support a major-only partial
# version, so we need the fully qualified origin/name/version/release ident anyway.
function Get-LatestHabPackageIdent {
  param(
    [Parameter(Mandatory=$true)] [string]$Origin,
    [Parameter(Mandatory=$true)] [string]$Name,
    [Parameter(Mandatory=$true)] [string]$Channel,
    [Parameter(Mandatory=$true)] [string]$MajorVersion
  )

  $matching_releases = @()
  $range = 0
  do {
    $page = Invoke-RestMethod "https://bldr.habitat.sh/v1/depot/channels/$Origin/$Channel/pkgs/$Name`?range=$range"
    $matching_releases += $page.data | Where-Object { $_.version -like "$MajorVersion.*" }
    $range += $page.data.Count
  } while ($page.data.Count -gt 0 -and $range -lt $page.total_count)

  if ($matching_releases.Count -eq 0) {
    throw "No $Origin/$Name releases matching version '$MajorVersion.*' found in the '$Channel' channel"
  }

  $latest = $matching_releases | Sort-Object { [version]$_.version }, release | Select-Object -Last 1
  return "$($latest.origin)/$($latest.name)/$($latest.version)/$($latest.release)"
}

# Habitat's chef-infra-client vendors a full copy of chef-powershell (lib/, bin/, ext/,
# gemspec) under vendor\gems\chef-powershell-<version>, and its own Bundler-based startup
# activates THAT gemspec before our code ever runs. That means Gem.loaded_specs["chef-powershell"]
# -- which our own resolve_wrapper_dll/resolve_core_wrapper_dll check first -- always points at
# the stale vendored copy, no matter what RUBYOPT/$LOAD_PATH tricks are used to shadow `require`.
# So instead of shadowing, we replace the vendored copy in place with this branch's code and
# freshly built DLLs, which is also a more faithful test of what a real Chef release will do.
function Set-VendoredChefPowerShellGem {
  param(
    [Parameter(Mandatory=$true)] [string]$ChefPkgIdent,
    [Parameter(Mandatory=$true)] [string]$FreshDllBin
  )

  $chef_pkg_path = hab pkg path $ChefPkgIdent
  $vendored_dir = Get-ChildItem "$chef_pkg_path\vendor\gems" -Filter "chef-powershell-*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $vendored_dir) { throw "Could not find a vendored chef-powershell gem under $chef_pkg_path\vendor\gems" }

  Write-Output "Replacing vendored chef-powershell at $($vendored_dir.FullName) with this branch's code + DLLs"
  Remove-Item "$($vendored_dir.FullName)\lib" -Recurse -Force
  Copy-Item "$project_root\chef-powershell\lib" "$($vendored_dir.FullName)\lib" -Recurse -Force
  Copy-Item "$project_root\chef-powershell\chef-powershell.gemspec" "$($vendored_dir.FullName)\chef-powershell.gemspec" -Force

  $vendored_dll_dir = "$($vendored_dir.FullName)\bin\ruby_bin_folder\$arch"
  Remove-Item $vendored_dll_dir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $vendored_dll_dir | Out-Null
  Copy-Item "$FreshDllBin\*" -Destination $vendored_dll_dir -Recurse -Force
}

function Invoke-ChefPowerShellIntegrationTest {
  param(
    [Parameter(Mandatory=$true)] [string]$Label,
    [Parameter(Mandatory=$true)] [scriptblock]$Invocation,
    [string]$ChefPowerShellBin
  )

  Write-Output "--- :test_tube: $Label"
  $original_chef_bin = $env:CHEF_POWERSHELL_BIN
  try {
    if ($ChefPowerShellBin) { $env:CHEF_POWERSHELL_BIN = $ChefPowerShellBin } else { Remove-Item Env:\CHEF_POWERSHELL_BIN -ErrorAction SilentlyContinue }
    & $Invocation
    if (-not $?) { throw "$Label failed" }
  }
  finally {
    if ($null -eq $original_chef_bin) { Remove-Item Env:\CHEF_POWERSHELL_BIN -ErrorAction SilentlyContinue } else { $env:CHEF_POWERSHELL_BIN = $original_chef_bin }
  }
  Write-Output "`r"
}

Write-Output "--- :mag: Determining which Chef version to integration-test against this Ruby"
$ruby_version = (ruby -e "puts RbConfig::CONFIG['ruby_version']").Trim()
Write-Output "System Ruby under test: $ruby_version"
Write-Output "`r"

$integration_test_script = "$project_root\chef-powershell\chef_gem_integration_test.rb"

if ($ruby_version.StartsWith("3.1")) {
  # ---- Chef-18 ships as both Omnibus and Habitat: test it both ways ----

  Write-Output "--- :gem: Building a local chef-powershell gem to replace Chef-18's bundled version"
  Push-Location "$project_root\chef-powershell"
  Remove-Item *.gem -ErrorAction SilentlyContinue
  gem build chef-powershell.gemspec
  if (-not $?) { throw "unable to build the chef-powershell gem" }
  $built_gem = (Get-ChildItem *.gem | Select-Object -First 1).FullName
  Pop-Location
  Write-Output "`r"

  Write-Output "--- :gem: Replacing the chef-powershell gem bundled in the Omnibus Chef-18 install"
  & C:\opscode\chef\embedded\bin\gem.cmd install $built_gem --no-document
  if (-not $?) { throw "unable to install local chef-powershell gem into Omnibus Chef-18" }
  Write-Output "`r"

  Invoke-ChefPowerShellIntegrationTest -Label "Chef-18 (Omnibus) integration test" -ChefPowerShellBin $x64_bin_path -Invocation {
    & C:\opscode\chef\embedded\bin\ruby.exe $integration_test_script
  }

  Write-Output "--- :package: Installing Chef-18 (Habitat) for integration testing"
  # chef/chef-infra-client is published to 'stable', not the 'base-2025' channel set above for our own package build
  $chef18_ident = Get-LatestHabPackageIdent -Origin "chef" -Name "chef-infra-client" -Channel "stable" -MajorVersion "18"
  Write-Output "Resolved latest Chef-18 Habitat package: $chef18_ident"
  hab pkg install $chef18_ident --channel stable
  if (-not $?) { throw "unable to install $chef18_ident" }
  Write-Output "`r"

  Set-VendoredChefPowerShellGem -ChefPkgIdent $chef18_ident -FreshDllBin $x64_bin_path

  Invoke-ChefPowerShellIntegrationTest -Label "Chef-18 (Habitat) integration test" -Invocation {
    hab pkg exec $chef18_ident ruby $integration_test_script
  }
}
elseif ($ruby_version.StartsWith("3.4")) {
  # ---- Chef-19 ships as Habitat only ----

  Write-Output "--- :package: Installing Chef-19 (Habitat) for integration testing"
  # chef/chef-infra-client is published to 'stable', not the 'base-2025' channel set above for our own package build
  $chef19_ident = Get-LatestHabPackageIdent -Origin "chef" -Name "chef-infra-client" -Channel "stable" -MajorVersion "19"
  Write-Output "Resolved latest Chef-19 Habitat package: $chef19_ident"
  hab pkg install $chef19_ident --channel stable
  if (-not $?) { throw "unable to install $chef19_ident" }
  Write-Output "`r"

  Set-VendoredChefPowerShellGem -ChefPkgIdent $chef19_ident -FreshDllBin $x64_bin_path

  Invoke-ChefPowerShellIntegrationTest -Label "Chef-19 (Habitat) integration test" -Invocation {
    hab pkg exec $chef19_ident ruby $integration_test_script
  }
}
else {
  throw "Unrecognized Ruby version '$ruby_version' - no Chef integration test mapping for it"
}
Write-Output "`r"

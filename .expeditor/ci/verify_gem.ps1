#!/usr/bin/env powershell

#Requires -Version 5

#####
##  To Run this script manually, clone this: https://github.com/chef/chef-powershell-shim.git
##  Then CD to the directory where that cloned repo lives.
##  Call this script from that directory with Dot notation - ". .c:\foo\build_dems.ps1"
##  Watch the magic unfold!
#####

$ErrorActionPreference = "Stop"

# Keep the Ruby that ships in the docker image (3.1.x or 3.4.x): the Ruby version selects which Chef
# major version this job tests. Chef's own Ruby must never be the one running this script.
$image_ruby = Get-Command ruby -ErrorAction Stop
Write-Output "Image Ruby: $($image_ruby.Source) ($(& ruby --version))"
Write-Output "`r"

# Need to set this variable to keep the build from failing while trying to resolve nonsense sdk paths
$env:MSBuildEnableWorkloadResolver = "false"

# setting the channel in this way gets access to the LTS channel and falls back to stable if the plan doesn't live there.
Write-Output "--- :shovel: Setting the BLDR and REFRESH Channels to LTS"
$env:HAB_BLDR_CHANNEL="base-2025"
$env:HAB_REFRESH_CHANNEL = "base-2025"
Write-Output "`r"

Write-Host "--- :screwdriver: Installing Habitat"
if (-not (Get-Command -Name hab -ErrorAction SilentlyContinue)) {
  Write-Output "--- Now Installing Habitat via Choco"
  choco install habitat -y
  Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
  refreshenv
  if (-not $?) { throw "unable to install Habitat" }
}
Write-Output "`r"

Write-Output "--- :chopsticks: Refreshing the build environment to pick up Hab binaries"
Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
refreshenv
# refreshenv can drop the image's Ruby from PATH; put its folder back first
$env:Path = (Split-Path $image_ruby.Source) + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
Write-Output "`r"

# Write-Output "--- :building_construction: Correcting a gem build problem, moving header files around"
# $filename = "ansidecl.h"
# $locale = Get-ChildItem -path c:\opscode -Include $filename -Recurse -ErrorAction Ignore
# Write-Output "Copying ansidecl.h to the correct folder"
# $parent_folder = $locale.Directory.Parent.FullName[1]
# $child_folder = $parent_folder + "\x86_64-w64-mingw32\include"
# Write-Output "`r"
# Copy-Item $parent_folder -Destination $child_folder -ErrorAction Continue
# Write-Output "`r"

Write-Output "--- :construction: Setting up Habitat to build PowerShell DLL's"
$env:HAB_ORIGIN = "chef"
$env:HAB_LICENSE= "accept-no-persist"
$env:FORCE_FFI_YAJL="ext"
if (Test-Path -PathType leaf "/hab/cache/keys/$env:HAB_ORIGIN-*.sig.key") {
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
hab pkg build habitat --refresh-channel base-2025
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
$x64 = hab pkg path $env:HAB_ORIGIN/chef-powershell-shim
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

Write-Output "--- :mag: Checking the DLL payload copied from the Habitat package"
# chef-powershell-shim's habitat/plan.ps1 ships the VC++ runtime next to the wrapper DLLs; the gem loads them from here.
Get-ChildItem -Path $x64_bin_path -File | Sort-Object Name | ForEach-Object { Write-Output ("  {0,-48} {1,10:N0} bytes" -f $_.Name, $_.Length) }
$expected_dlls = @("Chef.PowerShell.Wrapper.dll", "Chef.PowerShell.dll", "vcruntime140.dll", "msvcp140.dll")
foreach ($dll in $expected_dlls) {
  if (-not (Test-Path (Join-Path $x64_bin_path $dll))) { throw "$dll is missing from $x64_bin_path - the Habitat build or the copy above did not produce a complete payload" }
}
Write-Output "`r"

Write-Output "--- :truck: Moving to the chef-powershell gem directory"
Set-Location "$project_root\chef-powershell"
Write-Output "We are now here : $(Get-Location)"
Write-Output "`r"

Write-Output "--- :bank: Installing Gems for the Chef-PowerShell Gem"
gem install bundler
if (-not $?) { throw "unable to install this build"}
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

Write-Output "--- :point_right: Running the gem's specs (unit + DLL integration) against the freshly built DLLs"
# Style and spellcheck are not run here: they only need a source checkout and run in .github/workflows/lint.yml.
# These specs load the real DLLs, so they have to run after the Habitat build above.
bundle update
if (-not $?) { throw "Bundle update failed"}
bundle exec rake spec
if (-not $?) { throw "The gem's specs failed"}

Write-Output "`r"

# The newest chef-infra-client of a given major version is resolved at run time via the Habitat
# Depot API rather than pinned, so every promotion of an unreleased Chef package (the 'unstable'
# channel) is tested against this repo's chef-powershell code.
# `hab pkg install chef/chef-infra-client/18` does not support a major-only partial
# version, so we need the fully qualified origin/name/version/release ident anyway.
# The Depot lists a channel oldest-first (thousands of entries in 'unstable'), so we read pages from
# the newest end backwards and stop once we have walked past the requested major version.
function Get-LatestHabPackageIdent {
  param(
    [Parameter(Mandatory=$true)] [string]$Origin,
    [Parameter(Mandatory=$true)] [string]$Name,
    [Parameter(Mandatory=$true)] [string]$Channel,
    [Parameter(Mandatory=$true)] [string]$MajorVersion
  )

  $base_url = "https://bldr.habitat.sh/v1/depot/channels/$Origin/$Channel/pkgs/$Name"
  $first_page = Invoke-RestMethod "$base_url`?range=0"
  $total = $first_page.total_count
  $page_size = [math]::Max($first_page.data.Count, 1)

  $matching_releases = @()
  $range = [math]::Max($total - $page_size, 0)
  while ($true) {
    $page = Invoke-RestMethod "$base_url`?range=$range"
    $page_matches = @($page.data | Where-Object { $_.version -like "$MajorVersion.*" })
    if ($page_matches.Count -gt 0) {
      $matching_releases += $page_matches
    } elseif ($matching_releases.Count -gt 0) {
      break
    }
    if ($range -eq 0) { break }
    $range = [math]::Max($range - $page_size, 0)
  }

  if ($matching_releases.Count -eq 0) {
    throw "No $Origin/$Name releases matching version '$MajorVersion.*' found in the '$Channel' channel"
  }

  $latest = $matching_releases | Sort-Object { [version]$_.version }, release | Select-Object -Last 1
  return "$($latest.origin)/$($latest.name)/$($latest.version)/$($latest.release)"
}

# Habitat's chef-infra-client carries its own copy of chef-powershell under
# vendor\gems\chef-powershell-<version> and pins it in its Bundler files. To simulate a real
# release, this uninstalls that copy and `gem install`s the gem built from this branch with the
# package's own Ruby and gem environment (so extconf.rb runs and the gemspec is registered), then
# repoints the package's Bundler pin at the new version. Nothing is copied piecemeal from the repo.
# Whether Bundler then really activates this copy is asserted by chef_gem_integration_test.rb
# (CHEF_POWERSHELL_EXPECTED_VERSION and CHEF_POWERSHELL_EXPECTED_LIB), so a pin that wins fails the job.
function Install-BuiltGemIntoHabitatChef {
  param(
    [Parameter(Mandatory=$true)] [string]$ChefPkgIdent,
    [Parameter(Mandatory=$true)] [string]$BuiltGem
  )

  $chef_pkg_path = (hab pkg path $ChefPkgIdent | Out-String).Trim()
  $vendored_dir = Get-ChildItem "$chef_pkg_path\vendor\gems" -Filter "chef-powershell-*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $vendored_dir) { throw "Could not find a vendored chef-powershell gem under $chef_pkg_path\vendor\gems" }
  $old_version = $vendored_dir.Name -replace "^chef-powershell-", ""
  $new_version = [System.IO.Path]::GetFileNameWithoutExtension($BuiltGem) -replace "^chef-powershell-", ""
  Write-Output "Package vendors chef-powershell $old_version at $($vendored_dir.FullName); installing the built $new_version in its place"

  Write-Output "Bundler files in the package that mention chef-powershell (before):"
  $bundler_files = Get-ChildItem $chef_pkg_path -File -Recurse -Depth 3 -Include "Gemfile", "Gemfile.lock", "config" -ErrorAction SilentlyContinue |
    Where-Object { Select-String -Path $_.FullName -Pattern "chef-powershell" -Quiet }
  $bundler_files | ForEach-Object {
    Write-Output "  $($_.FullName)"
    Select-String -Path $_.FullName -Pattern "chef-powershell" | ForEach-Object { Write-Output "    $($_.Line.Trim())" }
  }

  # Run the package's own gem with its runtime environment (GEM_HOME/GEM_PATH point at its vendor
  # directory) so the old gem is replaced the way RubyGems would, including vendor\specifications.
  hab pkg exec $ChefPkgIdent gem uninstall chef-powershell --all --executables --ignore-dependencies --force
  if ($LASTEXITCODE -ne 0) { throw "unable to uninstall the vendored chef-powershell $old_version from $ChefPkgIdent" }
  hab pkg exec $ChefPkgIdent gem install $BuiltGem --local --ignore-dependencies --no-document
  if ($LASTEXITCODE -ne 0) { throw "unable to install $BuiltGem into $ChefPkgIdent" }
  if (-not (Test-Path "$chef_pkg_path\vendor\gems\chef-powershell-$new_version")) { throw "chef-powershell-$new_version was not installed under $chef_pkg_path\vendor\gems" }

  if ($old_version -ne $new_version) {
    $bundler_files | ForEach-Object {
      $text = Get-Content $_.FullName -Raw
      $updated = $text.Replace("chef-powershell-$old_version", "chef-powershell-$new_version").Replace("chef-powershell ($old_version)", "chef-powershell ($new_version)")
      if ($updated -ne $text) { Set-Content -Path $_.FullName -Value $updated -NoNewline; Write-Output "Repointed the chef-powershell pin in $($_.FullName)" }
    }
  }
  $script:installed_gem_dir = "$chef_pkg_path\vendor\gems\chef-powershell-$new_version"
}

# Installs the newest Chef-18 Omnibus package from the 'current' channel (every unreleased
# Chef-18 build) via the licensed Chef download API, which needs CHEF_LICENSE_KEY.
# `v=18` asks the API for the newest 18.x; the resolved version is logged after the install.
function Install-ChefOmnibusCurrent {
  param([Parameter(Mandatory=$true)] [string]$MajorVersion)

  if ([string]::IsNullOrWhiteSpace($env:CHEF_LICENSE_KEY)) {
    throw "CHEF_LICENSE_KEY is not set; it is required to download Chef-Client from the licensed Chef download API"
  }
  $chef_msi = Join-Path $env:TEMP "chef-client-$MajorVersion-current.msi"
  $chef_url = "https://chefdownload-commercial.chef.io/current/chef/download?p=windows&pv=2022&m=x86_64&v=$MajorVersion&license_id=$($env:CHEF_LICENSE_KEY)"
  # The progress bar makes Invoke-WebRequest extremely slow in Windows PowerShell 5.
  $ProgressPreference = 'SilentlyContinue'
  # The URL contains the license key, so neither it nor an exception carrying it is printed.
  Write-Output "Downloading the latest Chef-Client $MajorVersion from the 'current' channel of chefdownload-commercial.chef.io"
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $chef_url -OutFile $chef_msi -TimeoutSec 600
  }
  catch {
    $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "n/a" }
    throw "Chef-Client $MajorVersion download failed (HTTP status $status)"
  }
  Write-Output "Downloaded $([math]::Round((Get-Item $chef_msi).Length / 1MB, 1)) MB, installing"
  $chef_msi_log = Join-Path $env:TEMP "chef-client-install.log"
  # Prints the install log tail and the installer process tree; only used when the install fails or hangs.
  function Write-MsiDiagnostics {
    Get-Content $chef_msi_log -Tail 50 -ErrorAction SilentlyContinue | ForEach-Object { Write-Output "  log> $_" }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -in 'msiexec.exe', 'rundll32.exe', '7z.exe' } |
      Select-Object ProcessId, ParentProcessId, Name, @{ n = 'Cmd'; e = { "$($_.CommandLine)".Substring(0, [math]::Min(120, "$($_.CommandLine)".Length)) } } |
      Format-Table -AutoSize | Out-String -Width 250 | Write-Output
  }

  # Start-Process hung in this container; Process.Start does not.
  $msi_psi = New-Object System.Diagnostics.ProcessStartInfo
  $msi_psi.FileName = "msiexec.exe"
  $msi_psi.Arguments = "/i `"$chef_msi`" /qn /norestart /l*v `"$chef_msi_log`""
  $msi_psi.UseShellExecute = $false
  $msi_psi.CreateNoWindow = $true
  $msi = [System.Diagnostics.Process]::Start($msi_psi)
  $msi_started = Get-Date
  Write-Output "$(Get-Date -Format 'HH:mm:ss') started msiexec PID $($msi.Id), log at $chef_msi_log"
  while (-not $msi.HasExited) {
    $elapsed = [int]((Get-Date) - $msi_started).TotalSeconds
    if ($elapsed -gt 600) {
      Write-MsiDiagnostics
      $msi.Kill()
      throw "Chef-Client MSI install timed out after 10 minutes"
    }
    Start-Sleep -Seconds 30
    Write-Output "$(Get-Date -Format 'HH:mm:ss') msiexec still running after $($elapsed + 30)s"
  }
  $msi.WaitForExit()
  Write-Output "msiexec exited with code $($msi.ExitCode) after $([int]((Get-Date) - $msi_started).TotalSeconds)s"
  if ($msi.ExitCode -notin 0, 3010) {
    Write-MsiDiagnostics
    throw "Chef-Client MSI install failed with exit code $($msi.ExitCode)"
  }
  Remove-Item $chef_msi -Force -ErrorAction SilentlyContinue
  if (-not (Test-Path "C:\opscode\chef\embedded\bin\gem.cmd")) { throw "unable to install Chef-Client" }
  $omnibus_manifest = Get-Content "C:\opscode\chef\version-manifest.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
  Write-Output "Installed Chef-Client Omnibus $($omnibus_manifest.build_version) from the 'current' channel"
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
    $global:LASTEXITCODE = 0
    & $Invocation
    # $? is not reliable for a native command run inside a scriptblock; the exit code is
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" }
  }
  finally {
    if ($null -eq $original_chef_bin) { Remove-Item Env:\CHEF_POWERSHELL_BIN -ErrorAction SilentlyContinue } else { $env:CHEF_POWERSHELL_BIN = $original_chef_bin }
  }
  Write-Output "`r"
}

Write-Output "--- :mag: Determining which Chef version to integration-test against this Ruby"
$ruby_version = (ruby -e "puts RbConfig::CONFIG['ruby_version']").Trim()
Write-Output "System Ruby under test: $ruby_version ($((Get-Command ruby).Source))"
Write-Output "`r"

$integration_test_script = "$project_root\chef-powershell\chef_gem_integration_test.rb"
# The integration test uses this to assert it is exercising this branch's chef-powershell code
$env:CHEF_POWERSHELL_EXPECTED_LIB = "$project_root\chef-powershell\lib"

Write-Output "--- :gem: Building a local chef-powershell gem with the same steps a release uses"
Push-Location "$project_root\chef-powershell"
Remove-Item *.gem -ErrorAction SilentlyContinue
gem build chef-powershell.gemspec
if (-not $?) { throw "unable to build the chef-powershell gem" }
$built_gem = (Get-ChildItem *.gem | Select-Object -First 1).FullName
Pop-Location
$built_gem_version = [System.IO.Path]::GetFileNameWithoutExtension($built_gem) -replace "^chef-powershell-", ""
# The integration test asserts the Chef under test activates exactly this version
$env:CHEF_POWERSHELL_EXPECTED_VERSION = $built_gem_version
Write-Output "`r"

if ($ruby_version.StartsWith("3.1")) {
  # ---- Chef-18 ships as both Omnibus and Habitat: test it both ways ----

  Write-Output "--- :screwdriver: Installing the latest Chef-18 Omnibus from the 'current' channel"
  Install-ChefOmnibusCurrent -MajorVersion "18"
  Write-Output "`r"

  Write-Output "--- :gem: Replacing the chef-powershell gem bundled in the Omnibus Chef-18 install"
  # RubyGems activates the highest installed version on a plain `require`, not whichever gem
  # was installed most recently -- a stale higher-numbered leftover would silently win over
  # the one we just built. Remove every other installed version first.
  (& C:\opscode\chef\embedded\bin\gem.cmd list chef-powershell --local) | Select-String -Pattern "chef-powershell \((.+)\)" | ForEach-Object {
    $_.Matches[0].Groups[1].Value -split ", " | Where-Object { $_ -ne $built_gem_version } | ForEach-Object {
      Write-Output "Uninstalling stale chef-powershell $_"
      & C:\opscode\chef\embedded\bin\gem.cmd uninstall chef-powershell -v $_ --force
    }
  }
  & C:\opscode\chef\embedded\bin\gem.cmd install $built_gem --no-document
  if (-not $?) { throw "unable to install local chef-powershell gem into Omnibus Chef-18" }
  Write-Output "`r"

  Invoke-ChefPowerShellIntegrationTest -Label "Chef-18 (Omnibus) integration test" -ChefPowerShellBin $x64_bin_path -Invocation {
    & C:\opscode\chef\embedded\bin\ruby.exe $integration_test_script
  }

  Write-Output "--- :package: Installing Chef-18 (Habitat) for integration testing"
  # Test against unreleased packages: 'unstable' gets every build, not the 'base-2025' channel set above for our own package build
  $chef18_ident = Get-LatestHabPackageIdent -Origin "chef" -Name "chef-infra-client" -Channel "unstable" -MajorVersion "18"
  Write-Output "Resolved latest Chef-18 Habitat package: $chef18_ident"
  hab pkg install $chef18_ident --channel unstable
  if (-not $?) { throw "unable to install $chef18_ident" }
  Write-Output "`r"

  Install-BuiltGemIntoHabitatChef -ChefPkgIdent $chef18_ident -BuiltGem $built_gem
  $env:CHEF_POWERSHELL_EXPECTED_GEM_DIR = $script:installed_gem_dir

  Invoke-ChefPowerShellIntegrationTest -Label "Chef-18 (Habitat) integration test" -Invocation {
    hab pkg exec $chef18_ident ruby $integration_test_script
  }
}
elseif ($ruby_version.StartsWith("3.4")) {
  # ---- Chef-19 ships as Habitat only ----

  Write-Output "--- :package: Installing Chef-19 (Habitat) for integration testing"
  # Test against unreleased packages: 'unstable' gets every build, not the 'base-2025' channel set above for our own package build
  $chef19_ident = Get-LatestHabPackageIdent -Origin "chef" -Name "chef-infra-client" -Channel "unstable" -MajorVersion "19"
  Write-Output "Resolved latest Chef-19 Habitat package: $chef19_ident"
  hab pkg install $chef19_ident --channel unstable
  if (-not $?) { throw "unable to install $chef19_ident" }
  Write-Output "`r"

  Install-BuiltGemIntoHabitatChef -ChefPkgIdent $chef19_ident -BuiltGem $built_gem
  $env:CHEF_POWERSHELL_EXPECTED_GEM_DIR = $script:installed_gem_dir

  Invoke-ChefPowerShellIntegrationTest -Label "Chef-19 (Habitat) integration test" -Invocation {
    hab pkg exec $chef19_ident ruby $integration_test_script
  }
}
else {
  throw "Unrecognized Ruby version '$ruby_version' - no Chef integration test mapping for it"
}
Write-Output "`r"

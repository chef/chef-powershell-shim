## prep habitat for building chef-powershell gem

$ErrorActionPreference = "Stop"

$project_name = "chef-powershell"

Write-Output "--- Cleaning up old Hab directories for a minty fresh build experience"
# Is there a c:\hab directory? If so, nuke it.
if (Test-Path -Path c:\hab) {
    Remove-Item -LiteralPath c:\hab -Recurse -Force #-ErrorAction SilentlyContinue
}
Write-Output "`r"

Write-Output "--- Making sure we're in the correct spot"
$project_root = (Get-ChildItem c:\ -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and $_.Name.EndsWith($("$project_name-shim")) } | Select-Object -First 1).FullName
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

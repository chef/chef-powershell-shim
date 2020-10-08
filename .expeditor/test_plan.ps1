param (
    [Parameter(Mandatory=$true,
    HelpMessage="Provide the name of the plan to verify.")]
    [ValidateNotNullorEmpty()]
    [string]$Plan
)

$env:HAB_ORIGIN = 'ci'

Write-Host "--- :8ball: :windows: Verifying $Plan"

Write-Host "Using Habitat version $(hab --version)"

if (Test-Path -PathType leaf "/hab/cache/keys/ci-*.sig.key") {
    Write-Host "--- :key: Using existing fake '$env:HAB_ORIGIN' origin key"
} else {
    Write-Host "--- :key: Generating fake '$env:HAB_ORIGIN' origin key"
    hab origin key generate $env:HAB_ORIGIN
}

Write-Host "--- :construction: Building $Plan"
hab pkg build $Plan
if (-not $?) { throw "unable to build" }

. results/last_build.ps1
if (-not $?) { throw "unable to determine details about this build"}

Write-Host "--- :hammer_and_wrench: Installing $pkg_ident"
hab pkg install results/$pkg_artifact
if (-not $?) { throw "unable to install this build"}

if(Test-Path "./${Plan}/tests/test.ps1") {
  Write-Host "--- :mag_right: Testing $Plan"
  powershell -File "./${Plan}/tests/test.ps1" -PackageIdentifier $pkg_ident
}

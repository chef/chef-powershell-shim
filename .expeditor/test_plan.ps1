param (
    [Parameter(Mandatory=$true,
    HelpMessage="Provide the name of the plan to verify.")]
    [ValidateNotNullorEmpty()]
    [string]$Plan
)

$env:HAB_LICENSE = "accept-no-persist"
$env:HAB_BLDR_CHANNEL = 'base-2025'
$env:HAB_REFRESH_CHANNEL = 'base-2025'

Write-Host "--- :8ball: :windows: Verifying $Plan"

Write-Host "Using Habitat version $(hab --version)"

# Set HAB_ORIGIN after Habitat installation
Write-Host "HAB_ORIGIN set to 'ci' after installation."
$env:HAB_ORIGIN = 'ci'

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
  hab studio run "$plan\tests\test.ps1 $pkg_ident; exit `$LASTEXITCODE"
}

Exit $LASTEXITCODE

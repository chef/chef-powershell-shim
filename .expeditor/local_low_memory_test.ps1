#!/usr/bin/env powershell

#Requires -Version 5

<#
.SYNOPSIS
  Runs chef-powershell/memory_pressure_test.rb inside a memory-constrained Windows
  container, using the DLLs produced by a local .expeditor/build_gems.ps1 run (see
  local_build_gems.ps1), to guard against a regression of the heap-lifetime bug fixed
  in PRs #187, #196, #205 (result payloads getting corrupted/lost on the way back from
  the native wrapper to Ruby, particularly under memory pressure).

.DESCRIPTION
  1. Requires that chef-powershell/bin/ruby_bin_folder/<ARCH> already contains freshly
     built DLLs (i.e. you've already run .\.expeditor\local_build_gems.ps1, or copied a
     built Habitat package's bin/ over that folder yourself).
  2. Reuses the same minimal Windows Server 2022 Core + Ruby/Git/vcredist image that
     local_build_gems.ps1 builds (docker/windows2022-core/Dockerfile) -- no Habitat/
     Chef-Client/Node install is needed just to run this Ruby-only test.
  3. Runs that image as a *memory-limited* container (-MemoryLimit, default 512MB)
     with the repo mounted read-only at C:\workdir, and executes
     chef-powershell/memory_pressure_test.rb inside it. The script itself additionally
     forces Ruby-side GC churn (GC.stress + large discarded allocations) so both the
     Ruby heap and, via reduced available system memory, the CLR heap the native
     wrapper allocates from are put under realistic pressure.
  4. Surfaces the container's exit code as this script's exit code/throw, so it can be
     wired into CI the same way build_gems.ps1's other verification steps are.

.PARAMETER MemoryLimit
  Docker `--memory` limit to apply to the test container, e.g. "384m" or "512m". Low
  enough to force frequent GC on both the Ruby and CLR sides without being so low the
  container fails to start PowerShell/.NET at all -- 256m was observed to reliably
  OutOfMemoryException before a runspace could even come up (System.Management.
  Automation itself needs real headroom), so 512m is the default floor.

.PARAMETER ImageTag
  Tag of the Windows Server 2022 Core build image to (re)use. Defaults to the same tag
  local_build_gems.ps1 builds, so a prior local build run's image is reused as-is.

.PARAMETER Isolation
  Container isolation mode to use ("process" or "hyperv"). Defaults to "hyperv" for
  broader host/image version compatibility -- see local_build_gems.ps1.

.PARAMETER SkipImageBuild
  Skips (re)building the Docker image and just runs -ImageTag as-is.

.PARAMETER Iterations
  Number of stress-test iterations to run inside the container (each iteration
  round-trips the full payload matrix through both interpreters). Defaults to 40.

.EXAMPLE
  .\.expeditor\build_gems.ps1        # or local_build_gems.ps1, to produce fresh DLLs
  .\.expeditor\local_low_memory_test.ps1

.EXAMPLE
  .\.expeditor\local_low_memory_test.ps1 -MemoryLimit 128m -Iterations 100
#>

[CmdletBinding()]
param(
    [Parameter()] [string] $MemoryLimit = '512m',
    [Parameter()] [string] $ImageTag = 'chef-powershell-shim/windows2022-core:latest',
    [Parameter()] [ValidateSet('process', 'hyperv')] [string] $Isolation = 'hyperv',
    [Parameter()] [switch] $SkipImageBuild,
    [Parameter()] [int] $Iterations = 40
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string] $Message)
    Write-Output "--- :petri_dish: $Message"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI not found. Install Docker Desktop (with Windows container support) and retry.'
}

$dockerOsType = (docker info --format '{{.OSType}}' 2>$null)
if ($dockerOsType -ne 'windows') {
    throw "Docker is currently configured for '$dockerOsType' containers. Switch Docker Desktop to Windows containers and retry."
}

Write-Step 'Resolving project root'
$projectRoot = "$(git rev-parse --show-toplevel)"
if (-not $projectRoot) {
    throw 'Unable to resolve the git project root. Run this script from within the chef-powershell-shim repo.'
}
$projectRoot = (Resolve-Path $projectRoot).Path
Write-Output "Project root: $projectRoot"
Write-Output "`r"

$arch = if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { 'AMD64' }
$binDir = Join-Path $projectRoot "chef-powershell\bin\ruby_bin_folder\$arch"
$wrapperDll = Join-Path $binDir 'Chef.PowerShell.Wrapper.dll'
if (-not (Test-Path -Path $wrapperDll -PathType Leaf)) {
    throw (
        "No locally built DLLs found at '$binDir'. Run '.\.expeditor\local_build_gems.ps1' " +
        "(or '.\.expeditor\build_gems.ps1' directly) first to produce the DLLs this test " +
        'exercises -- this script intentionally does not build them itself.'
    )
}
Write-Output "Using locally built DLLs from: $binDir"
Write-Output "`r"

$dockerfilePath = Join-Path $projectRoot 'docker\windows2022-core\Dockerfile'
if (-not (Test-Path -Path $dockerfilePath -PathType Leaf)) {
    throw "Dockerfile not found at '$dockerfilePath'"
}

if (-not $SkipImageBuild) {
    Write-Step "Building/reusing the Windows Server 2022 Core test image ($ImageTag)"
    & docker build --file $dockerfilePath --tag $ImageTag --isolation $Isolation (Split-Path -Path $dockerfilePath -Parent)
    if ($LASTEXITCODE -ne 0) {
        throw "Docker image build failed with exit code $LASTEXITCODE"
    }
    Write-Output "`r"
}
else {
    Write-Step "Skipping image build, reusing existing image ($ImageTag)"
    Write-Output "`r"
}

Write-Step "Running memory_pressure_test.rb in a $MemoryLimit-limited container (isolation: $Isolation)"
$dockerRunArgs = @(
    'run',
    '--rm',
    '--isolation', $Isolation,
    '--memory', $MemoryLimit,
    '--volume', "${projectRoot}:C:\workdir:ro",
    '--workdir', 'C:\workdir\chef-powershell',
    $ImageTag,
    'ruby', 'memory_pressure_test.rb', "$Iterations"
)

& docker @dockerRunArgs
$testExitCode = $LASTEXITCODE

Write-Output "`r"
if ($testExitCode -ne 0) {
    throw "memory_pressure_test.rb failed inside the $MemoryLimit-limited container (exit code $testExitCode) -- possible regression of the PR #187/#196/#205 heap-lifetime bug."
}

Write-Output "--- :white_check_mark: All payload round-trips survived $MemoryLimit-limited-memory GC pressure intact."

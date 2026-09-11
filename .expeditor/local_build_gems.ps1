#!/usr/bin/env powershell

#Requires -Version 5

<#
.SYNOPSIS
  Reproduces the ".expeditor/build_gems.ps1" Buildkite build locally by
  spinning up a disposable Windows Server 2022 Core container and running
  the build inside it, instead of on your workstation directly.

.DESCRIPTION
  1. Builds (or reuses) a Windows Server 2022 Core-based Docker image
     (docker/windows2022-core/Dockerfile) containing just Ruby, Git, and
     Chocolatey - the same baseline the Buildkite `rubydistros/windows-*`
     agents provide. Everything else (Habitat, Chef-Client, Node.js, etc.)
     is installed by build_gems.ps1 itself at build time, exactly like CI.
  2. Runs that image as a container with two volumes mounted:
       - the repository root, read-write, at C:\workdir
       - -OutputPath (created if needed), at C:\output
  3. Executes .expeditor\build_gems.ps1 inside the container.
  4. Copies the resulting Habitat artifacts and gem/DLL output out of the
     container's C:\workdir into C:\output (i.e. -OutputPath on the host),
     so build artifacts are easy to find without digging through the repo
     working tree or a since-removed container.

.PARAMETER OutputPath
  Host directory to mount as the container's build output location. Created
  if it doesn't already exist. Defaults to ".\build-output" under the repo.

.PARAMETER RubyVersion
  Major.minor Ruby version to install in the image (e.g. "3.4" or "3.1"),
  matching one of the Ruby lines build_gems.ps1 is verified against in
  .expeditor/verify.pipeline.yml. Resolved to the newest matching Chocolatey
  "ruby" package version at image build time.

.PARAMETER ImageTag
  Tag to build/reuse for the Windows Server 2022 Core build image.

.PARAMETER NoCache
  Forces a full rebuild of the Docker image instead of using layer cache.

.PARAMETER Isolation
  Container isolation mode to use ("process" or "hyperv"). "process" only
  works when the container base image version matches the host OS build
  exactly, so it defaults to "hyperv" for broader compatibility.

.PARAMETER SkipImageBuild
  Skips (re)building the Docker image and just runs -ImageTag as-is. Useful
  once you already have an image built and are iterating on build_gems.ps1.

.PARAMETER HabAuthToken
  Habitat Builder personal access token, forwarded into the container as
  HAB_AUTH_TOKEN. Required because `hab pkg build` needs to install
  chef/hab-studio (and this project's Habitat build dependencies) from
  Habitat Builder, which returns 401 Unauthorized for the 'chef' origin's
  packages without a valid token. Defaults to $env:HAB_AUTH_TOKEN if set;
  generate one at https://bldr.habitat.sh/#/profile if you don't have one.

.EXAMPLE
  .\.expeditor\local_build_gems.ps1

.EXAMPLE
  .\.expeditor\local_build_gems.ps1 -OutputPath C:\chef-powershell-shim-output -RubyVersion 3.1
#>

[CmdletBinding()]
param(
    [Parameter()] [string] $OutputPath,
    [Parameter()] [string] $RubyVersion = '3.4',
    [Parameter()] [string] $ImageTag = 'chef-powershell-shim/windows2022-core:latest',
    [Parameter()] [switch] $NoCache,
    [Parameter()] [ValidateSet('process', 'hyperv')] [string] $Isolation = 'hyperv',
    [Parameter()] [switch] $SkipImageBuild,
    [Parameter()] [string] $HabAuthToken = $env:HAB_AUTH_TOKEN
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string] $Message)
    Write-Output "--- :whale: $Message"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI not found. Install Docker Desktop (with Windows container support) and retry.'
}

$dockerOsType = (docker info --format '{{.OSType}}' 2>$null)
if ($dockerOsType -ne 'windows') {
    throw "Docker is currently configured for '$dockerOsType' containers. Switch Docker Desktop to Windows containers and retry."
}

if ([string]::IsNullOrWhiteSpace($HabAuthToken)) {
    Write-Warning (
        "HAB_AUTH_TOKEN is not set. 'hab pkg build' needs it to install chef/hab-studio and " +
        "this project's Habitat build dependencies, and will fail with '401 Unauthorized' " +
        "without it. Set `$env:HAB_AUTH_TOKEN or pass -HabAuthToken before retrying " +
        '(see https://bldr.habitat.sh/#/profile to generate a token).'
    )
}

Write-Step 'Resolving project root'
$projectRoot = "$(git rev-parse --show-toplevel)"
if (-not $projectRoot) {
    throw 'Unable to resolve the git project root. Run this script from within the chef-powershell-shim repo.'
}
$projectRoot = (Resolve-Path $projectRoot).Path
Write-Output "Project root: $projectRoot"
Write-Output "`r"

if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot 'build-output'
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$OutputPath = (Resolve-Path $OutputPath).Path
Write-Output "Output directory (mounted at C:\output in the container): $OutputPath"
Write-Output "`r"

$dockerfilePath = Join-Path $projectRoot 'docker\windows2022-core\Dockerfile'
if (-not (Test-Path -Path $dockerfilePath -PathType Leaf)) {
    throw "Dockerfile not found at '$dockerfilePath'"
}

if (-not $SkipImageBuild) {
    Write-Step "Building the Windows Server 2022 Core build image ($ImageTag)"
    $buildArgs = @(
        'build',
        '--file', $dockerfilePath,
        '--tag', $ImageTag,
        '--build-arg', "RUBY_VERSION=$RubyVersion",
        '--isolation', $Isolation
    )
    if ($NoCache) {
        $buildArgs += '--no-cache'
    }
    $buildArgs += (Split-Path -Path $dockerfilePath -Parent)

    & docker @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Docker image build failed with exit code $LASTEXITCODE"
    }
    Write-Output "`r"
}
else {
    Write-Step "Skipping image build, reusing existing image ($ImageTag)"
    Write-Output "`r"
}

# The bulk of the actual build work (installing Habitat/Chef-Client/Node,
# building the Habitat package, building the gem) is delegated to
# build_gems.ps1 itself so this container reproduces CI exactly. After it
# completes (or fails), copy whatever build artifacts exist into C:\output
# so a failed run still leaves useful output/logs behind for inspection.
$containerCommand = @'
$ErrorActionPreference = "Continue"
Set-Location C:\workdir

$buildFailed = $false
try {
    powershell -ExecutionPolicy Bypass -File .expeditor\build_gems.ps1
    if ($LASTEXITCODE -ne 0) { throw "build_gems.ps1 exited with code $LASTEXITCODE" }
} catch {
    Write-Warning "build_gems.ps1 failed: $_"
    $buildFailed = $true
}

Write-Output "--- :outbox_tray: Copying build artifacts to C:\output"
New-Item -ItemType Directory -Path C:\output -Force | Out-Null

if (Test-Path C:\workdir\results) {
    Copy-Item C:\workdir\results C:\output\results -Recurse -Force
}

$gemFiles = Get-ChildItem -Path C:\workdir\chef-powershell\*.gem -ErrorAction SilentlyContinue
if ($gemFiles) {
    New-Item -ItemType Directory -Path C:\output\gem -Force | Out-Null
    Copy-Item $gemFiles.FullName -Destination C:\output\gem -Force
}

$binFolder = "C:\workdir\chef-powershell\bin\ruby_bin_folder"
if (Test-Path $binFolder) {
    Copy-Item $binFolder C:\output\ruby_bin_folder -Recurse -Force
}

if ($buildFailed) { exit 1 } else { exit 0 }
'@

Write-Step 'Running build_gems.ps1 inside the container'
$dockerRunArgs = @(
    'run',
    '--rm',
    '--isolation', $Isolation,
    '--volume', "${projectRoot}:C:\workdir",
    '--volume', "${OutputPath}:C:\output",
    '--workdir', 'C:\workdir'
)

if (-not [string]::IsNullOrWhiteSpace($HabAuthToken)) {
    $dockerRunArgs += '-e'
    $dockerRunArgs += "HAB_AUTH_TOKEN=$HabAuthToken"
}

foreach ($envVar in @('GEM_HOST_API_KEY', 'CHEF_POWERSHELL_VERSION_UPDATE')) {
    $value = [Environment]::GetEnvironmentVariable($envVar, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        $dockerRunArgs += '-e'
        $dockerRunArgs += "$envVar=$value"
    }
}

$dockerRunArgs += $ImageTag
$dockerRunArgs += @('powershell', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-Command', $containerCommand)

& docker @dockerRunArgs
$buildExitCode = $LASTEXITCODE

Write-Output "`r"
if ($buildExitCode -ne 0) {
    Write-Output "--- :x: Build failed (exit code $buildExitCode). Partial artifacts, if any, are available under: $OutputPath"
    throw "local build_gems.ps1 run failed with exit code $buildExitCode"
}

Write-Output "--- :white_check_mark: Build complete. Artifacts available under: $OutputPath"

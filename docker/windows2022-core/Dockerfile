# escape=`
#
# Windows Server 2022 Core build environment for chef-powershell-shim.
#
# This image intentionally stays minimal: `.expeditor\build_gems.ps1` itself
# installs Habitat, Chef-Client, Node.js, etc. at build time (exactly like the
# Buildkite CI agents do), so this Dockerfile only needs to provide the base
# OS plus the handful of things CI gets "for free" from the `rubydistros`
# image it runs on: Ruby, Git, and Chocolatey (used by build_gems.ps1 to
# install everything else).
#
# RUBY_VERSION is a major.minor prefix (e.g. "3.4" or "3.1"), matching the
# Ruby lines .expeditor/verify.pipeline.yml is tested against. Chocolatey's
# "ruby" package versions are suffixed with an extra packaging revision
# (e.g. "3.4.10.1") that changes over time, so it's resolved to the newest
# matching package version at build time rather than hardcoded here.
ARG RUBY_VERSION=3.4

FROM mcr.microsoft.com/windows/servercore:ltsc2022

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Chocolatey - used by build_gems.ps1 to install Habitat/Chef-Client/Node.js,
# and used here to install Ruby and Git.
RUN Set-ExecutionPolicy Bypass -Scope Process -Force ; `
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 ; `
    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

RUN choco feature enable -n allowGlobalConfirmation

# Installs Git plus a Chocolatey "ruby" package resolved from RUBY_VERSION.
# Kept as an external script (rather than an inline RUN one-liner) to avoid
# Dockerfile/PowerShell quoting collisions - see Install-Ruby.ps1 for why.
ARG RUBY_VERSION
COPY Install-Ruby.ps1 C:\Install-Ruby.ps1
RUN powershell -ExecutionPolicy Bypass -File C:\Install-Ruby.ps1 -RubyVersion $env:RUBY_VERSION

# Pick up choco/ruby/git on PATH for subsequent RUN/ENTRYPOINT steps.
RUN Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1 ; `
    Update-SessionEnvironment ; `
    ruby --version ; `
    git --version

ENV HAB_LICENSE=accept-no-persist
ENV FORCE_FFI_YAJL=ext

WORKDIR C:/workdir

ENTRYPOINT ["powershell.exe", "-NoLogo", "-ExecutionPolicy", "Bypass"]

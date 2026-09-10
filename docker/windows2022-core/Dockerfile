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
ARG RUBY_VERSION=3.4.8

FROM mcr.microsoft.com/windows/servercore:ltsc2022

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Chocolatey - used by build_gems.ps1 to install Habitat/Chef-Client/Node.js,
# and used here to install Ruby and Git.
RUN Set-ExecutionPolicy Bypass -Scope Process -Force ; `
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 ; `
    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

RUN choco feature enable -n allowGlobalConfirmation

ARG RUBY_VERSION
RUN choco install git --no-progress ; `
    choco install ruby --version=$env:RUBY_VERSION --no-progress

# Pick up choco/ruby/git on PATH for subsequent RUN/ENTRYPOINT steps.
RUN Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1 ; `
    Update-SessionEnvironment ; `
    ruby --version ; `
    git --version

ENV HAB_LICENSE=accept-no-persist
ENV FORCE_FFI_YAJL=ext

WORKDIR C:/workdir

ENTRYPOINT ["powershell.exe", "-NoLogo", "-ExecutionPolicy", "Bypass"]

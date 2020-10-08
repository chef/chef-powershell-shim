$pkg_name="dotnet-core-sdk-x86"
$pkg_origin="chef"
$pkg_version="3.1.100"
$pkg_license=('MIT')
$pkg_upstream_url="https://www.microsoft.com/net/core"
$pkg_description=".NET Core is a blazing fast, lightweight and modular platform
  for creating web applications and services that run on Windows,
  Linux and Mac."
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_source="https://download.visualstudio.microsoft.com/download/pr/8961027c-fc5b-40d8-9f67-b08c55510ef4/99c6723fb3916369d4bb425fa70d691e/dotnet-sdk-3.1.100-win-x86.zip"
$pkg_shasum="209e07a37c1049ba8652d6896a676f7fd7339f54a9928bb08ae448a065d65b38"
$pkg_bin_dirs=@("bin")

function Invoke-Install {
    Copy-Item * "$pkg_prefix/bin" -Recurse -Force
}

function Invoke-Check() {
    mkdir dotnet-new
    Push-Location dotnet-new
    ../dotnet.exe new web
    if(!(Test-Path "program.cs")) {
        Pop-Location
        Write-Error "dotnet app was not generated"
    }
    Pop-Location
    Remove-Item -Recurse -Force dotnet-new
}

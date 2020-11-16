$pkg_name="dotnet-5-sdk-x86"
$pkg_origin="chef"
$pkg_version="5.0.100"
$pkg_license=('MIT')
$pkg_upstream_url="https://dotnet.microsoft.com/"
$pkg_description=".NET is a free, cross-platform, open-source developer platform for building many different types of applications."
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_source="https://dotnetcli.azureedge.net/dotnet/Sdk/$pkg_version/dotnet-sdk-$pkg_version-win-x86.zip"
$pkg_shasum="3ce63836d27f1799d17cbef947ef24fcfe68264be5e1eb6b0ada2c7931d20f3a"
$pkg_bin_dirs=@("bin")

function Invoke-SetupEnvironment {
    Set-RuntimeEnv -IsPath "MSBuildSDKsPath" "$pkg_prefix\bin\sdk\$pkg_version\Sdks"
}

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

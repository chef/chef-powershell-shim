$pkg_name="windows-10-sdk-x86"
$pkg_origin="chef"
$pkg_version="10.0.17763"
$pkg_description="The Windows 10 SDK for Windows 10, version 1809 (servicing release 10.0.17763.132) provides the latest headers, libraries, metadata, and tools for building Windows 10 apps"
$pkg_upstream_url="https://developer.microsoft.com/en-us/windows/downloads/windows-10-sdk"
$pkg_license=@("Microsoft Software License")
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_source="https://download.microsoft.com/download/5/C/3/5C3770A3-12B4-4DB4-BAE7-99C624EB32AD/windowssdk/winsdksetup.exe"
$pkg_shasum="bbd1c41f9ebf518e4482c5c85a0de9ad7a72b596112c392911ef6054cb5d70d7"
$pkg_build_deps=@("core/lessmsi")

$pkg_bin_dirs=@(
    "Windows Kits\10\bin\x86",
    "Windows Kits\10\bin\10.0.17763.0\x86"
)
$pkg_lib_dirs=@(
    "Windows Kits\10\Lib\10.0.17763.0\um\x86",
    "Windows Kits\10\Lib\10.0.17763.0\ucrt\x86"
)
$pkg_include_dirs=@(
    "Windows Kits\10\Include\10.0.17763.0\shared",
    "Windows Kits\10\Include\10.0.17763.0\ucrt",
    "Windows Kits\10\Include\10.0.17763.0\um",
    "Windows Kits\10\Include\10.0.17763.0\winrt"
)

function Invoke-SetupEnvironment {
    Set-RuntimeEnv -IsPath "WindowsSdkDir_10" "$pkg_prefix\Windows Kits\10"
}

function Invoke-Unpack {
    Start-Process "$HAB_CACHE_SRC_PATH/$pkg_filename" -Wait -ArgumentList "/features OptionId.DesktopCPPx86 /quiet /layout $HAB_CACHE_SRC_PATH/$pkg_dirname"
    Push-Location "$HAB_CACHE_SRC_PATH/$pkg_dirname"
    try {
        Get-ChildItem "$HAB_CACHE_SRC_PATH/$pkg_dirname/installers" -Include *.msi -Recurse | ForEach-Object {
            lessmsi x $_
        }
    } finally { Pop-Location }
    Get-ChildItem "$HAB_CACHE_SRC_PATH/$pkg_dirname" -Include @("x64", "arm", "arm64") -Recurse | ForEach-Object {
        Remove-Item $_ -Recurse -Force
    }
}

function Invoke-Install {
    Get-ChildItem "$HAB_CACHE_SRC_PATH/$pkg_dirname" -Include "Windows Kits" -Recurse | ForEach-Object {
        Copy-Item $_ "$pkg_prefix" -Exclude "*.duplicate*" -Recurse -Force
    }
}

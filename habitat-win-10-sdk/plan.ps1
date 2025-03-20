$pkg_name="windows-10-sdk"
$pkg_origin="core"
$pkg_version="10.0.26100.0"
$pkg_description="The Windows App SDK provides a unified set of APIs and tools that are decoupled from the OS and released to developers via NuGet packages. These APIs and tools can be used in a consistent way by any desktop app on Windows 11 and downlevel to Windows 10, version 1809"
$pkg_upstream_url="https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/"
$pkg_license=@("Microsoft Software License")
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_source="https://go.microsoft.com/fwlink/?linkid=2272610"
$pkg_filename="winsdksetup.exe"
$pkg_shasum="5535188A9AEEA1CEBCBF04DE3C2C37D76F10600A65867FF65F6153D507B60488"
$pkg_build_deps=@("core/lessmsi")

$pkg_bin_dirs=@(
    "Windows Kits\10\bin\x64",
    "Windows Kits\10\bin\10.0.26100.0\x64"
)
$pkg_lib_dirs=@(
    "Windows Kits\10\Lib\10.0.26100.0\um\x64",
    "Windows Kits\10\Lib\10.0.26100.0\ucrt\x64"
)
$pkg_include_dirs=@(
    "Windows Kits\10\Include\10.0.26100.0\shared",
    "Windows Kits\10\Include\10.0.26100.0\ucrt",
    "Windows Kits\10\Include\10.0.26100.0\um",
    "Windows Kits\10\Include\10.0.26100.0\winrt"
)

function Invoke-SetupEnvironment {
    Set-RuntimeEnv -IsPath "WindowsSdkDir_10" "$pkg_prefix\Windows Kits\10"
}

function Invoke-Unpack {
    Start-Process "$HAB_CACHE_SRC_PATH/$pkg_filename" -Wait -ArgumentList "/features OptionId.DesktopCPPx64 /quiet /layout $HAB_CACHE_SRC_PATH/$pkg_dirname"
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

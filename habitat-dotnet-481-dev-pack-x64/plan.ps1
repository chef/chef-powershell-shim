$pkg_name="dotnet-481-dev-pack-x64"
$pkg_origin="chef"
$pkg_version="0.1.0"
$pkg_description=".net framework 4.8.1 with dev pack"
$pkg_upstream_url="https://www.microsoft.com/net/download/all"
$pkg_license=@("Microsoft Software License")
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_source="https://go.microsoft.com/fwlink/?linkid=2203306"
$pkg_filename="NDP481-DevPack-ENU.exe"
$pkg_shasum="fd9ae4b63cbc8f7637249c4b29d25281b1f70fbe6d650109dcbf2bdf596cf994"
$pkg_build_deps=@("core/lessmsi")
$pkg_bin_dirs=@("Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8.1 Tools\x64")
$pkg_lib_dirs=@("Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\Lib\um\x64")
$pkg_include_dirs=@("Program Files\Windows Kits\NETFXSDK\4.8.1\Include\um")

function Invoke-SetupEnvironment {
    Set-RuntimeEnv -IsPath "TargetFrameworkRootPath" "$pkg_prefix\Program Files (x86)\Reference Assemblies\Microsoft\Framework"
}

function Invoke-Unpack {
    $x64_bin_path = "$HAB_CACHE_SRC_PATH/$pkg_dirname"
    if (-not( Test-Path -PathType Container $x64_bin_path)) {
        Write-Output "My 64-bit path was NOT found, now building here : $x64_bin_path"
        New-Item -Path $x64_bin_path -ItemType Directory -Force
      }
    Start-Process "$HAB_CACHE_SRC_PATH/$pkg_filename" -Wait -ArgumentList "/features OptionId.NetFxSoftwareDevelopmentKit /layout $HAB_CACHE_SRC_PATH/$pkg_dirname /quiet"
    Push-Location "$HAB_CACHE_SRC_PATH/$pkg_dirname"
    try {
        Get-ChildItem "*.msi" | ForEach-Object {
            lessmsi x $_
        }
    } finally { Pop-Location }
}

function Invoke-Install {
    Get-ChildItem "$HAB_CACHE_SRC_PATH/$pkg_dirname" -Include "Program Files" -Recurse | ForEach-Object {
        Copy-Item $_ "$pkg_prefix" -Recurse -Force
    }
    # Copy-Item "$HAB_CACHE_SRC_PATH/$pkg_dirname/Redistributable/4.5.50710/netfx45_dtp/SourceDir/ProgramFilesFolder/*" "$pkg_prefix/Program Files" -Recurse
}

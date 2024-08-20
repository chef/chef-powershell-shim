$pkg_name="dotnet-481-dev-pack-x64"
$pkg_origin="chef"
$pkg_version="0.1.0"
$pkg_description=".net framework 4.8.1 with dev pack"
$pkg_upstream_url="https://www.microsoft.com/net/download/all"
$pkg_license=@("Microsoft Software License")
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_source="https://dotnet.microsoft.com/en-us/download/dotnet-framework/thank-you/net481-developer-pack-offline-installer"
$pkg_shasum="56e3dc8b9013e0af1f62bc7499395726c330e35265db870f5cbd51b5ad841bb7"
$pkg_build_deps=@("core/lessmsi")
$pkg_bin_dirs=@("Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8.1 Tools\x64")
$pkg_lib_dirs=@("Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\Lib\um\x64")
$pkg_include_dirs=@("Program Files\Windows Kits\NETFXSDK\4.8.1\Include\um")

function Invoke-SetupEnvironment {
    Set-RuntimeEnv -IsPath "TargetFrameworkRootPath" "$pkg_prefix\Program Files (x86)\Reference Assemblies\Microsoft\Framework"
}

function Invoke-Unpack {
    Start-Process "$HAB_CACHE_SRC_PATH/$pkg_filename" -Wait -ArgumentList "/features OptionId.NetFxSoftwareDevelopmentKit /layout $HAB_CACHE_SRC_PATH/$pkg_dirname /quiet"
    Push-Location "$HAB_CACHE_SRC_PATH/$pkg_dirname/Redistributable/4.5.50710"
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
    Copy-Item "$HAB_CACHE_SRC_PATH/$pkg_dirname/Redistributable/4.5.50710/netfx45_dtp/SourceDir/ProgramFilesFolder/*" "$pkg_prefix/Program Files" -Recurse
}

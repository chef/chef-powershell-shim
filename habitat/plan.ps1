$pkg_name="chef-powershell-shim"
$pkg_origin="chef"
$pkg_version="0.1.0"
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_license=@("Apache-2.0")
$pkg_build_deps=@("core/nuget", "core/dotnet-45-dev-pack", "core/visual-cpp-redist-2015", "core/windows-10-sdk", "core/visual-build-tools-2017")
$pkg_bin_dirs=@("bin")

function Invoke-SetupEnvironment {
  Push-RuntimeEnv -IsPath "RUBY_DLL_PATH" "$pkg_prefix/bin"
  Set-RuntimeEnv -IsPath "CHEF_POWERSHELL_BIN" "$pkg_prefix/bin"
}

function Invoke-Build {
  Copy-Item $PLAN_CONTEXT/../* $HAB_CACHE_SRC_PATH/$pkg_dirname -recurse -force
  nuget restore $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell/packages.config -PackagesDirectory $HAB_CACHE_SRC_PATH/$pkg_dirname/packages -Source "https://www.nuget.org/api/v2"
  $env:TargetFrameworkRootPath="$(Get-HabPackagePath dotnet-45-dev-pack)\Program Files\Reference Assemblies\Microsoft\Framework"
  $env:WindowsSdkDir_10="$(Get-HabPackagePath windows-10-sdk)\Windows Kits\10"
  $env:DisableRegistryUse="true"
  $env:UseEnv="true"
  $env:LIBPATH = "$HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell/bin/release"
  MSBuild $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper/Chef.Powershell.Wrapper.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64
  if($LASTEXITCODE -ne 0) {
    Write-Error "dotnet build failed!"
  }
}

function Invoke-Install {
  Copy-Item $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper/x64/release/*.dll "$pkg_prefix/bin"
  Copy-Item "$(Get-HabPackagePath visual-cpp-redist-2015)\bin\msvcp140.dll" "$pkg_prefix/bin"
  Copy-Item "$(Get-HabPackagePath visual-cpp-redist-2015)\bin\vcruntime140.dll" "$pkg_prefix/bin"
}

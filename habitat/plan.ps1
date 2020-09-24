$pkg_name="chef-powershell-shim"
$pkg_origin="chef"
$pkg_version="0.2.0"
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_license=@("Apache-2.0")
$pkg_build_deps=@(
  "core/nuget",
  "core/dotnet-45-dev-pack",
  "core/windows-10-sdk",
  # until the vs 2019 plan is promoted we need to fully qualify it
  "core/visual-build-tools-2019/16.7.3/20200923133724",
  "core/dotnet-core-sdk"
)
$pkg_bin_dirs=@(
  "bin",
  "bin/shared/Microsoft.NETCore.App/3.1.8"
)

function Invoke-SetupEnvironment {
  Push-RuntimeEnv -IsPath "RUBY_DLL_PATH" "$pkg_prefix/bin"
  Set-RuntimeEnv -IsPath "CHEF_POWERSHELL_BIN" "$pkg_prefix/bin"
}

function Invoke-Build {
  Copy-Item $PLAN_CONTEXT/../* $HAB_CACHE_SRC_PATH/$pkg_dirname -recurse -force
  nuget restore $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell/packages.config -PackagesDirectory $HAB_CACHE_SRC_PATH/$pkg_dirname/packages -Source "https://www.nuget.org/api/v2"
  MSBuild $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper/Chef.Powershell.Wrapper.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64
  if($LASTEXITCODE -ne 0) {
    Write-Error "dotnet build failed!"
  }

  $env:MSBuildSDKsPath="$(Get-HabPackagePath dotnet-core-sdk)\bin\sdk\3.1.100\Sdks"
  # dotnet restore --runtime win10-x64 $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Core/Chef.Powershell.Core.csproj
  MSBuild $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper.Core/Chef.Powershell.Wrapper.Core.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64 /restore
  if($LASTEXITCODE -ne 0) {
    Write-Error "dotnet core build failed!"
  }
}

function Invoke-Install {
  Copy-Item $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper/x64/release/*.dll "$pkg_prefix/bin"
  Copy-Item "$(Get-HabPackagePath visual-build-tools-2019)\Contents\VC\Redist\MSVC\14.27.29016\x64\Microsoft.VC142.CRT\*.dll" "$pkg_prefix/bin"

  dotnet publish --output $pkg_prefix/bin/shared/Microsoft.NETCore.App/3.1.8 --self-contained --configuration Release --runtime win10-x64 $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Core/Chef.Powershell.Core.csproj
  
  Copy-Item $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper.Core/x64/release/*.dll $pkg_prefix/bin/shared/Microsoft.NETCore.App/3.1.8
  Copy-Item $PLAN_CONTEXT/../Chef.PowerShell.Wrapper.Core/Chef.PowerShell.Wrapper.Core.runtimeconfig.json $pkg_prefix/bin/shared/Microsoft.NETCore.App/3.1.8/Chef.Powershell.Wrapper.Core.runtimeconfig.json
  Rename-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/3.1.8/Chef.Powershell.Core.deps.json $pkg_prefix/bin/shared/Microsoft.NETCore.App/3.1.8/Microsoft.NETCore.App.deps.json
  mkdir $pkg_prefix/bin/host/fxr/3.1.8
  Copy-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/3.1.8/hostfxr.dll $pkg_prefix/bin/host/fxr/3.1.8
}

$pkg_name="chef-powershell-shim-x86"
$pkg_origin="chef"
$pkg_version="0.2.1"
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_license=@("Apache-2.0")
$pkg_build_deps=@(
  "core/nuget",
  "chef/dotnet-45-dev-pack-x86",
  "chef/windows-10-sdk-x86",
  "chef/visual-build-tools-2019-x86",
  "chef/dotnet-5-sdk-x86"
)
$pkg_bin_dirs=@("bin")

function Invoke-SetupEnvironment {
  Push-RuntimeEnv -IsPath "RUBY_DLL_PATH" "$pkg_prefix/bin"
  Set-RuntimeEnv -IsPath "CHEF_POWERSHELL_BIN" "$pkg_prefix/bin"
}

function Invoke-Build {
  Copy-Item $PLAN_CONTEXT/../* $HAB_CACHE_SRC_PATH/$pkg_dirname -recurse -force
  nuget restore $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell/packages.config -PackagesDirectory $HAB_CACHE_SRC_PATH/$pkg_dirname/packages -Source "https://www.nuget.org/api/v2"
  MSBuild $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper/Chef.Powershell.Wrapper.vcxproj /t:Build /p:Configuration=Release /p:Platform=Win32
  if($LASTEXITCODE -ne 0) {
    Write-Error "dotnet build failed!"
  }

  MSBuild $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper.Core/Chef.Powershell.Wrapper.Core.vcxproj /t:Build /p:Configuration=Release /p:Platform=x86 /restore
  if($LASTEXITCODE -ne 0) {
    Write-Error "dotnet core build failed!"
  }
}

function Invoke-Install {
  Copy-Item $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper/release/*.dll "$pkg_prefix/bin"
  Copy-Item "$env:VCToolsInstallDir_160\x86\Microsoft.VC142.CRT\*.dll" "$pkg_prefix/bin"

  dotnet publish --output $pkg_prefix/bin/shared/Microsoft.NETCore.App/5.0.0 --self-contained --configuration Release --runtime win10-x86 $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Core/Chef.Powershell.Core.csproj
  
  Copy-Item $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper.Core/release/*.dll $pkg_prefix/bin/shared/Microsoft.NETCore.App/5.0.0
  Copy-Item $PLAN_CONTEXT/../Chef.PowerShell.Wrapper.Core/Chef.PowerShell.Wrapper.Core.runtimeconfig.json $pkg_prefix/bin/shared/Microsoft.NETCore.App/5.0.0/Chef.Powershell.Wrapper.Core.runtimeconfig.json
  Rename-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/5.0.0/Chef.Powershell.Core.deps.json $pkg_prefix/bin/shared/Microsoft.NETCore.App/5.0.0/Microsoft.NETCore.App.deps.json
  mkdir $pkg_prefix/bin/host/fxr/5.0.0
  Copy-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/5.0.0/hostfxr.dll $pkg_prefix/bin/host/fxr/5.0.0
  Copy-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/5.0.0/Ijwhost.dll $pkg_prefix/bin
}

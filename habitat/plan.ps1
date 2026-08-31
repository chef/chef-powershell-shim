$pkg_name="chef-powershell-shim"
$pkg_origin="chef"
$pkg_version=(Get-Content $PLAN_CONTEXT/../VERSION)
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_license=@("Apache-2.0")
$pkg_build_deps=@(
  "core/nuget",
  "core/dotnet-481-dev-pack",
  "core/windows-11-sdk",
  "core/visual-build-tools-2026",
  "core/dotnet-10-sdk"
)
$pkg_bin_dirs=@("bin")

$env:HAB_BLDR_CHANNEL = "base-2025"
$env:HAB_ORIGIN = "chef"
$env:HAB_REFRESH_CHANNEL = "base-2025"

function Invoke-SetupEnvironment {
  Push-RuntimeEnv -IsPath "RUBY_DLL_PATH" "$pkg_prefix/bin"
  Set-RuntimeEnv -IsPath "CHEF_POWERSHELL_BIN" "$pkg_prefix/bin"

  $sdkVersion = (Get-ChildItem "$(Get-HabPackagePath dotnet-10-sdk)\bin\Sdk" | Sort-Object Name -Descending | Select-Object -First 1).Name
  Set-RuntimeEnv -IsPath "MSBuildSDKsPath" "$(Get-HabPackagePath dotnet-10-sdk)\bin\Sdk\$sdkVersion\Sdks"
}

function Invoke-Build {
  Copy-Item $PLAN_CONTEXT/../* $HAB_CACHE_SRC_PATH/$pkg_dirname -Recurse -Force -Exclude ".vs"

  nuget restore `
    "$HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell/packages.config" `
    -PackagesDirectory "$HAB_CACHE_SRC_PATH/$pkg_dirname/packages" `
    -Source "https://www.nuget.org/api/v2"

  $vsBuildToolsPath = "$(Get-HabPackagePath visual-build-tools-2026)\Contents"
  $vcTargetsPath = "$vsBuildToolsPath\MSBuild\Microsoft\VC\v180\"
  $msbuildExe = "$vsBuildToolsPath\MSBuild\Current\Bin\amd64\MSBuild.exe"

  & $msbuildExe $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper/Chef.Powershell.Wrapper.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64
  if($LASTEXITCODE -ne 0) {
    Write-Error "dotnet build failed!"
  }

  $env:DOTNET_ROOT = "$(Get-HabPackagePath dotnet-10-sdk)\bin"

  & "$env:DOTNET_ROOT\dotnet.exe" build $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Core/Chef.Powershell.Core.csproj --configuration Release /p:Platform=x64
  if($LASTEXITCODE -ne 0) {
    Write-Error "dotnet core build failed!"
  }

  $refPackRoot = "$env:DOTNET_ROOT\packs\Microsoft.NETCore.App.Ref"
  $refVersion = (Get-ChildItem $refPackRoot | Sort-Object Name -Descending | Select-Object -First 1).Name
  $refPackPath = "$refPackRoot\$refVersion\ref\net10.0"
  $env:LIBPATH = "$refPackPath;$env:LIBPATH"

  $hostPackRoot = "$env:DOTNET_ROOT\packs\Microsoft.NETCore.App.Host.win-x64"
  $hostPackVersion = (Get-ChildItem $hostPackRoot | Sort-Object Name -Descending | Select-Object -First 1).Name
  $ijwHostSourcePath = "$hostPackRoot\$hostPackVersion\runtimes\win-x64\native\ijwhost.dll"
  & $msbuildExe $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper.Core/Chef.Powershell.Wrapper.Core.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64 /p:BuildProjectReferences=false /p:VCTargetsPath="$vcTargetsPath" /p:DotNetSdkRoot="$env:DOTNET_ROOT" /p:DotNetCoreRefPackPath="$refPackPath" /p:IjwHostSourcePath="$ijwHostSourcePath" /p:DisableImplicitFrameworkReferences=true /p:GenerateRuntimeConfigurationFiles=false /nodeReuse:false
  if($LASTEXITCODE -ne 0) {
    Write-Error "dotnet core build failed!"
  }
}

function Invoke-Install {
  $VCToolsInstallDir_180 = "$(Get-HabPackagePath visual-build-tools-2026)\Contents\VC\Redist\MSVC\14.51.36231"
  Copy-Item $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper/x64/release/*.dll "$pkg_prefix/bin"
  Copy-Item "$VCToolsInstallDir_180\x64\Microsoft.VC145.CRT\*.dll" "$pkg_prefix/bin"

  & "$(Get-HabPackagePath dotnet-10-sdk)\bin\dotnet.exe" publish --output $pkg_prefix/bin/shared/Microsoft.NETCore.App/10.0.0 --self-contained --configuration Release --runtime win-x64 $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Core/Chef.Powershell.Core.csproj

  Copy-Item $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper.Core/x64/release/*.dll $pkg_prefix/bin/shared/Microsoft.NETCore.App/10.0.0
  Copy-Item $PLAN_CONTEXT/../Chef.PowerShell.Wrapper.Core/Chef.PowerShell.Wrapper.Core.runtimeconfig.json $pkg_prefix/bin/shared/Microsoft.NETCore.App/10.0.0/Chef.Powershell.Wrapper.Core.runtimeconfig.json
  Rename-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/10.0.0/Chef.Powershell.Core.deps.json $pkg_prefix/bin/shared/Microsoft.NETCore.App/10.0.0/Microsoft.NETCore.App.deps.json
  mkdir $pkg_prefix/bin/host/fxr/10.0.0
  Copy-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/10.0.0/hostfxr.dll $pkg_prefix/bin/host/fxr/10.0.0

  # ijwhost.dll bootstraps the .NET runtime for the C++/CLI mixed-mode assembly.
  # Pull from the host pack if MSBuild didn't copy it to the publish output.
  $ijwHostInOutput = "$pkg_prefix/bin/shared/Microsoft.NETCore.App/10.0.0/ijwhost.dll"
  if (-not (Test-Path $ijwHostInOutput)) {
    $hostPackRoot = "$(Get-HabPackagePath dotnet-10-sdk)\bin\packs\Microsoft.NETCore.App.Host.win-x64"
    $hostPackVersion = (Get-ChildItem $hostPackRoot | Sort-Object Name -Descending | Select-Object -First 1).Name
    Copy-Item "$hostPackRoot\$hostPackVersion\runtimes\win-x64\native\ijwhost.dll" $ijwHostInOutput
  }
  Copy-Item $ijwHostInOutput $pkg_prefix/bin
}

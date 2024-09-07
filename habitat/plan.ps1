$pkg_name="chef-powershell-shim"
$pkg_origin="chef"
$pkg_version="0.4.0"
$pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
$pkg_license=@("Apache-2.0")
$pkg_build_deps=@(
  "core/nuget",
  "core/dotnet-481-dev-pack", #, As of August 2024, this package should be installed by default on all Windows devices.
  "core/windows-11-sdk", 
  "core/visual-build-tools-2022",
  "core/dotnet-core-sdk" # this should be pulling down the .net 8 or later sdk, not the one we have locally in this repo
)
$pkg_bin_dirs=@("bin")

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

  MSBuild $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper.Core/Chef.Powershell.Wrapper.Core.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64 /restore
  if($LASTEXITCODE -ne 0) {
    Write-Error "dotnet core build failed!"
  }
}

function Invoke-Install {
  # This blob here is admittedly insanity. We end up disconnected from the VCToolsDir but we know where it lives in relation to where we are currently.
  # This block crawls back up 3 levels to where all the tools folders live. Then traverses down 2 levels into
  # the msbuild tools so that we can finally add the correct path to the end and extract the MSVCT dll's we need. 
  # I making this way too hard. Someone throw me a bone here. 
  $basedir = (get-item $pkg_prefix).Parent.Parent.Parent.ToString()
  $temp = $($basedir + '\visual-build-tools-2022')
  $temp2 = (Get-Childitem -path $(Get-Childitem -path $temp).FullName).FullName
  $VCToolsInstallDir_170 = "$temp2\Contents\VC\Redist\MSVC\14.40.33807"
  Copy-Item $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper/x64/release/*.dll "$pkg_prefix/bin"
  Copy-Item "$VCToolsInstallDir_170\x64\Microsoft.VC143.CRT\*.dll" "$pkg_prefix/bin"

  dotnet publish --output $pkg_prefix/bin/shared/Microsoft.NETCore.App/8.0.0 --self-contained --configuration Release --runtime win-x64 $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Core/Chef.Powershell.Core.csproj

  Copy-Item $HAB_CACHE_SRC_PATH/$pkg_dirname/Chef.Powershell.Wrapper.Core/x64/release/*.dll $pkg_prefix/bin/shared/Microsoft.NETCore.App/8.0.0
  Copy-Item $PLAN_CONTEXT/../Chef.PowerShell.Wrapper.Core/Chef.PowerShell.Wrapper.Core.runtimeconfig.json $pkg_prefix/bin/shared/Microsoft.NETCore.App/8.0.0/Chef.Powershell.Wrapper.Core.runtimeconfig.json
  Rename-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/8.0.0/Chef.Powershell.Core.deps.json $pkg_prefix/bin/shared/Microsoft.NETCore.App/8.0.0/Microsoft.NETCore.App.deps.json
  mkdir $pkg_prefix/bin/host/fxr/8.0.0
  Copy-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/8.0.0/hostfxr.dll $pkg_prefix/bin/host/fxr/8.0.0
  Copy-Item $pkg_prefix/bin/shared/Microsoft.NETCore.App/8.0.0/Ijwhost.dll $pkg_prefix/bin
}

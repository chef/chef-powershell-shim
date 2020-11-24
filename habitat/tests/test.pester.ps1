param (
    [Parameter()]
    [string]$PackageIdentifier = $(throw "Fully qualified package identifier must be given as a parameter.")
)

Describe "chef-powershell-shim" {
    Context "windows powershell" {
        It "executes the Desktop edition" {
            $jResult = Invoke-Command -ComputerName localhost -EnableNetworkAccess {
                param($bin)
                $cSharp = "[DllImport(@`"$bin\Chef.PowerShell.Wrapper.dll`")]public static extern IntPtr ExecuteScript(string script);"
                $env:CHEF_POWERSHELL_BIN = $bin
                $exec = Add-Type -MemberDefinition $cSharp -Name "ps_exec" -Namespace Chef -PassThru
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni($exec::ExecuteScript("write-output `$PSVersionTable"))
            } -ArgumentList "$(hab pkg path $env:HAB_ORIGIN/chef-powershell-shim)\bin"
            $oResult = ConvertFrom-Json (ConvertFrom-Json $jResult).Result

            $oResult.PSEdition | Should -Be "Desktop"
        }

        It "is able to load assemblies from the GAC" {
            $jResult = Invoke-Command -ComputerName localhost -EnableNetworkAccess {
                param($bin)
                $cSharp = "[DllImport(@`"$bin\Chef.PowerShell.Wrapper.dll`")]public static extern IntPtr ExecuteScript(string script);"
                $env:CHEF_POWERSHELL_BIN = $bin
                $exec = Add-Type -MemberDefinition $cSharp -Name "ps_exec" -Namespace Chef -PassThru
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni($exec::ExecuteScript("Add-Type -Assembly Microsoft.Activities.Build"))
            } -ArgumentList "$(hab pkg path $env:HAB_ORIGIN/chef-powershell-shim)\bin"

            ConvertFrom-Json (ConvertFrom-Json $jResult).Errors.Count | Should -Be 0
        }

        It "reads the verbose stream" {
            $jResult = Invoke-Command -ComputerName localhost -EnableNetworkAccess {
                param($bin)
                $cSharp = "[DllImport(@`"$bin\Chef.PowerShell.Wrapper.dll`")]public static extern IntPtr ExecuteScript(string script);"
                $env:CHEF_POWERSHELL_BIN = $bin
                $exec = Add-Type -MemberDefinition $cSharp -Name "ps_exec" -Namespace Chef -PassThru
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni($exec::ExecuteScript("`$VerbosePreference = 'Continue';Write-Verbose 'some verbose text'"))
            } -ArgumentList "$(hab pkg path $env:HAB_ORIGIN/chef-powershell-shim)\bin"

            (ConvertFrom-Json $jResult).Verbose | Should -Be "some verbose text"
        }
    }
    Context "powershell core" {
        It "executes the Core edition" {
            $jResult = Invoke-Command -ComputerName localhost -EnableNetworkAccess {
                param($bin)
                $cSharp = "[DllImport(@`"$bin\shared\Microsoft.NETCore.App\5.0.0\Chef.PowerShell.Wrapper.Core.dll`")]public static extern IntPtr ExecuteScript(string script);"
                $env:DOTNET_MULTILEVEL_LOOKUP = 0
                $env:DOTNET_ROOT = $bin
                $env:PATH += ";$bin"
                $exec = Add-Type -MemberDefinition $cSharp -Name "ps_exec" -Namespace Chef -PassThru
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni($exec::ExecuteScript("write-output `$PSVersionTable"))
            } -ArgumentList "$(hab pkg path $env:HAB_ORIGIN/chef-powershell-shim)\bin"
            $oResult = ConvertFrom-Json (ConvertFrom-Json $jResult).Result

            $oResult.PSEdition | Should -Be "Core"
        }

        It "reads the verbose stream" {
            $jResult = Invoke-Command -ComputerName localhost -EnableNetworkAccess {
                param($bin)
                $cSharp = "[DllImport(@`"$bin\shared\Microsoft.NETCore.App\5.0.0\Chef.PowerShell.Wrapper.Core.dll`")]public static extern IntPtr ExecuteScript(string script);"
                $env:DOTNET_MULTILEVEL_LOOKUP = 0
                $env:DOTNET_ROOT = $bin
                $env:PATH += ";$bin"
                $exec = Add-Type -MemberDefinition $cSharp -Name "ps_exec" -Namespace Chef -PassThru
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni($exec::ExecuteScript("`$VerbosePreference = 'Continue';Write-Verbose 'some verbose text'"))
            } -ArgumentList "$(hab pkg path $env:HAB_ORIGIN/chef-powershell-shim)\bin"

            (ConvertFrom-Json $jResult).Verbose | Should -Be "some verbose text"
        }
    }
}

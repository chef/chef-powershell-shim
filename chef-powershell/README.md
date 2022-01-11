# Chef-PowerShell gem

**Umbrella Project**: [Chef PowerShell Shim](https://github.com/chef/chef-powershell-shim/blob/main/README.md)

**Project State**: [Active](https://github.com/chef/chef-oss-practices/blob/main/repo-management/repo-states.md#active)

**Issues [Response Time Maximum](https://github.com/chef/chef-oss-practices/blob/main/repo-management/repo-states.md)**: 14 days

**Pull Request [Response Time Maximum](https://github.com/chef/chef-oss-practices/blob/main/repo-management/repo-states.md)**: 14 days

## Getting Started

The Chef-Powershell gem contains code previously included directly in the Chef Infra client to allow Chef binaries to access PowerShell and Windows PowerShell via ffi. This makes it super easy to add and execute an arbitrary block of PowerShell code. This code DOES NOT replace the PowerShell resource that your recipes normally consume. Rather, that resource relies on this tool to execute your code.

## Documentation for Cookbook library authors

None. This gem is not meant to be consumed directly by cookbooks. It can be consumed by ruby code blocks.

## Documentation for Software Developers

The Chef-PowerShell gem provides in-process access to the PowerShell engine.

`powershell_exec` is initialized with a string that should be set to the script
to run and also takes an optional interpreter argument which must be either
:powershell (Windows PowerShell which is the default) or :pwsh (PowerShell
Core). It will return a ChefPowerShell::PowerShell object that provides 5 methods:

.result - returns a hash representing the results returned by executing the
          PowerShell script block

.verbose - this is an array of string containing any messages written to the
          PowerShell verbose stream during execution

.errors - this is an array of string containing any messages written to the
          PowerShell error stream during execution

.error? - returns true if there were error messages written to the PowerShell
          error stream during execution

.error! - raise ChefPowerShell::PowerShellExceptions::PowerShellCommandFailed if there was an error

Some examples of usage:

```ruby
 > powershell_exec!("(Get-Item c:\\windows\\system32\\w32time.dll).VersionInfo"
  ).result["FileVersion"]
=> "10.0.14393.0 (rs1_release.160715-1616)"
```
```ruby
> powershell_exec("(get-process ruby).Mainmodule").result["FileName"]
=> C:\\opscode\\chef\\embedded\\bin\\ruby.exe"
```
```ruby
> powershell_exec("$a = $true; $a").result
=> true
```
```ruby
> powershell_exec("$PSVersionTable", :pwsh).result["PSEdition"]
=> "Core"
```
```ruby
> powershell_exec("$PSVersionTable", :powershell).result["PSEdition"]
=> "Desktop"
```
```ruby
> powershell_exec("not-found").errors
=> ["ObjectNotFound: (not-found:String) [], CommandNotFoundException: The
term 'not-found' is not recognized as the name of a cmdlet, function, script
file, or operable program. Check the spelling of the name, or if a path was
included, verify that the path is correct and try again. (at <ScriptBlock>,
  <No file>: line 1)"]
  ```
  ```ruby
> powershell_exec("not-found").error?
=> true
```
```ruby
> powershell_exec("get-item c:\\notfound -erroraction stop")
WIN32OLERuntimeError: (in OLE method `ExecuteScript': )
    OLE error code:80131501 in System.Management.Automation
      The running command stopped because the preference variable
      "ErrorActionPreference" or common parameter is set to Stop: Cannot find
      path 'C:\notfound' because it does not exist.
```
```ruby
require "chef-powershell"
...
include ChefPowerShell::ChefPowerShell::PowerShellExec
...
def join_command
  cmd = ""
  cmd << "$pswd = ConvertTo-SecureString \'#{new_resource.password}\' -AsPlainText -Force;" if new_resource.password
  cmd << "$credential = New-Object System.Management.Automation.PSCredential (\'#{new_resource.user}\',$pswd);" if new_resource.password
  cmd << "Add-Computer -WorkgroupName #{new_resource.workgroup_name}"
  cmd << " -Credential $credential" if new_resource.password
  cmd << " -Force"
  cmd
end
...
my_result = powershell_exec!(join_command)
```

## Getting Involved

We'd love to have your help developing Chef Infra. See our [Contributing Document](../CONTRIBUTING.md) for more information on getting started.

## License and Copyright

Copyright Chef Software, Inc.

```
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

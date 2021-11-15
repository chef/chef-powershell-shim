##############################
##
## This script will automagically bump the VERSION number of the chef-powershell gem
## If you need to explicitly set the Major, Minor, or Version then set the
## environment variable CHEF_POWERSHELL_VERSION_UPDATE to either Major, Minor or Version
##
#############################

$ErrorActionPreference = "Stop"

# get the contents of the gem version file
try {
    $project_root = Get-ChildItem -Path C:\ -Recurse | Where-Object { $_.PSIsContainer -eq $True -and $_.Name -like "*chef-powershell-shim*" }  | % { $_.fullname } | select-object -First 1
    $file = (Get-Content $("$project_root\chef-powershell\lib\chef-powershell\version.rb"))
}
catch {
    Write-Error "Failed to Get the Version from version.rb"
}

# Use RegEx to get the Version Number and set it as a version datatype
# \s* - between 0 and many whitespace
# ModuleVersion - literal
# \s - 1 whitespace
# = - literal
# \s - 1 whitespace
# ' - literal
# () - capture Group
# \d* - between 0 and many digits
# ' - literal
# \s* between 0 and many whitespace

[version]$Version = [regex]::matches($file, "\s*VERSION\s=\s\`"(\d*.\d*.\d*)\`"\s*").groups[1].value
$update_type = [System.Environment]::GetEnvironmentVariable("CHEF_POWERSHELL_VERSION_UPDATE", "Machine")

# Add one to the build of the version number
if ($update_type -eq "Major") {
    [version]$NewVersion = "{0}.{1}.{2}" -f ($Version.Major + 1), $Version.Minor, $Version.Build
}
elseif ($update_type -eq "Minor") {
    [version]$NewVersion = "{0}.{1}.{2}" -f $Version.Major, ($Version.Minor + 1), $Version.Build
}
elseif ([string]::IsNullOrEmpty($update_type) || $update_type -eq "Version") {
    [version]$NewVersion = "{0}.{1}.{2}" -f $Version.Major, $Version.Minor, ($Version.Build + 1)
}
else {
    Write-Error "failed to update the version string"
}

# Replace Old Version Number with New Version number in the file
try {
    (Get-Content .\chef-powershell\lib\chef-powershell\version.rb) -replace $version, $NewVersion | Out-File .\chef-powershell\lib\chef-powershell\version.rb
    Write-Output "Updated Module Version from $Version to $NewVersion"
}
catch {
    $_
    Write-Error "failed to set file"
}
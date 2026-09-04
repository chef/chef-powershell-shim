##############################
##
## This script will automagically bump the VERSION number of the chef-powershell gem
## If you need to explicitly set the Major, Minor, or Version then set the
## environment variable CHEF_POWERSHELL_VERSION_UPDATE to either Major, Minor or Version
##
#############################

$ErrorActionPreference = "Stop"

# Get the project root directory using git
$project_root = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to determine git repository root. Are you in a git repository?"
    exit 1
}

# Convert Unix-style path to Windows path if necessary
$project_root = $project_root -replace '/', '\'

# Get the contents of the gem version file
$version_file = Join-Path $project_root "chef-powershell\lib\chef-powershell\version.rb"
if (-not (Test-Path $version_file)) {
    Write-Error "Version file not found at: $version_file"
    exit 1
}

try {
    $file = Get-Content $version_file
}
catch {
    Write-Error "Failed to read the Version from version.rb: $_"
    exit 1
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
elseif (([string]::IsNullOrEmpty($update_type)) -or ($update_type -eq "Version")) {
    [version]$NewVersion = "{0}.{1}.{2}" -f $Version.Major, $Version.Minor, ($Version.Build + 1)
}
else {
    Write-Error "failed to update the version string"
}

# Replace Old Version Number with New Version number in the file
try {
    (Get-Content $version_file) -replace $version, $NewVersion | Set-Content $version_file -Encoding UTF8
    Write-Output "Updated Module Version from $Version to $NewVersion"
}
catch {
    Write-Error "Failed to update version file: $_"
    exit 1
}
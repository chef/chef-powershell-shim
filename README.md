# chef-powershell-shim

A .NET Assembly to facilitate communication between Chef and PowerShell on the Windows platform. This repo now also contains the chef-powershell Ruby gem which consumes the the .NET Assembly and provides the interface between Chef and PowerShell via ffi.

### Development Prerequisites

Binaries can be built with Habitat. See the PowerShell script `.\.expeditor\build_gems.ps1` to test your changes locally.

You will need to have the following things installed:
1) .net framework 4.8.1 development pack
2) Windows 11 SDK build 26100
3) .net 8.0.303. You can load that from here: https://github.com/dotnet/core/blob/main/release-notes/8.0/8.0.7/8.0.7.md
4) MS build tools 17.11.2

Then set these envuironment variables:

```
$env:MSBuildEnableWorkloadResolver = "false";
$env:HAB_BLDR_CHANNEL = "LTS-2024";
$env:MSBuildSdksPath = "C:\Program Files\dotnet\sdk";
$env:HAB_ORIGIN = "chef";
```

Finally, ensure that nuget is correctly setup by adding a repo source

```
dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org
```

### Build on merge

(Broken due to credentials for pushing gem, but also `.\.expeditor\update_version.sh` appears to be broken as well.

`workflows/gem-build.yml` should normally build on merge to `main`

### Manual build

Then run `.\.expeditor\manual_gem_release.ps1` to build the gem and push it out. Releng does not have a Windows centric
facility to build and push gems to Artifactory automatically. You will need:
1) Access to the Chef internal Artifactory repo
2) a Windows build system

## Contributing/Development

Please read our [Community Contributions Guidelines](https://docs.chef.io/community_contributions.html), and
ensure you are signing all your commits with DCO sign-off.

The general development process is:

1. Fork this repo and clone it to your workstation.
2. Create a feature branch for your change.
3. Write code and tests.
4. Push your feature branch to github and open a pull request against master.

Once your repository is set up, you can start working on the code.  We do utilize
RSpec for test driven development, so you'll need to get a development
environment running. Follow the above procedure ("Installing from Git") to get
your local copy of the source running.

# License

|                      |                                          |
|:---------------------|:-----------------------------------------|
| **Author:**          | Stuart Preston (<stuart@chef.io>)
| **Copyright:**       | Copyright 20, Chef Software, Inc.
| **License:**         | Apache License, Version 2.0

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

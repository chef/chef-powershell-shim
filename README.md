## UPDATE (November, 2026): Repository branch structure changed

We pruned this repository to simplify maintenance. **`main` is now the only active branch.** All development, pull requests, and releases target it.

- The former `18-Stable` branch was renamed `main-stale` and retired. It is kept for reference only and is not maintained.
- Any relevant changes from the retired branch were merged into `main`.
- If your fork or local clone tracks a retired branch, re-point it to `main`:
  `git fetch origin && git checkout main && git branch -u origin/main`




# chef-powershell-shim

A .NET Assembly to facilitate communication between Chef and PowerShell on the Windows platform. This repo now also contains the chef-powershell Ruby gem which consumes the the .NET Assembly and provides the interface between Chef and PowerShell via ffi.

### Which script does what

| Script | Used by | Purpose |
|---|---|---|
| `.expeditor/ci/verify_gem.ps1` | Buildkite `verify` pipeline (`.expeditor/verify.pipeline.yml`), every PR | Builds the DLLs, checks the gem, and tests this branch's chef-powershell against Chef 18 (Omnibus + Habitat) and Chef 19 (Habitat). Verification only: it publishes nothing. |
| `.expeditor/ci/local_verify_in_docker.ps1` | Developers | Runs `verify_gem.ps1` locally in a disposable Windows container. |
| `.expeditor/ci/local_low_memory_test.ps1` | Developers | Memory-pressure regression test using locally built DLLs. Not run in CI. |
| `.expeditor/scripts/gem_push_artifactory.ps1` | Buildkite `gem_validate/release` pipeline, triggered by Expeditor after a merge that bumps the version | Builds the gem and pushes it to the internal Artifactory gems repo. |
| `.expeditor/manual_gem_release.ps1` | Releng, by hand on a Windows machine | Builds the gem and publishes it to RubyGems.org. `built_in:publish_rubygems` is commented out in `.expeditor/config.yml`, so this step is manual. |

### Development Prerequisites

Binaries can be built with Habitat. See the PowerShell script `.\.expeditor\ci\verify_gem.ps1` to test your changes locally.

If you'd rather not install Habitat, Chef-Client, and the other build dependencies directly on your
workstation, `.\.expeditor\ci\local_verify_in_docker.ps1` runs the exact same `verify_gem.ps1` build inside a
disposable Windows Server 2022 Core Docker container (Docker Desktop with Windows containers enabled
is required). It mounts your repo checkout read-write into the container and copies the resulting
Habitat artifacts, built gem, and compiled DLLs out to an output directory on your host (`.\build-output`
by default):

```powershell
.\.expeditor\ci\local_verify_in_docker.ps1
# or, to control the Ruby version / output location:
.\.expeditor\ci\local_verify_in_docker.ps1 -RubyVersion 3.1 -OutputPath C:\chef-powershell-shim-output
```

You'll need a Habitat Builder personal access token for this too - `hab pkg build` installs
chef/hab-studio and this project's Habitat build dependencies from Habitat Builder, which fails
with `401 Unauthorized` without one. Generate one at https://bldr.habitat.sh/#/profile, then either
set `$env:HAB_AUTH_TOKEN`, add a `HAB_AUTH_TOKEN=...` line to `~/.env`, or pass `-HabAuthToken`.

You will need to have the following things installed:
1) .net framework 4.8.1 development pack
2) Windows 11 SDK build 26100
3) .net 8.0.303. You can load that from here: https://github.com/dotnet/core/blob/main/release-notes/8.0/8.0.7/8.0.7.md
4) MS build tools 17.11.2

Then set these envuironment variables:

```
$env:MSBuildEnableWorkloadResolver = "false";
$env:MSBuildSdksPath = "C:\Program Files\dotnet\sdk";
$env:HAB_ORIGIN = "chef";
```

Finally, ensure that nuget is correctly setup by adding a repo source

```
dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org
```

### Build on merge

(Broken due to credentials for pushing gem, but also `.\.expeditor\update_version.sh` appears to be broken as well.

`workflows/gem-build.yml` should normally build on merge to `18-Stable`

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

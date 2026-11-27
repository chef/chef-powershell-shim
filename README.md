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
| `.github/workflows/lint.yml` | GitHub Actions, every PR and push to `main`, Windows runner | Style (`rake style`) and spellcheck (`rake spellcheck`) on a plain checkout of the commit under test. Needs no DLLs, Habitat or Chef. |
| `.expeditor/ci/verify_gem.ps1` | Buildkite `verify` pipeline (`.expeditor/verify.pipeline.yml`), every PR | Builds the DLLs and the gem, runs the gem's specs (`rake spec`) against those DLLs, then installs the built gem into the newest unreleased Chef 18 (Omnibus + Habitat) and Chef 19 (Habitat) and runs `chef_gem_integration_test.rb` there. Verification only: it publishes nothing. |
| `.expeditor/ci/local_verify_in_docker.ps1` | Developers | Runs `verify_gem.ps1` locally in a disposable Windows container. |
| `.expeditor/ci/local_low_memory_test.ps1` | Developers | Memory-pressure regression test using locally built DLLs. Not run in CI. |
| `.expeditor/scripts/gem_push_artifactory.ps1` | Buildkite `gem_validate/release` pipeline, triggered by Expeditor after a merge that bumps the version | Builds the gem and pushes it to the internal Artifactory gems repo. |
| `.expeditor/manual_gem_release.ps1` | Releng, by hand on a Windows machine | Builds the gem and publishes it to RubyGems.org (see "How the gem is released today"). |

### Development Prerequisites

Binaries can be built with Habitat. Style and spellcheck are not part of that script (see `.github/workflows/lint.yml`; locally, `bundle exec rake style spellcheck` from `chef-powershell/`). See the PowerShell script `.\.expeditor\ci\verify_gem.ps1` to test your changes locally.

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
3) .NET 10 SDK
4) Visual Studio Build Tools 2026 (MSVC v180 toolset)

These match the build dependencies in `habitat/plan.ps1`, which is the source of truth.

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

### How the gem is released today

The gem contains compiled DLLs, so it can only be built on Windows. This is read from the repo configuration; it
has not been re-run end to end.

1. **PR validation (every PR):** two independent checks, neither of which publishes anything.
   - GitHub Actions `Lint and spellcheck` (`.github/workflows/lint.yml`) runs style and spellcheck on the commit under test.
   - The Buildkite `verify` pipeline runs `.expeditor/ci/verify_gem.ps1`: build the DLLs with Habitat, run the gem's
     specs against them, `gem build` the gem the way a release does, then install that built gem into the newest
     unreleased Chef 18 (Omnibus from the `current` channel, Habitat from `unstable`) and Chef 19 (Habitat from
     `unstable`) and run `chef_gem_integration_test.rb` inside each. That test fails unless the Chef under test
     activated exactly the gem that was built.
2. **On merge to `main` (automatic, Expeditor, see `.expeditor/config.yml`):**
   - bumps the version in the `VERSION` file (patch by default; use the `Expeditor: Bump Version Minor/Major`
     labels for larger bumps, or `Expeditor: Skip Version Bump` to skip),
   - runs `.expeditor/update_version.sh`, which copies `VERSION` into `chef-powershell/lib/chef-powershell/version.rb`
     and runs `bundle update chef-powershell --conservative`,
   - updates the changelog, tags the release, and triggers the `habitat/build` and `gem_validate/release` pipelines.
3. **`gem_validate/release` (Buildkite, `.expeditor/gem_release.pipeline.yml`):** runs
   `.expeditor/scripts/gem_push_artifactory.ps1`, which builds the DLLs with Habitat, builds the gem and pushes it to
   the internal Artifactory gems repo. The Artifactory host and repo name in that script still carry a
   `TODO: confirm` comment.
4. **Publishing to RubyGems.org is manual.** The Expeditor `built_in:publish_rubygems` action is commented out in
   `.expeditor/config.yml`. Someone with RubyGems.org access publishes the merged version using either:
   - `.\.expeditor\manual_gem_release.ps1` on a Windows machine (builds the DLLs and gem, then runs `gem push` to
     RubyGems.org), or
   - the `Manually triggered workflow` GitHub Action (`.github/workflows/manual-gem-build.yml`, `workflow_dispatch`),
     which pushes with the `GEM_HOST_API_KEY` repository secret.

`.github/workflows/gem-build.yml` only runs when a merged PR targeting the retired `18-Stable` branch is labelled
`build and release`, so it no longer triggers. `.github/workflows/tester.yml` is a manual test workflow.

## Contributing/Development

Please read our [Community Contributions Guidelines](https://docs.chef.io/community_contributions.html), and
ensure you are signing all your commits with DCO sign-off.

The general development process is:

1. Fork this repo and clone it to your workstation.
2. Create a feature branch for your change.
3. Write code and tests.
4. Push your feature branch to github and open a pull request against `main`.

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

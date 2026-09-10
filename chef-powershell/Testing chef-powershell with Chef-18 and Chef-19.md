# Testing chef-powershell with Chef-18 and Chef-19


**This is now automated.** `.expeditor/build_gems.ps1` runs this exact flow (both Chef-18 formats
and Chef-19) as part of CI, using `chef_gem_integration_test.rb` (same directory as this doc) as
the shared assertions (Part 5 below). If you're testing manually, treat that script as the source
of truth for exact commands — this guide explains the *why* behind each step and gives you
copy/pasteable pieces to run interactively.

---

## Background: how chef-powershell fits into Chef

Both Chef-18 and Chef-19 consume `chef-powershell` **as a plain bundled RubyGem**. The gem ships
its own native DLLs inside `bin/ruby_bin_folder/<ARCH>/`. Neither chef version relies on Habitat
auto-injecting `CHEF_POWERSHELL_BIN` from the shim package; that mechanism was removed in
chef/chef PR #15594 (main) / #16092 (chef-18). This means:

- The DLL resolution path is **identical** in both versions.
- The difference in testing is purely about *how you get Chef installed*, not how you call
  `powershell_exec`.
- Chef-19 ships **only as a Habitat package**.
- Chef-18 ships as **a Habitat package** or **an Omnibus gem** (installable via `gem install chef`
  inside an embedded Ruby environment, or via the Omnibus installer).

There are two native DLLs in the gem:

| Interpreter symbol | DLL (relative to `CHEF_POWERSHELL_BIN`) |
|---|---|
| `:powershell` | `Chef.PowerShell.Wrapper.dll` (.NET 481) |
| `:pwsh` | `shared/Microsoft.NETCore.App/10.0.0/Chef.PowerShell.Wrapper.Core.dll` (.NET 10) |

---

## Part 1 — Testing the gem itself (no Chef install needed)

These tests run against the gem sources and/or against a locally built Habitat package. They do not
require Chef to be installed.

### 1.1 RSpec unit tests

```powershell
cd C:\localrepo\chef-powershell-shim\chef-powershell
bundle install
bundle exec rake spec
```

The specs live in `spec/unit/powershell_exec_spec.rb`. They test both `:powershell` and `:pwsh`
interpreters and are tagged `:windows_only` so they only run on Windows. `CHEF_POWERSHELL_BIN` is
set by the `before` block in the spec to the gem's own `bin/ruby_bin_folder/<ARCH>/` folder.

### 1.2 Smoke-test a locally built Hab package

`smoke_test_dlls.rb` verifies that both DLLs in the built package actually execute PowerShell
without needing Chef installed at all.

**Step 1 — install the .hart file you want to test and capture its installed path:**
`build_gems.ps1` already does this for you (see `$x64`/`$x64_bin_path`); for a standalone
`.hart` you built manually:

```powershell
hab pkg install results\chef-chef-powershell-shim-19.1.0-20260818161158-x86_64-windows.hart
$pkgPath = (hab pkg path chef/chef-powershell-shim)
# e.g. C:\hab\pkgs\chef\chef-powershell-shim\19.1.0\20260818161158
```

**Step 2 — run the smoke test:**

```powershell
cd C:\localrepo\chef-powershell-shim\chef-powershell
bundle exec ruby smoke_test_dlls.rb "$pkgPath\bin"
```

Or via environment variable:

```powershell
$env:CHEF_POWERSHELL_BIN = "$pkgPath\bin"
bundle exec ruby smoke_test_dlls.rb
```

Exit code 0 = all tests passed.

### 1.3 Full package layout verification

`verify_hab_build.rb` checks that the Hab package has the correct directory layout *and* that both
runtimes execute:

```powershell
bundle exec ruby verify_hab_build.rb "$pkgPath\bin"
```

This checks for the presence of:
- `bin\Chef.PowerShell.Wrapper.dll` (.NET 481 wrapper)
- `bin\shared\Microsoft.NETCore.App\10.0.0\Chef.PowerShell.Wrapper.Core.dll` (.NET 10 wrapper)
- `bin\host\fxr\10.0.0\hostfxr.dll`
- VC++ CRT redist DLLs (`vcruntime140.dll`, `msvcp140.dll`, etc.)

---

## Part 2 — Testing against Chef-19 (Habitat only)

Chef-19 is only distributed as a Habitat package. There is no Omnibus installer or standalone gem
path.

### 2.1 Install Chef-19 via Habitat

**If you've set `$env:HAB_BLDR_CHANNEL`/`$env:HAB_REFRESH_CHANNEL` to build this repo's own
Habitat plan (e.g. `base-2025`), unset that or pass `--channel stable` explicitly.**
`chef/chef-infra-client` is published to the `stable` channel, not `base-2025` — installing
without the override fails with `Package not found` even though the package exists.

```powershell
# Latest stable Chef-19 from the chef origin
hab pkg install chef/chef-infra-client --channel stable

# Pin a specific version/timestamp if needed
hab pkg install chef/chef-infra-client/19.x.y/<timestamp> --channel stable
```

### 2.2 Replace the vendored chef-powershell gem with this branch's code + fresh DLLs

Chef's Habitat packages vendor a full copy of `chef-powershell` (`lib/`, `bin/`, `ext/`, gemspec)
under `vendor/gems/chef-powershell-<version>` inside the installed package, and Chef's own
Bundler-based startup activates *that* gemspec before any of your code runs. That means
`Gem.loaded_specs["chef-powershell"]` — which this repo's own `resolve_wrapper_dll`/
`resolve_core_wrapper_dll` check first — always points at the stale vendored copy.

**`RUBYOPT -I<path>` does NOT fix this** (an earlier version of this guide recommended it —
don't use it). It only shadows which *file* `require 'chef-powershell'` resolves to; it does not
change what RubyGems considers "activated," so `Gem.loaded_specs["chef-powershell"].full_gem_path`
still points at the old vendored directory and DLL resolution still fails there (verified: you
get a `LoadError: Pwsh Core wrapper DLL not found at .../vendor/gems/chef-powershell-18.6.6/...`
even with `RUBYOPT` set). The reliable fix is to replace the vendored copy on disk:

```powershell
$chefPkg = hab pkg path chef/chef-infra-client
$vendoredDir = Get-ChildItem "$chefPkg\vendor\gems" -Filter "chef-powershell-*" -Directory | Select-Object -First 1

Remove-Item "$($vendoredDir.FullName)\lib" -Recurse -Force
Copy-Item "C:\localrepo\chef-powershell-shim\chef-powershell\lib" "$($vendoredDir.FullName)\lib" -Recurse -Force
Copy-Item "C:\localrepo\chef-powershell-shim\chef-powershell\chef-powershell.gemspec" "$($vendoredDir.FullName)\chef-powershell.gemspec" -Force

$vendoredDllDir = "$($vendoredDir.FullName)\bin\ruby_bin_folder\$env:PROCESSOR_ARCHITECTURE"
Remove-Item $vendoredDllDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $vendoredDllDir | Out-Null
Copy-Item "C:\localrepo\chef-powershell-shim\chef-powershell\bin\ruby_bin_folder\$env:PROCESSOR_ARCHITECTURE\*" -Destination $vendoredDllDir -Recurse -Force
```

This is exactly what `Set-VendoredChefPowerShellGem` in `.expeditor/build_gems.ps1` automates.
Once done, **no `RUBYOPT` or `CHEF_POWERSHELL_BIN` override is needed** for the rest of this
section — `require 'chef-powershell'` now resolves to this branch's code and DLLs directly, and
`ffi`/`ffi-yajl` are already resolved because Chef's own vendor/bundle setup provides them (the
original vendored gem needed them too).

### 2.3 Run a quick in-process PowerShell test

```powershell
hab pkg exec chef/chef-infra-client ruby -e "
  require 'chef-powershell'
  include ChefPowerShell::ChefPowerShellModule::PowerShellExec

  r = powershell_exec('`$PSVersionTable', :powershell)
  puts 'WinPS PSEdition: ' + r.result['PSEdition'].to_s
  puts 'WinPS error?   ' + r.error?.to_s

  r2 = powershell_exec('`$PSVersionTable', :pwsh)
  puts 'PSCore PSEdition: ' + r2.result['PSEdition'].to_s
  puts 'PSCore version:   ' + r2.result['PSVersion']['Major'].to_s
"
```

Expected output:

```
WinPS PSEdition: Desktop
WinPS error?   false
PSCore PSEdition: Core
PSCore version:   7
```

Note: the `` ` `` before `$PSVersionTable` is PowerShell's escape character, required so the
outer double-quoted `-e "..."` string doesn't have PowerShell itself expand its own
`$PSVersionTable` automatic variable before Ruby ever sees the code (a plain backslash does
NOT escape `$` in PowerShell double-quoted strings, unlike bash).

### 2.4 Run a Chef recipe using `powershell_exec` under Chef-19

Create a minimal test recipe at `C:\tmp\test_recipe.rb`:

```ruby
# test_recipe.rb
powershell_exec!("Write-Host 'Hello from WinPS'")
result = powershell_exec("$PSVersionTable", :pwsh)
raise "PSCore not found" unless result.result["PSEdition"] == "Core"
puts "hello world - reached Chef::Log line, PSCore detected OK"
ps_version = result.result["PSVersion"]
puts "PSEdition: #{result.result['PSEdition']}, PSVersion: #{ps_version['Major']}.#{ps_version['Minor']}.#{ps_version['Patch']}"
Chef::Log.info("PSCore major version: #{result.result['PSVersion']['Major']}")
```

> **Note on output:** `chef-apply`/`chef-client` produce very little console output on a clean,
> successful run — `Chef::Log.info` does not print at the default log level, and
> `powershell_exec!`'s internal `Write-Host` runs inside the PowerShell host, not Ruby's
> stdout. Add an explicit `puts` (as above) if you want visible proof the recipe reached past
> the `powershell_exec` call.

**`chef-client --override-runlist` requires a real cookbook**, not a loose recipe file —
`--config-option cookbook_path=C:\tmp` expects `C:\tmp\<cookbook_name>\recipes\default.rb`
plus a `metadata.rb`. For a single standalone recipe file like the one above, use `chef-apply`
instead:

```powershell
hab pkg exec chef/chef-infra-client chef-apply C:\tmp\test_recipe.rb
```

With the vendored gem already replaced in 2.2, this works with **no env var overrides** —
verified output: `hello world - reached Chef::Log line, PSCore detected OK` /
`PSEdition: Core, PSVersion: 7.6.5`.

---

## Part 3 — Testing against Chef-18 as a Habitat package

Chef-18 Habitat packages are in the `chef` origin under the `18-Stable` channel.

### 3.1 Install Chef-18 via Habitat

The plain `/18` channel/version shorthand does not resolve — you must pin a fully qualified
version. There are ~100 released 18.x patch versions, so **do not hardcode one** (it will go
stale) — resolve the newest at run time from the Habitat Depot API instead. Same channel caveat
as Chef-19 applies: `chef/chef-infra-client` lives in `stable`, not `base-2025`.

```powershell
# Resolve the newest 18.x release ident dynamically (mirrors Get-LatestHabPackageIdent
# in .expeditor/build_gems.ps1)
$matching_releases = @()
$range = 0
do {
  $page = Invoke-RestMethod "https://bldr.habitat.sh/v1/depot/channels/chef/stable/pkgs/chef-infra-client?range=$range"
  $matching_releases += $page.data | Where-Object { $_.version -like "18.*" }
  $range += $page.data.Count
} while ($page.data.Count -gt 0 -and $range -lt $page.total_count)
$latest = $matching_releases | Sort-Object { [version]$_.version }, release | Select-Object -Last 1
$chef18Ident = "$($latest.origin)/$($latest.name)/$($latest.version)/$($latest.release)"

hab pkg install $chef18Ident --channel stable
```

### 3.2 Replace the vendored chef-powershell gem with this branch's code + fresh DLLs

Same caveat and fix as Chef-19 (see 2.2) — `RUBYOPT` does not fix `Gem.loaded_specs`, so replace
the vendored copy on disk instead:

```powershell
$chefPkg = hab pkg path $chef18Ident
$vendoredDir = Get-ChildItem "$chefPkg\vendor\gems" -Filter "chef-powershell-*" -Directory | Select-Object -First 1

Remove-Item "$($vendoredDir.FullName)\lib" -Recurse -Force
Copy-Item "C:\localrepo\chef-powershell-shim\chef-powershell\lib" "$($vendoredDir.FullName)\lib" -Recurse -Force
Copy-Item "C:\localrepo\chef-powershell-shim\chef-powershell\chef-powershell.gemspec" "$($vendoredDir.FullName)\chef-powershell.gemspec" -Force

$vendoredDllDir = "$($vendoredDir.FullName)\bin\ruby_bin_folder\$env:PROCESSOR_ARCHITECTURE"
Remove-Item $vendoredDllDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $vendoredDllDir | Out-Null
Copy-Item "C:\localrepo\chef-powershell-shim\chef-powershell\bin\ruby_bin_folder\$env:PROCESSOR_ARCHITECTURE\*" -Destination $vendoredDllDir -Recurse -Force
```

### 3.3 Quick runtime test (same as Chef-19 above, different exec target)

```powershell
hab pkg exec $chef18Ident ruby -e "
  require 'chef-powershell'
  include ChefPowerShell::ChefPowerShellModule::PowerShellExec

  r = powershell_exec('`$PSVersionTable', :powershell)
  puts 'WinPS PSEdition: ' + r.result['PSEdition'].to_s

  r2 = powershell_exec('`$PSVersionTable', :pwsh)
  puts 'PSCore PSEdition: ' + r2.result['PSEdition'].to_s
"
```

### 3.4 Run a Chef recipe using `powershell_exec` under Chef-18

With the vendored gem already replaced in 3.2, no env var overrides are needed:

```powershell
hab pkg exec $chef18Ident chef-apply C:\tmp\test_recipe.rb
```

---

## Part 4 — Testing against Chef-18 as a gem (Omnibus / standalone Ruby)

Chef-18 can also be consumed through the Omnibus installer, which provides a self-contained Ruby
environment at `C:\opscode\chef\embedded\`. This path lets you install and test a specific gem
version without touching a Habitat studio.

### 4.1 Install Chef-18 via Omnibus installer

Download from https://downloads.chef.io/tools/infra-client and run the MSI, or use cinst:

```powershell
# winget
winget install Chef.ChefClient --version 18.x.y

# or Chocolatey
choco install chef-client --version 18.x.y
```

After install, the embedded Ruby is at `C:\opscode\chef\embedded\bin\ruby.exe`.

### 4.2 Install your local chef-powershell gem build into the Omnibus Ruby

Build the gem from source first. **Note:** `rake gem_build` is referenced in `task all`/`task gem`
in this repo's `Rakefile` but is never actually defined anywhere — running it fails with
`Don't know how to build task 'gem_build'`. Use the standard `gem build` command against the
gemspec instead:

```powershell
cd C:\localrepo\chef-powershell-shim\chef-powershell
gem build chef-powershell.gemspec
# Look at the "Successfully built RubyGem" output for the exact filename, e.g.:
#   File: chef-powershell-19.1.0.gem
```

> **Note on version:** the gem version comes from `lib/chef-powershell/version.rb`
> (`ChefPowerShellModule::VERSION`) and can drift from the top-level `VERSION` file (which only
> applies to the Habitat package) — always use the exact filename `gem build` printed rather
> than assuming a version number.

Then install it into the Omnibus embedded Ruby (run as Administrator), substituting the actual
filename from the `gem build` output above. Use `gem`/`gem.cmd`, not `gem.exe` — the Omnibus
embedded Ruby only ships `gem`/`gem.bat`/`gem.cmd` wrapper scripts:

```powershell
C:\opscode\chef\embedded\bin\gem install .\chef-powershell-<version>.gem --no-document
```

> **Warning:** Installing this locally built gem into an Omnibus Chef-18 environment replaces the
> `18.6.x` gem. This is intentional for testing but will affect any Chef runs on this machine
> until you revert. Consider using a VM or container.

> **Check for stale higher-numbered gems first.** RubyGems activates the *highest installed
> version* on a plain `require` — it does NOT prefer whichever gem you just installed. If an
> older test left behind e.g. `chef-powershell-19.1.0` alongside your freshly built `18.6.6`,
> `require 'chef-powershell'` silently loads the stale `19.1.0` instead (verified: this actually
> happened — `Gem.loaded_specs['chef-powershell'].full_gem_path` pointed at the old `19.1.0`
> gem dir even though `18.6.6` had just been installed). Check and clean up before trusting any
> result:
>
> ```powershell
> C:\opscode\chef\embedded\bin\gem list chef-powershell
> # Uninstall anything that isn't the version you intend to test:
> C:\opscode\chef\embedded\bin\gem uninstall chef-powershell -v <stale-version> --force
> ```

### 4.3 Verify the gem is loaded correctly

```powershell
C:\opscode\chef\embedded\bin\ruby -e "
  require 'chef-powershell'
  puts Gem.loaded_specs['chef-powershell'].version
  puts Gem.loaded_specs['chef-powershell'].full_gem_path
"
```

### 4.4 Run the quick PowerShell test via Omnibus Ruby

```powershell
C:\opscode\chef\embedded\bin\ruby -e "
  require 'chef-powershell'
  include ChefPowerShell::ChefPowerShellModule::PowerShellExec

  r = powershell_exec('`$PSVersionTable', :powershell)
  puts 'WinPS PSEdition: ' + r.result['PSEdition'].to_s
  puts 'WinPS error?   ' + r.error?.to_s

  r2 = powershell_exec('`$PSVersionTable', :pwsh)
  puts 'PSCore PSEdition: ' + r2.result['PSEdition'].to_s
  puts 'PSCore version:   ' + r2.result['PSVersion']['Major'].to_s
"
```

### 4.5 Run a Chef recipe via Omnibus chef-client

```powershell
C:\opscode\chef\bin\chef-apply C:\tmp\test_recipe.rb
```

### 4.6 Point Omnibus Ruby at the locally built shim DLLs (optional)

If you want to test DLLs from a local Hab package rather than the ones baked into the gem:

```powershell
$shimPkg = hab pkg path chef/chef-powershell-shim
$env:CHEF_POWERSHELL_BIN = "$shimPkg\bin"

C:\opscode\chef\embedded\bin\ruby -e "
  require 'chef-powershell'
  include ChefPowerShell::ChefPowerShellModule::PowerShellExec
  r = powershell_exec('`$PSVersionTable', :pwsh)
  puts r.result['PSVersion']['Major']
"
```

---

## Part 5 — What to check in each test scenario

Regardless of which method you use, always verify these specific behaviors.

**Where to run this:** `chef_gem_integration_test.rb` (same directory as this doc) already runs
every check below as a single script — prefer it over copy-pasting snippets. Run it with
whichever Ruby you're testing:

```powershell
# Omnibus Chef-18
C:\opscode\chef\embedded\bin\ruby.exe C:\localrepo\chef-powershell-shim\chef-powershell\chef_gem_integration_test.rb

# Habitat Chef-18/19, after Set-VendoredChefPowerShellGem has replaced the vendored copy (2.2/3.2)
hab pkg exec <chef-ident> ruby C:\localrepo\chef-powershell-shim\chef-powershell\chef_gem_integration_test.rb
```

If you do want to check something ad hoc, paste the snippets below directly into whichever
`ruby -e "..."` command (or `irb`/`pry` session) you're already using from Part 2/3/4, right after
the `include ChefPowerShell::ChefPowerShellModule::PowerShellExec` line — they assume `r`/`r2`
were just assigned by a `powershell_exec` call in that same session.

### 5.1 Both interpreters work

```ruby
# Windows PowerShell (Desktop edition, .NET 481 DLL)
r = powershell_exec("$PSVersionTable", :powershell)
raise unless r.result["PSEdition"] == "Desktop"
raise unless r.result["PSVersion"].to_s.to_i < 6

# PowerShell Core (Core edition, .NET 10 DLL)
r2 = powershell_exec("$PSVersionTable", :pwsh)
raise unless r2.result["PSEdition"] == "Core"
raise unless r2.result["PSVersion"]["Major"] >= 7
```

### 5.2 Error handling works

```ruby
r = powershell_exec("this-command-does-not-exist")
raise unless r.error?
raise unless r.errors.first.include?("not recognized")
```

### 5.3 `.error!` raises correctly

```ruby
begin
  powershell_exec!("throw 'boom'")
  raise "should have raised"
rescue ChefPowerShell::PowerShellExceptions::PowerShellCommandFailed
  puts "error! raised correctly"
end
```

### 5.4 Result types are correct

```ruby
r = powershell_exec("$true")
raise unless r.result == true

r = powershell_exec("[ordered]@{a=1; b='hello'}")
raise unless r.result["a"] == 1
raise unless r.result["b"] == "hello"
```

### 5.5 DLL resolution path is what you expect

```ruby
puts ENV["CHEF_POWERSHELL_BIN"]
puts Gem.loaded_specs["chef-powershell"]&.full_gem_path
```

---

## Part 6 — Troubleshooting

### "Chef.PowerShell.Wrapper.dll not found"

`CHEF_POWERSHELL_BIN` is pointing at a directory that does not contain the DLL, or the env var is
not set. The gem falls back to `bin/ruby_bin_folder/<ARCH>/` inside the gem's own `full_gem_path`.
Check both:

```ruby
puts ENV["CHEF_POWERSHELL_BIN"]
puts Gem.loaded_specs["chef-powershell"].full_gem_path + "/bin/ruby_bin_folder/AMD64/"
```

### "hostfxr.dll not found" or "The framework 'Microsoft.NETCore.App' was not found"

The `.NET 10` runtime layout inside the package is incomplete. Run `verify_hab_build.rb` to check
the layout. Ensure `host/fxr/10.0.0/hostfxr.dll` exists and `DOTNET_ROOT` is either not set or
points at the correct location. The gem sets `DOTNET_MULTILEVEL_LOOKUP=0` and overrides
`DOTNET_ROOT` to `bin/ruby_bin_folder/<ARCH>` during `:pwsh` calls.

### `DOTNET_ROOT` conflicts with a system .NET installation

The `Pwsh#exec` method in the gem temporarily overrides `DOTNET_ROOT` for the duration of the
PowerShell call and restores it afterwards. If another thread is also making .NET calls
simultaneously, there can be a race. In single-threaded testing this is not an issue.

### Version mismatch after installing 19.1.0 gem into Chef-18 Omnibus

Bundler's lockfile may still reference the old `18.6.x` gem. Run:

```powershell
C:\opscode\chef\embedded\bin\bundle update chef-powershell
```

or force the gem path with `gem 'chef-powershell', path: '...'` in a local Gemfile.

### Hab package not found after `hab pkg install`

```powershell
hab pkg list chef/chef-powershell-shim
hab pkg path chef/chef-powershell-shim
```

If using a local `.hart` file, install with the full path:

```powershell
hab pkg install C:\localrepo\chef-powershell-shim\results\chef-chef-powershell-shim-19.1.0-20260818161158-x86_64-windows.hart
```

---

## Quick reference

| Goal | Command |
|---|---|
| Run RSpec unit tests | `bundle exec rake spec` (from `chef-powershell/`) |
| Smoke test local Hab build | `bundle exec ruby smoke_test_dlls.rb <pkg>\bin` |
| Full layout verification | `bundle exec ruby verify_hab_build.rb <pkg>\bin` |
| Test under Chef-19 Hab | `hab pkg exec chef/chef-infra-client ruby -e "..."` (`--channel stable` on install; replace vendored gem first, see 2.2) |
| Test under Chef-18 Hab | `hab pkg exec $chef18Ident ruby -e "..."` (replace vendored gem first, see 3.2) |
| Test under Chef-18 Omnibus | `C:\opscode\chef\embedded\bin\ruby -e "..."` |
| Install local gem into Omnibus | `C:\opscode\chef\embedded\bin\gem install .\chef-powershell-<version>.gem` |
| Replace a Habitat package's vendored gem | see `Set-VendoredChefPowerShellGem` in `.expeditor/build_gems.ps1`, or 2.2/3.2 |
| Override DLL path at runtime (Omnibus only) | `$env:CHEF_POWERSHELL_BIN = "<path>\bin"` |
| Automated CI equivalent | `.expeditor\build_gems.ps1` + `chef_gem_integration_test.rb` |

# Testing chef-powershell with Chef-18 and Chef-19

**Branch context:** This guide is written against `jfm/net10-update` (chef-powershell-shim v19.1.0,
.NET 10 / PS Core 7.6.x). Adjust version strings as needed for other branches.

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

**Step 1 — install the .hart file you want to test:**

```powershell
hab pkg install results\chef-chef-powershell-shim-19.1.0-20260818161158-x86_64-windows.hart
```

**Step 2 — find the installed package prefix:**

```powershell
$pkgPath = (hab pkg path chef/chef-powershell-shim)
# e.g. C:\hab\pkgs\chef\chef-powershell-shim\19.1.0\20260818161158
```

**Step 3 — run the smoke test:**

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

```powershell
# Latest stable Chef-19 from the chef origin
hab pkg install chef/chef-infra-client

# Pin a specific version/timestamp if needed
hab pkg install chef/chef-infra-client/19.x.y/<timestamp>
```

### 2.2 Find Chef-19's embedded Ruby, and load the LOCAL gem source (not the baked-in one)

Chef-19's `chef-infra-client` package does NOT bundle `ruby.exe` in its own `bin/` folder —
that folder only contains the `chef-*`/`ohai`/`inspec` wrapper scripts. Ruby is a separate
Habitat dependency package (`core/ruby3_4-plus-devkit` as of this writing); find it via
`hab pkg dependencies` or by locating the installed package directly:

```powershell
$chefPkg = hab pkg path chef/chef-infra-client
$rubyPkg = hab pkg path core/ruby3_4-plus-devkit
$rubyExe = "$rubyPkg\bin\ruby.exe"
```

**Important:** whatever `chef-powershell` gem version is already bundled inside the installed
`chef-infra-client` package was baked in at *that package's build time* — it does **not**
contain the fix from this branch. Do not test against it. Instead, use this repo's own
`Gemfile`/`Gemfile.lock` (already set up for `bundle exec rake spec` in Part 1) but run it
through Chef-19's own Ruby, so `ffi`/`ffi-yajl` resolve correctly for that Ruby version:

```powershell
cd C:\localrepo\chef-powershell-shim\chef-powershell
& "$rubyPkg\bin\ruby.exe" "$rubyPkg\bin\bundle" install   # first time only, installs into ./vendor/bundle
& "$rubyPkg\bin\ruby.exe" "$rubyPkg\bin\bundle" exec ruby -e "require 'chef-powershell'; puts 'loaded OK'"
```

A plain `-I "...\chef-powershell\lib" -e "require 'chef-powershell'"` will **fail** with
`LoadError: cannot load such file -- ffi` — `ffi`/`ffi-yajl` are not installed anywhere on
`core/ruby3_4-plus-devkit`'s base gem path by default. `bundle exec` (using this repo's
Gemfile) is required to resolve them.

### 2.3 Point `CHEF_POWERSHELL_BIN` at a freshly built shim package (not chef-infra-client's own bin)

Build/install the `chef-powershell-shim` Habitat package from this branch (see Part 1.2), then
point `CHEF_POWERSHELL_BIN` at *that* package's `bin/` directory — not at `chef-infra-client`'s
own `bin/`, which only has the old DLLs from whenever `chef-infra-client` was last built:

```powershell
$pkgPath = (hab pkg path chef/chef-powershell-shim)
$env:CHEF_POWERSHELL_BIN = "$pkgPath\bin"
```

### 2.4 Run a quick in-process PowerShell test via Chef-19's Ruby, using the local gem + fresh DLLs

```powershell
cd C:\localrepo\chef-powershell-shim\chef-powershell
& "$rubyPkg\bin\ruby.exe" "$rubyPkg\bin\bundle" exec ruby -e "
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

Once this branch's `chef-powershell` gem changes are actually merged and `chef-infra-client` is
rebuilt against them, the gem no longer needs to be loaded via `-I` — the normal
`hab pkg exec chef/chef-infra-client ruby -e "require 'chef-powershell'; ..."` flow (without the
`-I` override) becomes the correct way to test, since the fix will then be baked into the
installed package.

### 2.5 Run a Chef recipe using `powershell_exec` under Chef-19

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

**Important — this alone will reproduce error 126, not test the fix.** `chef-apply` loads
whatever `chef-powershell` gem version is bundled inside the installed `chef-infra-client`
package (verified: v18.6.6 referencing the old `.NET 8.0.0` path in this install) — that gem
predates this branch's fix and does not respect `CHEF_POWERSHELL_BIN` overrides at all (only
the fixed `bin_dir` helper added in this branch does). Setting `CHEF_POWERSHELL_BIN` alone will
NOT redirect it. To actually exercise this branch's fixed code, force Ruby to load this repo's
gem source ahead of the bundled one via `RUBYOPT`:

```powershell
$env:RUBYOPT = "-IC:\localrepo\chef-powershell-shim\chef-powershell\lib"
hab pkg exec chef/chef-infra-client chef-apply C:\tmp\test_recipe.rb
# Expected output: "hello world - reached Chef::Log line, PSCore detected OK"

# Clean up afterward so it doesn't leak into unrelated commands in this shell session:
Remove-Item Env:\RUBYOPT
```

### 2.6 Test against the locally built shim Hab package under Chef-19

If you want Chef-19 to use your **locally built** shim DLLs instead of the ones baked into its
bundled gem, override `CHEF_POWERSHELL_BIN`:

```powershell
$shimPkg = hab pkg path chef/chef-powershell-shim   # install local .hart first
$env:CHEF_POWERSHELL_BIN = "$shimPkg\bin"

hab pkg exec chef/chef-infra-client ruby -e "
  require 'chef-powershell'
  include ChefPowerShell::ChefPowerShellModule::PowerShellExec
  r = powershell_exec('`$PSVersionTable', :pwsh)
  puts r.result['PSVersion']['Major']
"
```

> **Important — this alone will reproduce error 126, same as section 2.5.** `chef-infra-client`
> vendors its own copy of `chef-powershell` (v18.6.6) inside the package itself
> (`vendor/gems/chef-powershell-18.6.6`), and a plain `require 'chef-powershell'` will always
> resolve to that vendored copy first — regardless of `CHEF_POWERSHELL_BIN` — because the old
> gem's code doesn't know to look at that env var. Setting `CHEF_POWERSHELL_BIN` only has an
> effect once Ruby is actually loading **this repo's** `chef-powershell` source. Force that with
> `RUBYOPT` before running:
>
> ```powershell
> $shimPkg = hab pkg path chef/chef-powershell-shim   # install local .hart first
> $env:CHEF_POWERSHELL_BIN = "$shimPkg\bin"
> $env:RUBYOPT = "-IC:\localrepo\chef-powershell-shim\chef-powershell\lib"
>
> hab pkg exec chef/chef-infra-client ruby -e "
>   require 'chef-powershell'
>   include ChefPowerShell::ChefPowerShellModule::PowerShellExec
>   r = powershell_exec('`$PSVersionTable', :pwsh)
>   puts r.result['PSVersion']['Major']
> "
>
> # Clean up afterward so it doesn't leak into unrelated commands in this shell session:
> Remove-Item Env:\RUBYOPT
> Remove-Item Env:\CHEF_POWERSHELL_BIN -ErrorAction SilentlyContinue
> ```
>
> With both set, `require 'chef-powershell'` resolves to this repo's `lib/chef-powershell.rb`,
> which uses the `ChefPowerShell.bin_dir` helper — that helper DOES check `CHEF_POWERSHELL_BIN`
> first, so the DLLs from your locally built `chef-powershell-shim` Hab package get used.

---

## Part 3 — Testing against Chef-18 as a Habitat package

Chef-18 Habitat packages are in the `chef` origin under the `18-Stable` channel.

### 3.1 Install Chef-18 via Habitat

The plain `/18` channel/version shorthand does not resolve — pin an actual version instead:

```powershell
# Pin a specific 18.x version (verified working)
hab pkg install chef/chef-infra-client/18.11.11

# Or pin a specific version/timestamp if you need an exact build
hab pkg install chef/chef-infra-client/18.x.y/<timestamp>
```

### 3.2 Find Chef-18's embedded Ruby, and load the LOCAL gem source (not the baked-in one)

Just like Chef-19 (see 2.2), `chef-infra-client`'s own `bin/` folder does NOT contain
`ruby.exe` — it only has the `chef-*`/`ohai`/`inspec` wrapper scripts. Ruby is a separate
Habitat dependency package. Chef-18 depends on an older Ruby (3.1.x) devkit package rather
than the 3.4.x one Chef-19 uses, so discover it dynamically instead of hardcoding the name:

```powershell
$chefPkg = hab pkg path chef/chef-infra-client/18.11.11
$rubyIdent = (hab pkg dependencies chef/chef-infra-client/18.11.11 | Select-String "ruby").ToString().Trim()
$rubyPkg = hab pkg path $rubyIdent
$rubyExe = "$rubyPkg\bin\ruby.exe"
```

**Important:** just like Chef-19, whatever `chef-powershell` gem version is already bundled
inside the installed `chef-infra-client` package (pinned to `~> 18.6.x`) predates this branch's
fix. Do not test against it directly. Use this repo's own `Gemfile`/`Gemfile.lock` run through
Chef-18's own Ruby instead, so `ffi`/`ffi-yajl` resolve correctly for that Ruby version:

```powershell
cd C:\localrepo\chef-powershell-shim\chef-powershell
& "$rubyPkg\bin\ruby.exe" "$rubyPkg\bin\bundle" install   # first time only, installs into ./vendor/bundle
& "$rubyPkg\bin\ruby.exe" "$rubyPkg\bin\bundle" exec ruby -e "require 'chef-powershell'; puts 'loaded OK'"
```

### 3.3 Point `CHEF_POWERSHELL_BIN` at a freshly built shim package

```powershell
$pkgPath = (hab pkg path chef/chef-powershell-shim)
$env:CHEF_POWERSHELL_BIN = "$pkgPath\bin"
```

### 3.4 Quick runtime test (same as Chef-19 above, different exec target)

```powershell
cd C:\localrepo\chef-powershell-shim\chef-powershell
& "$rubyPkg\bin\ruby.exe" "$rubyPkg\bin\bundle" exec ruby -e "
  require 'chef-powershell'
  include ChefPowerShell::ChefPowerShellModule::PowerShellExec

  r = powershell_exec('`$PSVersionTable', :powershell)
  puts 'WinPS PSEdition: ' + r.result['PSEdition'].to_s

  r2 = powershell_exec('`$PSVersionTable', :pwsh)
  puts 'PSCore PSEdition: ' + r2.result['PSEdition'].to_s
"
```

### 3.5 Run a Chef recipe using `powershell_exec` under Chef-18

Same caveat as Chef-19 section 2.5 — running `chef-apply` directly loads the stale bundled
`~> 18.6.x` gem and reproduces error 126. Force the local repo source via `RUBYOPT`:

```powershell
$env:RUBYOPT = "-IC:\localrepo\chef-powershell-shim\chef-powershell\lib"
hab pkg exec chef/chef-infra-client/18.11.11 chef-apply C:\tmp\test_recipe.rb
Remove-Item Env:\RUBYOPT
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
filename from the `gem build` output above:

```powershell
C:\opscode\chef\embedded\bin\gem install .\chef-powershell-<version>.gem --no-document
```

> **Warning:** Installing this locally built gem into an Omnibus Chef-18 environment replaces the
> `18.6.x` gem. This is intentional for testing but will affect any Chef runs on this machine
> until you revert. Consider using a VM or container.

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

Regardless of which method you use, always verify these specific behaviors:

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
| Test under Chef-19 Hab | `hab pkg exec chef/chef-infra-client ruby -e "..."` |
| Test under Chef-18 Hab | `& "$rubyPkg\bin\ruby.exe" "$rubyPkg\bin\bundle" exec ruby -e "..."` (see 3.2) |
| Test under Chef-18 Omnibus | `C:\opscode\chef\embedded\bin\ruby -e "..."` |
| Install local gem into Omnibus | `C:\opscode\chef\embedded\bin\gem install .\chef-powershell-<version>.gem` |
| Override DLL path at runtime | `$env:CHEF_POWERSHELL_BIN = "<path>\bin"` |

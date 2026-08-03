#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_hab_build.rb — Verifies a freshly built chef-powershell-shim Hab package.
#
# Checks that the package layout is correct, all required files are present,
# and that both PowerShell runtimes (.NET Framework 4.8.1 and .NET 10) execute
# successfully.
#
# Usage (from a Hab studio or on the host after building):
#   ruby verify_hab_build.rb <path\to\pkg_prefix\bin>
#
# Or via environment variable:
#   $env:CHEF_POWERSHELL_BIN = "C:\hab\pkgs\chef\chef-powershell-shim\X.Y.Z\<timestamp>\bin"
#   ruby verify_hab_build.rb
#
# Exit code: 0 = all checks passed, 1 = one or more failures

BIN_DIR = if ARGV[0]
            File.expand_path(ARGV[0])
          elsif ENV["CHEF_POWERSHELL_BIN"]
            File.expand_path(ENV["CHEF_POWERSHELL_BIN"])
          else
            abort "Usage: ruby verify_hab_build.rb <path\\to\\pkg_prefix\\bin>\n" \
                  "  or set CHEF_POWERSHELL_BIN environment variable"
          end.freeze

CORE_DIR = File.join(BIN_DIR, "shared", "Microsoft.NETCore.App", "10.0.0").freeze
FXR_DIR  = File.join(BIN_DIR, "host", "fxr", "10.0.0").freeze

NET481_DLL = File.join(BIN_DIR, "Chef.PowerShell.Wrapper.dll").freeze
NET10_DLL  = File.join(CORE_DIR, "Chef.PowerShell.Wrapper.Core.dll").freeze

# ---------------------------------------------------------------------------
# Load the gem from source
# ---------------------------------------------------------------------------

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

unless Gem.loaded_specs["chef-powershell"]
  gemspec_path = File.expand_path("chef-powershell.gemspec", __dir__)
  if File.exist?(gemspec_path)
    spec = Gem::Specification.load(gemspec_path)
    spec.instance_variable_set(:@full_gem_path, File.expand_path(__dir__))
    Gem.loaded_specs[spec.name] = spec
  end
end

require "chef-powershell"

ENV["CHEF_POWERSHELL_BIN"] = BIN_DIR

# Override Pwsh#exec so it points at our built DLLs instead of the gem's bundled ones.
class ChefPowerShell
  class Pwsh
    def exec(script, timeout: -1)
      orig_mlookup = ENV["DOTNET_MULTILEVEL_LOOKUP"]
      orig_root    = ENV["DOTNET_ROOT"]
      orig_root86  = ENV["DOTNET_ROOT(x86)"]

      ENV["DOTNET_MULTILEVEL_LOOKUP"] = "0"
      ENV["DOTNET_ROOT"]      = BIN_DIR
      ENV["DOTNET_ROOT(x86)"] = BIN_DIR
      @powershell_dll = NET10_DLL

      ChefPowerShell::PowerShell.instance_method(:exec).bind(self).call(script, timeout: timeout)
    ensure
      ENV["DOTNET_MULTILEVEL_LOOKUP"] = orig_mlookup
      ENV["DOTNET_ROOT"]      = orig_root
      ENV["DOTNET_ROOT(x86)"] = orig_root86
    end
  end
end

# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------

PASS  = "\e[32mPASS\e[0m"
FAIL  = "\e[31mFAIL\e[0m"
BOLD  = "\e[1m"
RESET = "\e[0m"

$failures = 0
$passes   = 0

def check(description)
  result = yield
  if result
    puts "  #{PASS} #{description}"
    $passes += 1
  else
    puts "  #{FAIL} #{description}"
    $failures += 1
  end
rescue => e
  puts "  #{FAIL} #{description}"
  puts "       #{e.class}: #{e.message.lines.first&.chomp}"
  $failures += 1
end

def section(title)
  puts "\n#{BOLD}#{title}#{RESET}"
end

def ps481(script, timeout: -1)
  ps = ChefPowerShell::PowerShell.allocate
  ps.instance_variable_set(:@powershell_dll, NET481_DLL)
  ps.send(:exec, script, timeout: timeout)
  ps
end

def ps_core(script, timeout: -1)
  ChefPowerShell::Pwsh.new(script, timeout: timeout)
end

puts "#{BOLD}chef-powershell-shim Hab Build Verification#{RESET}"
puts "BIN_DIR  : #{BIN_DIR}"
puts "CORE_DIR : #{CORE_DIR}"
puts "FXR_DIR  : #{FXR_DIR}"

# ---------------------------------------------------------------------------
# 1. Package layout
# ---------------------------------------------------------------------------

section("1. Package layout — required files and directories")

check("bin/ directory exists") { Dir.exist?(BIN_DIR) }
check("shared/Microsoft.NETCore.App/10.0.0/ exists")   { Dir.exist?(CORE_DIR) }
check("host/fxr/10.0.0/ exists")                       { Dir.exist?(FXR_DIR) }

check("Chef.PowerShell.Wrapper.dll present (net481)") { File.exist?(NET481_DLL) }
check("Chef.PowerShell.Wrapper.Core.dll present (net10)") { File.exist?(NET10_DLL) }
check("Chef.Powershell.Core.dll present in CORE_DIR")  { File.exist?(File.join(CORE_DIR, "Chef.Powershell.Core.dll")) }

check("hostfxr.dll present in host/fxr/10.0.0/")       { File.exist?(File.join(FXR_DIR, "hostfxr.dll")) }
check("hostfxr.dll present in CORE_DIR (self-contained)") { File.exist?(File.join(CORE_DIR, "hostfxr.dll")) }
check("Ijwhost.dll present in BIN_DIR")                 { File.exist?(File.join(BIN_DIR, "Ijwhost.dll")) }

check("Microsoft.NETCore.App.deps.json present (renamed from Chef.Powershell.Core.deps.json)") do
  File.exist?(File.join(CORE_DIR, "Microsoft.NETCore.App.deps.json"))
end
check("Chef.Powershell.Core.deps.json absent (should have been renamed)") do
  !File.exist?(File.join(CORE_DIR, "Chef.Powershell.Core.deps.json"))
end
check("Chef.PowerShell.Wrapper.Core.runtimeconfig.json present") do
  File.exist?(File.join(CORE_DIR, "Chef.Powershell.Wrapper.Core.runtimeconfig.json"))
end

check("System.Diagnostics.PerformanceCounter.dll present (runtime dep)") do
  File.exist?(File.join(CORE_DIR, "System.Diagnostics.PerformanceCounter.dll"))
end

check("VC++ CRT redist DLLs present (e.g. vcruntime140.dll)") do
  Dir.glob(File.join(BIN_DIR, "vcruntime*.dll")).any?
end

# ---------------------------------------------------------------------------
# 2. Windows PowerShell (.NET Framework 4.8.1)
# ---------------------------------------------------------------------------

section("2. Windows PowerShell — Chef.PowerShell.Wrapper.dll (.NET Framework 4.8.1)")

check("Executes a trivial script (1 + 1 = 2)") do
  r = ps481("1 + 1")
  r.errors.empty? && r.result == 2
end

check("PSEdition is Desktop") do
  r = ps481("$PSVersionTable")
  r.result["PSEdition"] == "Desktop"
end

check("PSVersion major is 5") do
  r = ps481("$PSVersionTable")
  r.result["PSVersion"]["Major"].to_i == 5
end

check("Returns a string value") do
  r = ps481("'hello from net481'")
  r.result == "hello from net481"
end

check("Returns a hashtable as a Ruby hash") do
  r = ps481("@{ Key = 'Value' }")
  r.result["Key"] == "Value"
end

check("Non-terminating error captured in .errors (not raised)") do
  r = ps481("Write-Error 'net481 deliberate error'")
  r.error? && r.errors.first.include?("net481 deliberate error")
end

check("No errors on clean script") do
  r = ps481("'clean'")
  !r.error?
end

# ---------------------------------------------------------------------------
# 3. PowerShell Core (.NET 10)
# ---------------------------------------------------------------------------

section("3. PowerShell Core — Chef.PowerShell.Wrapper.Core.dll (.NET 10)")

check("Executes a trivial script (1 + 1 = 2)") do
  r = ps_core("1 + 1")
  r.errors.empty? && r.result == 2
end

check("PSEdition is Core") do
  r = ps_core("$PSVersionTable")
  r.result["PSEdition"] == "Core"
end

check("PSVersion major is >= 7") do
  r = ps_core("$PSVersionTable")
  r.result["PSVersion"]["Major"].to_i >= 7
end

check("Returns a string value") do
  r = ps_core("'hello from net10'")
  r.result == "hello from net10"
end

check("Returns a hashtable as a Ruby hash") do
  r = ps_core("@{ Key = 'Value' }")
  r.result["Key"] == "Value"
end

check("Non-terminating error captured in .errors (not raised)") do
  r = ps_core("Write-Error 'net10 deliberate error'")
  r.error? && r.errors.first.include?("net10 deliberate error")
end

check("No errors on clean script") do
  r = ps_core("'clean'")
  !r.error?
end

# ---------------------------------------------------------------------------
# 4. Cross-runtime parity
# ---------------------------------------------------------------------------

section("4. Cross-runtime parity")

check("Both runtimes return the same arithmetic result") do
  ps481("6 * 7").result == ps_core("6 * 7").result
end

check("Both runtimes see PROCESSOR_ARCHITECTURE env var") do
  r481  = ps481("$env:PROCESSOR_ARCHITECTURE")
  rcore = ps_core("$env:PROCESSOR_ARCHITECTURE")
  r481.result =~ /AMD64|x86|ARM64/i && rcore.result =~ /AMD64|x86|ARM64/i
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

total = $passes + $failures
puts "\n#{BOLD}Results: #{$passes}/#{total} passed#{RESET}"
if $failures > 0
  puts "#{FAIL} #{$failures} check(s) failed"
  exit 1
else
  puts "#{PASS} All checks passed"
  exit 0
end

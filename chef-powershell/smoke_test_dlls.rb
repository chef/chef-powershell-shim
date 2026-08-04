#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Standalone smoke test for the built Chef PowerShell DLLs.
#
# Usage:
#   ruby smoke_test_dlls.rb <path\to\hab_package\bin>
#
# Or via environment variable:
#   $env:CHEF_POWERSHELL_BIN = "C:\hab\pkgs\chef\chef-powershell-shim\X.Y.Z\timestamp\bin"
#   ruby smoke_test_dlls.rb
#
# Exit code: 0 = all tests passed, 1 = one or more failures

# Resolve the DLL bin directory
BIN_DIR = if ARGV[0]
            File.expand_path(ARGV[0])
          elsif ENV["CHEF_POWERSHELL_BIN"]
            ENV["CHEF_POWERSHELL_BIN"]
          else
            abort "Usage: ruby smoke_test_dlls.rb <path\\to\\bin>\n" \
                  "  or set CHEF_POWERSHELL_BIN environment variable"
          end.freeze

NET481_DLL = File.join(BIN_DIR, "Chef.PowerShell.Wrapper.dll").freeze
NET10_DLL  = File.join(BIN_DIR, "shared", "Microsoft.NETCore.App", "10.0.0",
  "Chef.PowerShell.Wrapper.Core.dll").freeze

# Add gem lib to load path (run from the chef-powershell directory or its parent)
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

# When running from source (not installed as a gem), Gem.loaded_specs["chef-powershell"]
# is nil, which causes powershell.rb to crash at class-body load time.
# Register the gemspec manually so full_gem_path resolves to this directory.
unless Gem.loaded_specs["chef-powershell"]
  gemspec_path = File.expand_path("chef-powershell.gemspec", __dir__)
  if File.exist?(gemspec_path)
    spec = Gem::Specification.load(gemspec_path)
    spec.instance_variable_set(:@full_gem_path, File.expand_path(__dir__))
    Gem.loaded_specs[spec.name] = spec
  end
end

require "chef-powershell"

# powershell_exec.rb sets CHEF_POWERSHELL_BIN to the gem source dir at load time,
# overriding whatever was set before. Reset it to our hab package bin dir so the
# C++/CLI wrapper can find Chef.PowerShell.dll alongside itself.
ENV["CHEF_POWERSHELL_BIN"] = BIN_DIR

# Pwsh#exec resets @powershell_dll and DOTNET_ROOT to paths inside the gem's
# own bin/ruby_bin_folder tree.  Reopen the class so it uses BIN_DIR (the hab
# package) instead.  This is the correct way to test the built DLLs without
# having the gem installed.
class ChefPowerShell
  class Pwsh
    def exec(script, timeout: -1)
      original_dml      = ENV["DOTNET_MULTILEVEL_LOOKUP"]
      original_root     = ENV["DOTNET_ROOT"]
      original_root_x86 = ENV["DOTNET_ROOT(x86)"]

      ENV["DOTNET_MULTILEVEL_LOOKUP"] = "0"
      ENV["DOTNET_ROOT"]      = BIN_DIR
      ENV["DOTNET_ROOT(x86)"] = BIN_DIR
      @powershell_dll = NET10_DLL

      # Call PowerShell#exec directly — we are already inside Pwsh#exec so
      # calling super would recurse.  bind() bypasses Ruby access control.
      ChefPowerShell::PowerShell.instance_method(:exec).bind(self).call(script, timeout: timeout)
    ensure
      ENV["DOTNET_MULTILEVEL_LOOKUP"] = original_dml
      ENV["DOTNET_ROOT"]      = original_root
      ENV["DOTNET_ROOT(x86)"] = original_root_x86
    end
  end
end

# ---------------------------------------------------------------------------
# Minimal test harness
# ---------------------------------------------------------------------------

PASS  = "\e[32mPASS\e[0m"
FAIL  = "\e[31mFAIL\e[0m"
SKIP  = "\e[33mSKIP\e[0m"
BOLD  = "\e[1m"
RESET = "\e[0m"

$failures = 0
$passes   = 0
$skips    = 0

def check(description, skip_reason: nil)
  if skip_reason
    puts "  #{SKIP} #{description} (#{skip_reason})"
    $skips += 1
    return
  end
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
  puts "       #{e.class}: #{e.message.lines.first.chomp}"
  $failures += 1
end

def section(title)
  puts "\n#{BOLD}#{title}#{RESET}"
end

# ---------------------------------------------------------------------------
# Helpers to invoke the DLLs
# ---------------------------------------------------------------------------

def ps481(script, timeout: -1)
  ps = ChefPowerShell::PowerShell.allocate
  ps.instance_variable_set(:@powershell_dll, NET481_DLL)
  ps.send(:exec, script, timeout: timeout)
  ps
end

def ps_core(script, timeout: -1)
  ChefPowerShell::Pwsh.new(script, timeout: timeout)
end

# ---------------------------------------------------------------------------
# Pre-flight: DLL presence
# ---------------------------------------------------------------------------

section("Pre-flight: DLL file checks")
puts "  DLL directory : #{BIN_DIR}"
puts "  NET481 DLL    : #{NET481_DLL}"
puts "  NET10  DLL    : #{NET10_DLL}"
puts

net481_present = File.exist?(NET481_DLL)
net10_present  = File.exist?(NET10_DLL)

check("Chef.PowerShell.Wrapper.dll present")      { net481_present }
check("Chef.PowerShell.Wrapper.Core.dll present") { net10_present }

# ---------------------------------------------------------------------------
# Windows PowerShell (.NET Framework 4.8.1)
# ---------------------------------------------------------------------------

section("Windows PowerShell — Chef.PowerShell.Wrapper.dll (.NET Framework 4.8.1)")

if net481_present
  check("DLL loads and executes a trivial script") do
    r = ps481("1 + 1")
    r.errors.empty? && r.result == 2
  end

  check("Returns PSEdition = Desktop") do
    r = ps481("$PSVersionTable")
    r.result["PSEdition"] == "Desktop"
  end

  check("PS version is < 7") do
    r = ps481("$PSVersionTable")
    r.result["PSVersion"].to_s.to_i < 7
  end

  check("Returns a string") do
    r = ps481("'hello from net481'")
    r.result == "hello from net481"
  end

  check("Returns integer 42") do
    r = ps481("42")
    r.result == 42
  end

  check("Returns boolean true") do
    r = ps481("$true")
    r.result == true
  end

  check("Returns boolean false") do
    r = ps481("$false")
    r.result == false
  end

  check("Returns an array") do
    r = ps481("@(1, 2, 3)")
    Array(r.result).sort == [1, 2, 3]
  end

  check("Returns a hashtable as a Ruby hash") do
    r = ps481("@{ Name = 'Chef'; Version = '18' }")
    r.result["Name"] == "Chef" && r.result["Version"] == "18"
  end

  check("Handles multi-line script") do
    r = ps481("$s = 0\n1..10 | ForEach-Object { $s += $_ }\n$s")
    r.result == 55
  end

  check("Captures non-terminating error in .errors") do
    r = ps481("Write-Error 'net481 error test'")
    r.error? && r.errors.first.include?("net481 error test")
  end

  check("error? is false when no errors") do
    r = ps481("'clean'")
    !r.error?
  end

  check("Captures verbose output") do
    r = ps481("Write-Verbose 'net481 verbose' -Verbose")
    r.verbose.join.include?("net481 verbose")
  end

  check("Reads current process ID") do
    r = ps481("$PID")
    r.result.is_a?(Integer) && r.result > 0
  end

  check("env:PROCESSOR_ARCHITECTURE is accessible") do
    r = ps481("$env:PROCESSOR_ARCHITECTURE")
    r.result =~ /AMD64|x86|ARM64/i
  end

  check("String interpolation works") do
    r = ps481('"Result: $( 6 * 7 )"')
    r.result == "Result: 42"
  end

  check("Select-Object returns a typed hash") do
    r = ps481("Get-Process -Id $PID | Select-Object Id, ProcessName")
    r.result["Id"].is_a?(Integer) && !r.result["ProcessName"].to_s.empty?
  end

  check("Timeout: fast script completes within 5 seconds") do
    t = Time.now
    r = ps481("'fast'", timeout: 10)
    (Time.now - t) < 5 && r.result == "fast"
  end

  check("Timeout: slow script raises or errors (1s timeout)") do

    r = ps481("Start-Sleep -Seconds 30", timeout: 1)
    r.error? # some implementations signal timeout via errors rather than raising
  rescue => _e
    true

  end

  check("Unknown command captured as error (not exception)") do
    r = ps481("this-cmd-xyz-does-not-exist")
    r.error? && r.errors.first =~ /not recognized|CommandNotFoundException/i
  end
else
  puts "  #{SKIP} All NET481 tests — DLL not found"
  $skips += 13
end

# ---------------------------------------------------------------------------
# PowerShell Core (.NET 10)
# ---------------------------------------------------------------------------

section("PowerShell Core — Chef.PowerShell.Wrapper.Core.dll (.NET 10)")

if net10_present
  check("DLL loads and executes a trivial script") do
    r = ps_core("1 + 1")
    r.errors.empty? && r.result == 2
  end

  check("Returns PSEdition = Core") do
    r = ps_core("$PSVersionTable")
    r.result["PSEdition"] == "Core"
  end

  check("PS Core version is >= 7") do
    r = ps_core("$PSVersionTable")
    r.result["PSVersion"]["Major"] >= 7
  end

  check("Reports .NET 10 runtime") do
    r = ps_core("[System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription")
    r.result =~ /\.NET 10\./i
  end

  check("Returns a string") do
    r = ps_core("'hello from net10'")
    r.result == "hello from net10"
  end

  check("Returns integer 42") do
    r = ps_core("42")
    r.result == 42
  end

  check("Returns boolean true") do
    r = ps_core("$true")
    r.result == true
  end

  check("Returns boolean false") do
    r = ps_core("$false")
    r.result == false
  end

  check("Returns an array") do
    r = ps_core("@(10, 20, 30)")
    Array(r.result).sort == [10, 20, 30]
  end

  check("Returns a hashtable as a Ruby hash") do
    r = ps_core("@{ Edition = 'Core'; Engine = '.NET10' }")
    r.result["Edition"] == "Core" && r.result["Engine"] == ".NET10"
  end

  check("Handles multi-line script") do
    r = ps_core("$s = 0\n1..10 | ForEach-Object { $s += $_ }\n$s")
    r.result == 55
  end

  check("Captures non-terminating error in .errors") do
    r = ps_core("Write-Error 'net10 error test'")
    r.error? && r.errors.first.include?("net10 error test")
  end

  check("error? is false when no errors") do
    r = ps_core("'clean'")
    !r.error?
  end

  check("Captures verbose output") do
    r = ps_core("Write-Verbose 'net10 verbose' -Verbose")
    r.verbose.join.include?("net10 verbose")
  end

  check("String interpolation works") do
    r = ps_core('"Net10 result: $( 6 * 7 )"')
    r.result == "Net10 result: 42"
  end

  check("env:PROCESSOR_ARCHITECTURE is accessible") do
    r = ps_core("$env:PROCESSOR_ARCHITECTURE")
    r.result =~ /AMD64|x86|ARM64/i
  end

  check("Select-Object returns a typed hash") do
    r = ps_core("Get-Process -Id $PID | Select-Object Id, ProcessName")
    r.result["Id"].is_a?(Integer) && !r.result["ProcessName"].to_s.empty?
  end

  check("Timeout: fast script completes within 5 seconds") do
    t = Time.now
    r = ps_core("'fast'", timeout: 10)
    (Time.now - t) < 5 && r.result == "fast"
  end

  check("Timeout: slow script raises or errors (1s timeout)") do

    r = ps_core("Start-Sleep -Seconds 30", timeout: 1)
    r.error?
  rescue => _e
    true

  end

  check("Unknown command captured as error (not exception)") do
    r = ps_core("this-cmd-xyz-does-not-exist")
    r.error? && r.errors.first =~ /not recognized|CommandNotFoundException/i
  end

  check("DOTNET_ROOT env is restored after execution") do
    saved = ENV["DOTNET_ROOT"]
    ps_core("'test'")
    ENV["DOTNET_ROOT"] == saved
  end
else
  puts "  #{SKIP} All NET10 tests — DLL not found"
  $skips += 15
end

# ---------------------------------------------------------------------------
# Cross-DLL isolation
# ---------------------------------------------------------------------------

if net481_present && net10_present
  section("Cross-DLL isolation")

  check("Both interpreters run sequentially without state bleed") do
    r1 = ps481("$PSVersionTable")
    r2 = ps_core("$PSVersionTable")
    r1.result["PSEdition"] == "Desktop" && r2.result["PSEdition"] == "Core"
  end

  check("Variables do not persist across Windows PowerShell calls (fresh runspace)") do
    ps481("$global:SmokeTestVar = 'was-set'")
    r = ps481("$global:SmokeTestVar")
    # NET481 uses PowerShell.Create() — fresh runspace per call, no shared state.
    # Unset $null is suppressed in the PS pipeline so ConvertTo-Json gets no input;
    # the wrapper returns {} (empty hash), not "was-set" from the previous call.
    r.result != "was-set"
  end

  check("Variables do not persist across PowerShell Core calls (fresh runspace)") do
    ps_core("$global:SmokeTestVar = 'was-set'")
    r = ps_core("$global:SmokeTestVar")
    r.result.nil?
  end
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

puts "\n#{"=" * 60}"
total = $passes + $failures + $skips
puts "Results: #{$passes}/#{total - $skips} passed, #{$failures} failed, #{$skips} skipped"
puts "=" * 60

if $failures > 0
  puts "\n#{FAIL} Smoke test FAILED — #{$failures} test(s) did not pass."
  exit 1
else
  puts "\n#{PASS} All smoke tests passed."
  exit 0
end

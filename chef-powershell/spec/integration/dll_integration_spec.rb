#
# Author:: John McCrae (<jmccrae@chef.io>)
# Copyright:: Copyright (c) 2025 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.
# License:: Apache License, Version 2.0
#
# Integration tests that exercise the actual built DLL binaries.
#
# Usage:
#   Set CHEF_POWERSHELL_BIN to the bin/ directory of the built Hab package, e.g.:
#     $env:CHEF_POWERSHELL_BIN = "C:\hab\pkgs\chef\chef-powershell-shim\X.Y.Z\timestamp\bin"
#   Then run:
#     rspec spec/integration/dll_integration_spec.rb
#
# If CHEF_POWERSHELL_BIN is not set, the spec falls back to the gem's own bin/ruby_bin_folder
# (useful when running from a fully-installed gem).

# Snapshot CHEF_POWERSHELL_BIN *before* require "chef-powershell", because
# powershell_exec.rb unconditionally overwrites it with the gem's own bin path
# at module load time.
_hab_bin_override = ENV["CHEF_POWERSHELL_BIN"].dup if ENV["CHEF_POWERSHELL_BIN"] && !ENV["CHEF_POWERSHELL_BIN"].empty?

require "chef-powershell"

# Determine the DLL root directory. Prefer env override so CI/smoke testing
# can point directly at a freshly built Hab package without installing the gem.
DLL_BIN_DIR = if _hab_bin_override
                File.expand_path(_hab_bin_override)
              else
                File.join(Gem.loaded_specs["chef-powershell"].full_gem_path,
                          "bin", "ruby_bin_folder", ENV.fetch("PROCESSOR_ARCHITECTURE", "AMD64"))
              end.freeze

NET481_DLL  = File.join(DLL_BIN_DIR, "Chef.PowerShell.Wrapper.dll").freeze
NET10_DLL   = File.join(DLL_BIN_DIR, "shared", "Microsoft.NETCore.App", "10.0.0",
                        "Chef.PowerShell.Wrapper.Core.dll").freeze

# Re-pin CHEF_POWERSHELL_BIN to the Hab package dir so the C++/CLI assembly
# resolver (currentDomain_AssemblyResolve in Wrapper.cpp) finds Chef.PowerShell.dll
# in the right place. powershell_exec.rb overwrote it with the gem's own path.
ENV["CHEF_POWERSHELL_BIN"] = DLL_BIN_DIR

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run a script via the raw PowerShell (net481) DLL, bypassing gem path logic.
def raw_powershell(script, timeout: -1)
  orig_bin = ENV["CHEF_POWERSHELL_BIN"]
  ENV["CHEF_POWERSHELL_BIN"] = DLL_BIN_DIR
  ps = ChefPowerShell::PowerShell.allocate
  ps.instance_variable_set(:@powershell_dll, NET481_DLL)
  ps.send(:exec, script, timeout: timeout)
  ps
ensure
  ENV["CHEF_POWERSHELL_BIN"] = orig_bin
end

# Run a script via the raw Pwsh (net10) DLL, bypassing gem path logic.
def raw_pwsh(script, timeout: -1)
  orig_bin      = ENV["CHEF_POWERSHELL_BIN"]
  orig_dml      = ENV["DOTNET_MULTILEVEL_LOOKUP"]
  orig_root     = ENV["DOTNET_ROOT"]
  orig_root_x86 = ENV["DOTNET_ROOT(x86)"]

  ENV["CHEF_POWERSHELL_BIN"]      = DLL_BIN_DIR
  ENV["DOTNET_MULTILEVEL_LOOKUP"] = "0"
  ENV["DOTNET_ROOT"]              = DLL_BIN_DIR
  ENV["DOTNET_ROOT(x86)"]         = DLL_BIN_DIR

  ps = ChefPowerShell::Pwsh.allocate
  ps.instance_variable_set(:@powershell_dll, NET10_DLL)
  # Must call PowerShell#exec directly — Pwsh#exec overrides it and unconditionally
  # resets @powershell_dll to the gem's bundled path before calling super.
  ChefPowerShell::PowerShell.instance_method(:exec).bind(ps).call(script, timeout: timeout)
  ps
ensure
  ENV["CHEF_POWERSHELL_BIN"]      = orig_bin
  ENV["DOTNET_MULTILEVEL_LOOKUP"] = orig_dml
  ENV["DOTNET_ROOT"]              = orig_root
  ENV["DOTNET_ROOT(x86)"]         = orig_root_x86
end

# ---------------------------------------------------------------------------
# Shared behaviour
# ---------------------------------------------------------------------------

RSpec.shared_examples "a working powershell engine" do |runner_proc|
  let(:run) { runner_proc }

  # -- basic sanity ----------------------------------------------------------

  it "returns a result for a trivial script" do
    result = run.call("1 + 1")
    expect(result.errors).to be_empty
    expect(result.result).to eq(2)
  end

  it "returns a string result" do
    result = run.call("'hello from powershell'")
    expect(result.errors).to be_empty
    expect(result.result).to eq("hello from powershell")
  end

  it "returns a boolean true" do
    result = run.call("$true")
    expect(result.errors).to be_empty
    expect(result.result).to be true
  end

  it "returns a boolean false" do
    result = run.call("$false")
    expect(result.errors).to be_empty
    expect(result.result).to be false
  end

  it "returns an integer" do
    result = run.call("42")
    expect(result.errors).to be_empty
    expect(result.result).to eq(42)
  end

  it "returns a float" do
    result = run.call("3.14")
    expect(result.errors).to be_empty
    expect(result.result).to be_within(0.001).of(3.14)
  end

  # -- collections -----------------------------------------------------------

  it "returns an array of integers" do
    result = run.call("@(1, 2, 3)")
    expect(result.errors).to be_empty
    expect(result.result).to contain_exactly(1, 2, 3)
  end

  it "returns an array of strings" do
    result = run.call("@('alpha', 'beta', 'gamma')")
    expect(result.errors).to be_empty
    expect(result.result).to contain_exactly("alpha", "beta", "gamma")
  end

  it "returns a hashtable as a hash" do
    result = run.call("@{ Name = 'Chef'; Version = '18' }")
    expect(result.errors).to be_empty
    expect(result.result["Name"]).to eq("Chef")
    expect(result.result["Version"]).to eq("18")
  end

  # -- pipeline / multi-value ------------------------------------------------

  it "returns the last value from a pipeline" do
    result = run.call("1; 2; 3")
    expect(result.errors).to be_empty
    # Multiple objects get returned as an array
    expect([result.result].flatten).to include(3)
  end

  it "handles empty output" do
    result = run.call("# just a comment")
    expect(result.errors).to be_empty
    # No PS output → DLL returns EMPTY_JSON_STRING "{}" → Ruby parses to empty hash
    expect(result.result).to eq({})
  end

  # -- error handling --------------------------------------------------------

  it "captures non-terminating errors in .errors" do
    result = run.call("Write-Error 'something went wrong'")
    expect(result.error?).to be true
    expect(result.errors.first).to include("something went wrong")
  end

  it "reports error? false when no errors occurred" do
    result = run.call("'clean run'")
    expect(result.error?).to be false
  end

  it "captures an unknown command as a non-terminating error" do
    result = run.call("this-command-does-not-exist-xyz")
    expect(result.error?).to be true
    expect(result.errors.first).to match(/not recognized|CommandNotFoundException/i)
  end

  it "does not raise on non-terminating errors by default" do
    expect { run.call("Write-Error 'oops'") }.not_to raise_error
  end

  # -- verbose stream --------------------------------------------------------

  it "captures verbose output" do
    result = run.call("Write-Verbose 'verbose message' -Verbose")
    expect(result.verbose).to be_a(Array)
    expect(result.verbose.join).to include("verbose message")
  end

  # -- complex objects -------------------------------------------------------

  it "returns process information as a hash" do
    # Get the current process - always exists
    result = run.call("Get-Process -Id $PID | Select-Object -Property Id, ProcessName")
    expect(result.errors).to be_empty
    expect(result.result["Id"]).to be_a(Integer)
    expect(result.result["ProcessName"]).to be_a(String)
  end

  it "returns environment variable values" do
    result = run.call("$env:PROCESSOR_ARCHITECTURE")
    expect(result.errors).to be_empty
    expect(result.result).to match(/AMD64|x86|ARM64/i)
  end

  it "can perform arithmetic and string operations" do
    result = run.call("$a = 10; $b = 32; \"Result: $($a + $b)\"")
    expect(result.errors).to be_empty
    expect(result.result).to eq("Result: 42")
  end

  it "handles multi-line scripts" do
    script = <<~PS
      $sum = 0
      1..10 | ForEach-Object { $sum += $_ }
      $sum
    PS
    result = run.call(script)
    expect(result.errors).to be_empty
    expect(result.result).to eq(55)
  end

  # -- timeout ---------------------------------------------------------------

  it "completes quickly for a fast script" do
    start = Time.now
    result = run.call("'fast'", timeout: 10)
    elapsed = Time.now - start
    expect(result.result).to eq("fast")
    expect(elapsed).to be < 5
  end

  it "records a timeout as an error (does not raise)" do
    # A 1-second timeout against a 30-second sleep should trigger the guard.
    # The DLL stops the pipeline and appends a message to errors; it does not raise.
    result = run.call("Start-Sleep -Seconds 30", timeout: 1)
    expect(result.error?).to be true
    expect(result.errors.join).to match(/timed out/i)
  end
end

# ---------------------------------------------------------------------------
# DLL presence checks
# ---------------------------------------------------------------------------

RSpec.describe "Built DLL binaries", :windows_only do
  it "NET 4.8.1 wrapper DLL exists at expected path" do
    expect(File.exist?(NET481_DLL)).to be(true),
      "Expected #{NET481_DLL} to exist — set CHEF_POWERSHELL_BIN to the Hab package bin/ dir"
  end

  it ".NET 10 wrapper core DLL exists at expected path" do
    expect(File.exist?(NET10_DLL)).to be(true),
      "Expected #{NET10_DLL} to exist — set CHEF_POWERSHELL_BIN to the Hab package bin/ dir"
  end
end

# ---------------------------------------------------------------------------
# Windows PowerShell (.NET Framework 4.8.1 DLL)
# ---------------------------------------------------------------------------

RSpec.describe "Chef.PowerShell.Wrapper.dll (.NET Framework / Windows PowerShell)", :windows_only do
  before(:all) do
    skip "NET481 DLL not found at #{NET481_DLL}" unless File.exist?(NET481_DLL)
  end

  it "loads the DLL and runs a basic script" do
    result = raw_powershell("$PSVersionTable")
    expect(result.errors).to be_empty
    expect(result.result).to be_a(Hash)
    expect(result.result["PSEdition"]).to eq("Desktop")
  end

  it "reports Windows PowerShell version < 7" do
    result = raw_powershell("$PSVersionTable")
    major = result.result["PSVersion"].to_s.to_i
    expect(major).to be < 7
  end

  include_examples "a working powershell engine", ->(script, **kwargs) { raw_powershell(script, **kwargs) }
end

# ---------------------------------------------------------------------------
# PowerShell Core (.NET 10 DLL)
# ---------------------------------------------------------------------------

RSpec.describe "Chef.PowerShell.Wrapper.Core.dll (.NET 10 / PowerShell Core)", :windows_only do
  before(:all) do
    skip "NET10 DLL not found at #{NET10_DLL}" unless File.exist?(NET10_DLL)
  end

  it "loads the DLL and runs a basic script" do
    result = raw_pwsh("$PSVersionTable")
    expect(result.errors).to be_empty
    expect(result.result).to be_a(Hash)
    expect(result.result["PSEdition"]).to eq("Core")
  end

  it "reports PowerShell Core version >= 7" do
    result = raw_pwsh("$PSVersionTable")
    major = result.result["PSVersion"]["Major"]
    expect(major).to be >= 7
  end

  it "reports .NET runtime version is 10.x" do
    result = raw_pwsh("[System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription")
    expect(result.errors).to be_empty
    expect(result.result).to match(/\.NET 10\./i)
  end

  include_examples "a working powershell engine", ->(script, **kwargs) { raw_pwsh(script, **kwargs) }
end

# ---------------------------------------------------------------------------
# Cross-DLL / isolation tests
# ---------------------------------------------------------------------------

RSpec.describe "DLL isolation", :windows_only do
  before(:all) do
    skip "Both DLLs required" unless File.exist?(NET481_DLL) && File.exist?(NET10_DLL)
  end

  it "can run both interpreters sequentially without state bleed" do
    r1 = raw_powershell("$PSVersionTable")
    r2 = raw_pwsh("$PSVersionTable")
    expect(r1.result["PSEdition"]).to eq("Desktop")
    expect(r2.result["PSEdition"]).to eq("Core")
  end

  it "variables from one execution do not persist to the next" do
    raw_powershell("$global:TestIsolation = 'set-by-first-call'")
    result = raw_powershell("$global:TestIsolation")
    # Each call uses a fresh runspace — variable should not persist
    # DLL returns EMPTY_JSON_STRING ("{}" -> {}) when PS produces no output
    expect(result.result).to eq({})
  end

  it "DOTNET_ROOT env is restored after pwsh execution" do
    original = ENV["DOTNET_ROOT"]
    raw_pwsh("'test'")
    expect(ENV["DOTNET_ROOT"]).to eq(original)
  end
end

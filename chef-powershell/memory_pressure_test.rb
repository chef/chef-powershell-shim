#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Regression test for the class of bug fixed by PRs #187, #196, #205: under memory
# pressure, the buffer the native wrapper used to hand a result back to Ruby could be
# collected/reused before Ruby finished reading it, silently corrupting or truncating
# the payload -- even for values as trivial as a boolean. The fix made the native side
# call back *into* Ruby (StoreResultCallback in lib/chef-powershell/powershell.rb) so
# the bytes are copied into a Ruby string synchronously, while the buffer is still
# guaranteed valid, instead of Ruby reading a raw pointer whenever it got around to it.
#
# This script re-creates the conditions that exposed that bug:
#   - the *process* is put under heavy GC churn (large, constantly-discarded Ruby
#     allocations, plus GC.stress to force a collection around every allocation), and
#   - it is intended to be run inside a memory-constrained container (see
#     .expeditor/local_low_memory_test.ps1), so the .NET/CLR side is also forced to
#     collect aggressively rather than comfortably holding on to short-lived buffers.
#
# It then repeatedly round-trips a variety of payload shapes/sizes (including the
# "trivial" boolean/integer cases from the original bug reports) through both
# interpreters and asserts *exact* equality on every single iteration. Any deviation
# indicates the result buffer was corrupted, truncated, or reused before Ruby captured
# it, i.e. a regression of the original heap-lifetime bug.
#
# Usage:
#   ruby memory_pressure_test.rb [iterations]
#
# Or via environment variable:
#   $env:CHEF_POWERSHELL_BIN = "C:\hab\pkgs\chef\chef-powershell-shim\X.Y.Z\timestamp\bin"
#   ruby memory_pressure_test.rb
#
# Exit code: 0 = all round-trips were exact, 1 = one or more were corrupted/failed.

original_gem_path = Gem.path.dup

begin
  require "bundler/setup"
rescue LoadError, StandardError
  # Fall back to system/already-loaded gems if Bundler is unavailable, or if the
  # committed Gemfile.lock doesn't match what's installed on this particular host
  # (e.g. a bare low-memory container that only has ffi/ffi-yajl installed globally).
  # Even when it ultimately raises, `bundler/setup` replaces Gem.path with just the
  # (possibly gem-less, on a version mismatch) vendor bundle dir as a side effect --
  # restore it so the plain `require`s below can still find system-installed gems.
  Gem.paths = { "GEM_PATH" => original_gem_path.join(File::PATH_SEPARATOR) }
  Gem::Specification.reset
end

BIN_DIR = if ARGV[0] && !ARGV[0].match?(/\A\d+\z/)
            File.expand_path(ARGV[0])
          elsif ENV["CHEF_POWERSHELL_BIN"]
            ENV["CHEF_POWERSHELL_BIN"]
          else
            File.expand_path(File.join("bin", "ruby_bin_folder", ENV.fetch("PROCESSOR_ARCHITECTURE", "AMD64")), __dir__)
          end.freeze

ITERATIONS = (ARGV.find { |a| a.match?(/\A\d+\z/) } || 15).to_i

NET481_DLL = File.join(BIN_DIR, "Chef.PowerShell.Wrapper.dll").freeze
NET10_DLL  = File.join(BIN_DIR, "shared", "Microsoft.NETCore.App", "10.0.0",
  "Chef.PowerShell.Wrapper.Core.dll").freeze

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

# Same trick smoke_test_dlls.rb uses: when running from source (not installed as a
# gem), Gem.loaded_specs["chef-powershell"] is nil, which crashes powershell.rb at
# class-body load time. Register the gemspec manually.
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

class ChefPowerShell
  class Pwsh
    # AddDllDirectory allocates an OS-tracked "cookie" for every call and is never
    # released (there is no matching RemoveDllDirectory call anywhere in this repo).
    # Calling it fresh on every single :pwsh invocation -- as the upstream Pwsh#exec
    # and smoke_test_dlls.rb do -- leaks one of those cookies per call. That's mostly
    # invisible in normal use, but a long-running memory-pressure loop like this one
    # calls Pwsh#exec many times in a tight loop and *will* eventually exhaust the
    # per-process directory table (observed here as a "Failed to register DLL search
    # directory" LoadError, not a crash, so it can't silently corrupt anything -- but
    # it does stop the stress loop short). Work around it here, in the test harness
    # only, by registering each directory at most once per process.
    @registered_dll_dirs = {}

    def exec(script, timeout: -1)
      original_dml      = ENV["DOTNET_MULTILEVEL_LOOKUP"]
      original_root     = ENV["DOTNET_ROOT"]
      original_root_x86 = ENV["DOTNET_ROOT(x86)"]

      ENV["DOTNET_MULTILEVEL_LOOKUP"] = "0"
      ENV["DOTNET_ROOT"]      = BIN_DIR
      ENV["DOTNET_ROOT(x86)"] = BIN_DIR
      @powershell_dll = NET10_DLL

      core_dir = File.dirname(@powershell_dll)
      Kernel32.SetDefaultDllDirectories(Kernel32::LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)
      [BIN_DIR, core_dir].each do |dir|
        next if self.class.instance_variable_get(:@registered_dll_dirs)[dir]

        Kernel32.register_search_directory(dir)
        self.class.instance_variable_get(:@registered_dll_dirs)[dir] = true
      end
      Kernel32.SetDllDirectoryA(core_dir)

      ChefPowerShell::PowerShell.instance_method(:exec).bind(self).call(script, timeout: timeout)
    ensure
      ENV["DOTNET_MULTILEVEL_LOOKUP"] = original_dml
      ENV["DOTNET_ROOT"]      = original_root
      ENV["DOTNET_ROOT(x86)"] = original_root_x86
    end
  end
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

# ---------------------------------------------------------------------------
# Memory pressure helpers
# ---------------------------------------------------------------------------

# GC.stress = true forces a full GC around *every single* Ruby object allocation,
# which is the most thorough way to catch anything relying on a Ruby object's
# memory staying put across a call boundary -- but it can slow execution down by
# multiple orders of magnitude, which isn't practical to run by default (including
# inside an already memory-constrained container). It's opt-in via
# CHEF_POWERSHELL_GC_STRESS=1 for maintainers who want the maximal, slow, "torture
# test" version of this script; the default mode below still forces a full GC
# around every payload round-trip, just not around every single allocation.
EXTREME_GC_STRESS = ENV["CHEF_POWERSHELL_GC_STRESS"] == "1"

def under_gc_pressure
  if EXTREME_GC_STRESS
    original = GC.stress
    GC.stress = true
    begin
      yield
    ensure
      GC.stress = original
    end
  else
    yield
  end
end

# Churn a batch of large, immediately-discarded allocations and force a full,
# immediate GC to simulate a memory-constrained environment applying pressure to
# both the Ruby heap and, indirectly (via reduced available system memory), the
# CLR heap the native wrapper allocates its result buffers from. This runs around
# every payload round-trip (not just every iteration), maximizing the chance a GC
# lands in the window between the native side handing back a result and Ruby
# finishing reading it.
def churn_garbage(chunks: 4, chunk_size: 256 * 1024)
  chunks.times { "x" * chunk_size }
  GC.start(full_mark: true, immediate_sweep: true)
end

# ---------------------------------------------------------------------------
# Harness
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

# Payload matrix: deliberately includes the "trivial" scalar cases called out in the
# original bug reports (bare booleans/integers), plus strings (including multi-byte
# UTF-8, to stress the UTF-16LE -> UTF-8 decode path), arrays, hashes, and a large
# string to stress bigger buffer allocations.
PAYLOADS = [
  ["$true",                                          true],
  ["$false",                                         false],
  ["42",                                              42],
  ["0",                                               0],
  ["-17",                                             -17],
  ["3.14",                                            3.14],
  ["'hello from powershell'",                         "hello from powershell"],
  ["'unicode: héllo wörld 日本語 🎉'", "unicode: héllo wörld 日本語 🎉"],
  ["@(1, 2, 3, 4, 5)",                                [1, 2, 3, 4, 5]],
  ["@{ Name = 'Chef'; Version = '19' }",              { "Name" => "Chef", "Version" => "19" }],
  ["'x' * 20000",                                     nil], # validated separately below (length check)
].freeze

def run_payload_round_trips(run_proc, label)
  PAYLOADS.each do |script, expected|
    # Churn + force a GC immediately before every single call, so a collection is
    # highly likely to land right in the window between the native side handing
    # back the result buffer and Ruby finishing reading it.
    churn_garbage

    if script == "'x' * 20000"
      check("#{label}: large string round-trips intact (20000 chars)") do
        result = run_proc.call("('x' * 20000)")
        result.errors.empty? && result.result.is_a?(String) && result.result.length == 20000 && result.result.chars.uniq == ["x"]
      end
    else
      check("#{label}: #{script.inspect} round-trips as #{expected.inspect}") do
        result = run_proc.call(script)
        result.errors.empty? && result.result == expected
      end
    end
  end
end

net481_present = File.exist?(NET481_DLL)
net10_present  = File.exist?(NET10_DLL)

puts "DLL directory : #{BIN_DIR}"
puts "NET481 DLL    : #{NET481_DLL} (#{net481_present ? "present" : "MISSING"})"
puts "NET10  DLL    : #{NET10_DLL} (#{net10_present ? "present" : "MISSING"})"
puts "Iterations    : #{ITERATIONS}"
puts "GC pressure   : #{EXTREME_GC_STRESS ? "EXTREME (GC.stress=true for the whole run; CHEF_POWERSHELL_GC_STRESS=1)" : "full GC forced before every round-trip (set CHEF_POWERSHELL_GC_STRESS=1 for the slower, more thorough GC.stress mode)"}"

abort "Neither wrapper DLL was found under #{BIN_DIR} -- nothing to test." unless net481_present || net10_present

under_gc_pressure do
  ITERATIONS.times do |i|
    section("Iteration #{i + 1}/#{ITERATIONS}")

    run_payload_round_trips(method(:ps481), ":powershell") if net481_present
    run_payload_round_trips(method(:ps_core), ":pwsh") if net10_present
  end
end

puts "\n#{"=" * 60}"
total = $passes + $failures
puts "Results: #{$passes}/#{total} round-trips exact, #{$failures} corrupted/failed"
puts "=" * 60

if $failures > 0
  puts "\n#{FAIL} Memory pressure test FAILED -- #{$failures} round-trip(s) came back " \
       "corrupted, truncated, or wrong. This is the class of bug fixed in PRs #187/#196/#205."
  exit 1
else
  puts "\n#{PASS} All #{$passes} round-trips survived GC/memory pressure intact."
  exit 0
end

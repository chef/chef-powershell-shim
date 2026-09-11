#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Fault-injection harness: deliberately sabotage chef-powershell in ways a real
# user/CI/machine might (accidentally or otherwise), and verify the result is
# either (a) full resilience -- the sabotage doesn't matter -- or (b) a clean,
# understandable failure (a LoadError with a message telling you what's
# missing), never a silent wrong result or a bare, unexplained error 126.
#
# Every scenario operates on a disposable scratch copy of the gem (and, for
# the stale-gem-version scenario, a disposable GEM_HOME). Your real installed
# chef-powershell-shim / chef-infra-client packages are never modified.
#
# Usage:
#   cd chef-powershell
#   bundle exec ruby chef_gem_break_test.rb
#
# Optional -- also run the "forgot to replace the vendored gem" control
# scenario against a REAL Chef install (destructive to that install; only run
# this inside a disposable container):
#   $env:CHEF_HAB_IDENT   = "chef/chef-infra-client"          # Habitat ident, or
#   $env:CHEF_OMNIBUS_RUBY = "C:\opscode\chef\embedded\bin\ruby.exe"
#   bundle exec ruby chef_gem_break_test.rb
#
# Exit code: 0 = every scenario behaved as expected, 1 = one or more did not.

require "open3"
require "fileutils"
require "tmpdir"
require "tempfile"
require "securerandom"

GEM_ROOT = File.expand_path(__dir__)
ARCH = ENV["PROCESSOR_ARCHITECTURE"] || "AMD64"
GOOD_BIN_DIR = File.join(GEM_ROOT, "bin", "ruby_bin_folder", ARCH)

unless File.directory?(GOOD_BIN_DIR)
  abort "No built DLLs found at #{GOOD_BIN_DIR}. Build/install the Habitat package first (see build_gems.ps1)."
end

PASS = "\e[32mPASS\e[0m"
FAIL = "\e[31mFAIL\e[0m"
SKIP = "\e[33mSKIP\e[0m"
BOLD = "\e[1m"
RESET = "\e[0m"

$results = []

def section(title)
  puts "\n#{BOLD}== #{title} ==#{RESET}"
end

# Records a scenario's verdict. `actual` and `expected` are short symbols
# describing what happened, e.g. :graceful_failure, :success, :confusing_failure.
def record(name, expected:, actual:, detail: nil)
  ok = Array(expected).include?(actual)
  $results << { name: name, ok: ok, expected: expected, actual: actual, detail: detail }
  status = ok ? PASS : FAIL
  puts "  #{status} #{name} (expected: #{Array(expected).join(" or ")}, got: #{actual})"
  puts "       #{detail}" if detail && !ok
end

def skip(name, reason)
  $results << { name: name, ok: true, expected: :skip, actual: :skip, detail: reason }
  puts "  #{SKIP} #{name} (#{reason})"
end

# ---------------------------------------------------------------------------
# Scratch gem root helper -- a disposable copy of this gem's lib/ + gemspec +
# DLLs, so scenarios can freely delete/corrupt files without touching the
# real thing. Registered as a fake Gem::Specification inside the child
# process (same trick smoke_test_dlls.rb uses) so Gem.loaded_specs resolves
# to it exactly like a real installed gem would.
# ---------------------------------------------------------------------------
def make_scratch_gem_root(version: nil)
  root = Dir.mktmpdir("chef_powershell_break_test_")
  FileUtils.cp_r(File.join(GEM_ROOT, "lib"), root)
  FileUtils.cp(File.join(GEM_ROOT, "chef-powershell.gemspec"), root)
  bin_dir = File.join(root, "bin", "ruby_bin_folder", ARCH)
  FileUtils.mkdir_p(File.dirname(bin_dir))
  FileUtils.cp_r(GOOD_BIN_DIR, bin_dir)

  if version
    version_file = File.join(root, "lib", "chef-powershell", "version.rb")
    contents = File.read(version_file).sub(/VERSION = ".*"/, %{VERSION = "#{version}"})
    File.write(version_file, contents)
  end

  yield root, bin_dir if block_given?
  root
ensure
  at_exit { FileUtils.remove_entry(root) if root && File.exist?(root) }
end

# Runs a single interpreter (:powershell or :pwsh) in a fresh `ruby` child process, with
# `gem_root` faked as the activated chef-powershell gem (unless gem_root is nil, e.g. the
# real-GEM_HOME multi-version scenario, which activates gems normally).
#
# One interpreter per process, not both in one script: an unhandled exception inside the
# embedded CLR (e.g. a managed assembly it cannot resolve) can SIGSEGV the whole ruby.exe
# host rather than raising a catchable Ruby exception. Testing both interpreters in a
# single process meant a hard crash in the first silently erased evidence of the second.
def run_interpreter_in_child(interpreter, gem_root:, env: {}, use_bundler: true)
  preamble = <<~RUBY
    require "chef-powershell"
  RUBY

  if gem_root
    preamble = <<~RUBY
      spec = Gem::Specification.load(#{File.join(gem_root, "chef-powershell.gemspec").inspect})
      spec.instance_variable_set(:@full_gem_path, #{gem_root.inspect})
      Gem.loaded_specs["chef-powershell"] = spec
      $LOAD_PATH.unshift(#{File.join(gem_root, "lib").inspect})
      #{preamble}
    RUBY
  end

  code = <<~RUBY
    #{preamble}
    include ChefPowerShell::ChefPowerShellModule::PowerShellExec
    begin
      r = powershell_exec("$PSVersionTable", #{interpreter.inspect})
      result = r.error? ? "error: \#{r.errors.first}" : "ok:\#{r.result["PSEdition"]}"
    rescue Exception => e
      result = "raised:\#{e.class}:\#{e.message.lines.first.to_s.strip}"
    end
    STDOUT.puts "RESULT #{interpreter}=\#{result}"
    STDOUT.flush
  RUBY

  # LoadError/ScriptError aren't StandardError, so the child's own `rescue Exception`
  # above catches them -- but don't let ambient vars from *this* dev shell (leftover
  # CHEF_POWERSHELL_BIN/DOTNET_ROOT/RUBYOPT from earlier manual testing) leak into a
  # scenario that didn't ask for them. nil explicitly unsets a var for the child.
  base_env = {
    "BUNDLE_GEMFILE" => File.join(GEM_ROOT, "Gemfile"),
    "CHEF_POWERSHELL_BIN" => nil,
    "DOTNET_ROOT" => nil,
    "DOTNET_ROOT(x86)" => nil,
    "DOTNET_MULTILEVEL_LOOKUP" => nil,
    "RUBYOPT" => nil,
  }
  full_env = base_env.merge(env)
  # Pass the code via a temp file, not `-e <code>` -- a multi-line string as a single
  # argument to `bundle` (a .bat/.cmd wrapper on Windows) does not survive process
  # creation reliably and silently produces an empty, exit-0 no-op child process.
  Tempfile.create(["chef_gem_break_test_child", ".rb"]) do |file|
    file.write(code)
    file.flush
    # Bypass Bundler for scenarios that need real RubyGems version-resolution behavior
    # (highest installed version wins) -- `bundle exec` ignores GEM_HOME/GEM_PATH overrides
    # and resolves chef-powershell from this repo's own Gemfile.lock regardless.
    cmd = use_bundler ? ["bundle", "exec", "ruby", file.path] : ["ruby", file.path]
    stdout, stderr, status = Open3.capture3(full_env, *cmd, chdir: GEM_ROOT)
    return { stdout: stdout, stderr: stderr, status: status }
  end
end

def outcome_for(interpreter, run)
  line = run[:stdout].lines.find { |l| l.start_with?("RESULT #{interpreter}=") }
  return :crashed unless line

  value = line.split("=", 2).last.strip
  return :succeeded if value.start_with?("ok:")
  return :handled_error if value.start_with?("error:")
  return :raised_load_error if value.start_with?("raised:LoadError")

  :raised_other
end


# ---------------------------------------------------------------------------
# Category 1: corrupted / partial DLL layout
# ---------------------------------------------------------------------------
section("Corrupted / partial DLL layout")

{
  "shared/Microsoft.NETCore.App/10.0.0 entirely missing (simulates an incomplete .NET 10 publish)" => {
    corrupt: ->(bin_dir) { FileUtils.rm_rf(File.join(bin_dir, "shared")) },
    expect_pwsh: :raised_load_error,
    expect_powershell: :succeeded,
  },
  "host/fxr/10.0.0/hostfxr.dll missing" => {
    corrupt: ->(bin_dir) { FileUtils.rm_rf(File.join(bin_dir, "host")) },
    expect_pwsh: %i{raised_load_error raised_other crashed},
    expect_powershell: :succeeded,
  },
  "Chef.PowerShell.Wrapper.dll (net481) missing" => {
    corrupt: ->(bin_dir) { FileUtils.rm_f(File.join(bin_dir, "Chef.Powershell.Wrapper.dll")) },
    expect_pwsh: :succeeded,
    expect_powershell: %i{raised_load_error raised_other crashed},
  },
  "vcruntime140.dll (CRT dependency) missing, wrapper DLLs still present" => {
    corrupt: ->(bin_dir) { FileUtils.rm_f(File.join(bin_dir, "vcruntime140.dll")) },
    expect_pwsh: %i{raised_load_error raised_other crashed},
    expect_powershell: %i{raised_load_error raised_other crashed},
  },
}.each do |name, scenario|
  root = make_scratch_gem_root
  bin_dir = File.join(root, "bin", "ruby_bin_folder", ARCH)
  scenario[:corrupt].call(bin_dir)

  pwsh_run = run_interpreter_in_child(:pwsh, gem_root: root)
  powershell_run = run_interpreter_in_child(:powershell, gem_root: root)
  actual_pwsh = outcome_for("pwsh", pwsh_run)
  actual_powershell = outcome_for("powershell", powershell_run)

  record("#{name} -- :pwsh", expected: scenario[:expect_pwsh], actual: actual_pwsh,
    detail: "stderr: #{pwsh_run[:stderr].lines.first(3).join.strip}")
  record("#{name} -- :powershell", expected: scenario[:expect_powershell], actual: actual_powershell,
    detail: "stderr: #{powershell_run[:stderr].lines.first(3).join.strip}")

  # A confusing error 126 with no diagnostic is the worst outcome -- flag it loudly even
  # though :raised_other is technically an "acceptable" catch-all above.
  if actual_pwsh == :raised_other && !pwsh_run[:stdout].include?("not found")
    puts "       #{FAIL} note: :pwsh failure did not mention a missing file by name -- this would look like an unexplained error 126 to a user"
  end
  if actual_powershell == :raised_other && !powershell_run[:stdout].include?("not found")
    puts "       #{FAIL} note: :powershell failure did not mention a missing file by name -- this would look like an unexplained error 126 to a user"
  end
end

# ---------------------------------------------------------------------------
# Category 2: hostile environment variables
# ---------------------------------------------------------------------------
section("Hostile environment variables")

begin
  root = make_scratch_gem_root
  run = run_interpreter_in_child(:pwsh, gem_root: root, env: { "DOTNET_ROOT" => "C:\\this\\does\\not\\exist" })
  record("Bogus pre-existing DOTNET_ROOT is overridden during :pwsh exec",
    expected: :succeeded, actual: outcome_for("pwsh", run), detail: run[:stderr])
end

begin
  root = make_scratch_gem_root
  env = { "CHEF_POWERSHELL_BIN" => "C:\\this\\does\\not\\exist\\either" }
  pwsh_run = run_interpreter_in_child(:pwsh, gem_root: root, env: env)
  powershell_run = run_interpreter_in_child(:powershell, gem_root: root, env: env)
  record("Bogus CHEF_POWERSHELL_BIN is ignored when a valid gem_spec path exists (:pwsh)",
    expected: :succeeded, actual: outcome_for("pwsh", pwsh_run), detail: pwsh_run[:stderr])
  record("Bogus CHEF_POWERSHELL_BIN is ignored when a valid gem_spec path exists (:powershell)",
    expected: :succeeded, actual: outcome_for("powershell", powershell_run), detail: powershell_run[:stderr])
end

begin
  root = make_scratch_gem_root
  run = run_interpreter_in_child(:pwsh, gem_root: root, env: { "PROCESSOR_ARCHITECTURE" => "" })
  record("Blank PROCESSOR_ARCHITECTURE falls back to AMD64 default (:pwsh)",
    expected: :succeeded, actual: outcome_for("pwsh", run), detail: run[:stderr])
end

# ---------------------------------------------------------------------------
# Category 3: stale / multiple installed gem versions shadowing each other
# ---------------------------------------------------------------------------
section("Stale / multiple installed gem versions")

begin
  gem_home = Dir.mktmpdir("chef_powershell_break_test_gemhome_")
  good_gem_file = Dir.glob(File.join(GEM_ROOT, "chef-powershell-*.gem")).first
  unless good_gem_file
    Dir.chdir(GEM_ROOT) { system("gem", "build", "chef-powershell.gemspec", out: File::NULL, err: File::NULL) }
    good_gem_file = Dir.glob(File.join(GEM_ROOT, "chef-powershell-*.gem")).first
  end

  evil_source = Dir.mktmpdir("chef_powershell_break_test_evil_src_")
  FileUtils.cp_r(File.join(GEM_ROOT, "lib"), evil_source)
  FileUtils.cp_r(File.join(GEM_ROOT, "ext"), evil_source)
  FileUtils.cp(File.join(GEM_ROOT, "chef-powershell.gemspec"), evil_source)
  FileUtils.cp(File.join(GEM_ROOT, "Rakefile"), evil_source)
  FileUtils.cp(File.join(GEM_ROOT, "LICENSE"), evil_source)
  FileUtils.mkdir_p(File.join(evil_source, "bin")) # no DLLs at all -- simulates a broken/incomplete install
  evil_version_file = File.join(evil_source, "lib", "chef-powershell", "version.rb")
  File.write(evil_version_file, File.read(evil_version_file).sub(/VERSION = ".*"/, 'VERSION = "99.0.0"'))
  evil_gem_file = nil
  Dir.chdir(evil_source) do
    system("gem", "build", "chef-powershell.gemspec", out: File::NULL, err: File::NULL)
    evil_gem_file = Dir.glob(File.join(evil_source, "chef-powershell-*.gem")).first
  end

  if good_gem_file && evil_gem_file
    system("gem", "install", good_gem_file, "--install-dir", gem_home, "--no-document", "--force", "--ignore-dependencies", out: File::NULL, err: File::NULL)
    system("gem", "install", evil_gem_file, "--install-dir", gem_home, "--no-document", "--force", "--ignore-dependencies", out: File::NULL, err: File::NULL)

    # Reuse this repo's own vendored ffi/ffi_yajl instead of hitting the network, and
    # bypass Bundler (which would otherwise ignore GEM_HOME/GEM_PATH and resolve
    # chef-powershell from this repo's own Gemfile.lock regardless of these overrides).
    ruby_version = RbConfig::CONFIG["ruby_version"]
    vendor_gems = File.join(GEM_ROOT, "vendor", "bundle", "ruby", ruby_version)
    shadow_env = {
      "GEM_HOME" => gem_home,
      "GEM_PATH" => "#{gem_home};#{vendor_gems}",
      "BUNDLE_GEMFILE" => nil,
    }
    pwsh_run = run_interpreter_in_child(:pwsh, gem_root: nil, env: shadow_env, use_bundler: false)
    powershell_run = run_interpreter_in_child(:powershell, gem_root: nil, env: shadow_env, use_bundler: false)
    # A plain `require` with two installed versions activates the highest (99.0.0, the broken
    # one) -- the desired behavior is a clear, loud LoadError, not a silent bad result.
    record("Higher-numbered but DLL-less gem shadows the real one -- fails loudly instead of silently (:pwsh)",
      expected: %i{raised_load_error raised_other}, actual: outcome_for("pwsh", pwsh_run), detail: pwsh_run[:stderr])
    record("Higher-numbered but DLL-less gem shadows the real one -- fails loudly instead of silently (:powershell)",
      expected: %i{raised_load_error raised_other}, actual: outcome_for("powershell", powershell_run), detail: powershell_run[:stderr])
  else
    skip("Stale gem version shadowing", "could not build good and/or evil .gem files")
  end
ensure
  FileUtils.remove_entry(gem_home) if gem_home && File.exist?(gem_home)
  FileUtils.remove_entry(evil_source) if evil_source && File.exist?(evil_source)
  Dir.glob(File.join(GEM_ROOT, "chef-powershell-99.0.0.gem")).each { |f| FileUtils.rm_f(f) }
end

# ---------------------------------------------------------------------------
# Category 4 (control): forgetting to replace Chef's vendored gem entirely.
# Destructive to a real Chef install -- only runs against a Chef environment
# you explicitly point at, and is meant to be run inside a disposable
# container. This is the ORIGINAL error-126 bug: it is EXPECTED to fail here.
# ---------------------------------------------------------------------------
section("Forgot to replace Chef's vendored/bundled gem (control case)")

if ENV["CHEF_HAB_IDENT"]
  ident = ENV["CHEF_HAB_IDENT"]
  stdout, stderr, _status = Open3.capture3("hab", "pkg", "exec", ident, "ruby", "-e",
    "require 'chef-powershell'; include ChefPowerShell::ChefPowerShellModule::PowerShellExec; " \
    "r = powershell_exec('$PSVersionTable', :pwsh); puts \"RESULT pwsh=ok\"")
  actual = stdout.include?("RESULT pwsh=ok") ? :succeeded : :raised_or_crashed
  record("Untouched Habitat install (#{ident}) reproduces the original error-126 bug",
    expected: :raised_or_crashed, actual: actual, detail: stderr.lines.first(5).join.strip)
elsif ENV["CHEF_OMNIBUS_RUBY"]
  ruby_exe = ENV["CHEF_OMNIBUS_RUBY"]
  stdout, stderr, _status = Open3.capture3(ruby_exe, "-e",
    "require 'chef-powershell'; include ChefPowerShell::ChefPowerShellModule::PowerShellExec; " \
    "r = powershell_exec('$PSVersionTable', :pwsh); puts \"RESULT pwsh=ok\"")
  actual = stdout.include?("RESULT pwsh=ok") ? :succeeded : :raised_or_crashed
  record("Untouched Omnibus install (#{ruby_exe}) -- gem version currently active",
    expected: %i{succeeded raised_or_crashed}, actual: actual, detail: stderr.lines.first(5).join.strip)
else
  skip("Forgot to replace vendored/bundled gem",
    "set CHEF_HAB_IDENT or CHEF_OMNIBUS_RUBY to a real (disposable!) Chef install to run this")
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section("Summary")
failures = $results.reject { |r| r[:ok] }
puts "#{$results.count { |r| r[:actual] == :skip }} skipped, #{$results.size - failures.size - $results.count { |r| r[:actual] == :skip }} passed, #{failures.size} failed"
exit(failures.empty? ? 0 : 1)

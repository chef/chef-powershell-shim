#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Integration test run against a real Chef installation (Omnibus or Habitat) to prove
# that THIS repo's chef-powershell code (not whatever version Chef vendored/bundled at
# its own build time) is what actually executes powershell_exec.
#
# This is intentionally invoked through Chef's own Ruby (embedded/Habitat), with this
# repo's lib/ forced ahead of Chef's bundled copy on the load path (see build_gems.ps1),
# so it reproduces exactly what a real Chef run would do.
#
# Usage: ruby chef_gem_integration_test.rb
# Exit code: 0 = all checks passed, 1 = one or more failures

require "chef-powershell"
include ChefPowerShell::ChefPowerShellModule::PowerShellExec

failures = []

spec = Gem.loaded_specs["chef-powershell"]
puts "Loaded chef-powershell #{spec&.version} from #{spec&.full_gem_path || "$LOAD_PATH override"}"

begin
  result = powershell_exec("$PSVersionTable", :powershell)
  if result.result["PSEdition"] != "Desktop"
    failures << ":powershell PSEdition was #{result.result["PSEdition"].inspect}, expected \"Desktop\""
  end
  puts ":powershell PSEdition: #{result.result["PSEdition"]}"
rescue => e
  failures << ":powershell raised #{e.class}: #{e.message}"
end

begin
  result = powershell_exec("$PSVersionTable", :pwsh)
  if result.result["PSEdition"] != "Core"
    failures << ":pwsh PSEdition was #{result.result["PSEdition"].inspect}, expected \"Core\""
  end
  major = result.result["PSVersion"]["Major"]
  failures << ":pwsh PSVersion.Major was #{major.inspect}, expected >= 7" unless major.to_i >= 7
  puts ":pwsh PSEdition: #{result.result["PSEdition"]}, PSVersion.Major: #{major}"
rescue => e
  failures << ":pwsh raised #{e.class}: #{e.message}"
end

begin
  result = powershell_exec("this-command-does-not-exist")
  failures << "non-terminating error was not captured in .error?" unless result.error?
  puts "Non-terminating error captured: #{result.error?}"
rescue => e
  failures << "non-terminating error case raised #{e.class}: #{e.message}"
end

begin
  powershell_exec!("throw 'boom'")
  failures << "powershell_exec! did not raise for a terminating error"
rescue ChefPowerShell::PowerShellExceptions::PowerShellCommandFailed
  puts "powershell_exec! raised PowerShellCommandFailed as expected"
rescue => e
  failures << "powershell_exec! raised the wrong error class #{e.class}: #{e.message}"
end

if failures.empty?
  puts "All chef-powershell integration checks passed"
  exit 0
else
  puts "Chef-powershell integration checks FAILED:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end

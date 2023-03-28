#
# Author:: Stuart Preston (<stuart@chef.io>)
# Copyright:: Copyright (c) Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "ffi" unless defined?(FFI)
autoload :FFI_Yajl, "ffi_yajl"
require_relative "exceptions"
require_relative "unicode"

class ChefPowerShell
  class PowerShell

    attr_reader :result
    attr_reader :errors
    attr_reader :verbose

    # Run a command under PowerShell via FFI
    # This implementation requires the managed dll and native wrapper to be in the library search
    # path on Windows (i.e. c:\windows\system32 or in the same location as ruby.exe).
    #
    # Requires: .NET Framework 4.0 or higher on the target machine.
    #
    # @param script [String] script to run
    # @param timeout [Integer, nil] timeout in seconds.
    # @return [Object] output
    def initialize(script, timeout: -1)
      # This Powershell DLL source lives here: https://github.com/chef/chef-powershell-shim
      # Every merge into that repo triggers a Habitat build and verification process.
      # There is no mechanism to build a Windows gem file. It has to be done manually running manual_gem_release.ps1
      # Bundle install ensures that the correct architecture binaries are installed into the path.
      @powershell_dll = Gem.loaded_specs["chef-powershell"].full_gem_path + "/bin/ruby_bin_folder/#{ENV["PROCESSOR_ARCHITECTURE"]}/Chef.PowerShell.Wrapper.dll"
      timeout = -1 if timeout.nil? || timeout == 0

      exec(script, timeout: timeout)
    end

    def power_mod
      ChefPowerShell::PowerShell::PowerShellMod
    end
    #
    # Was there an error running the command
    #
    # @return [Boolean]
    #
    def error?
      errors.count > 0
    end

    #
    # @raise [ChefPowerShell::PowerShellExceptions::PowerShellCommandFailed] raise if the command failed
    #
    def error!
      raise ChefPowerShell::PowerShellExceptions::PowerShellCommandFailed, "Unexpected exit in PowerShell command: #{@errors}" if error?
    end

    module PowerShellMod
      extend FFI::Library

      def self.load_powershell_dll(powershell_dll)
        @dlls ||= []
        return if @dlls.include?(powershell_dll)
        ffi_lib powershell_dll
        @dlls << powershell_dll
      end

      def self.do_work(ps_command, p_output, memory_size = MEMORY_SIZE, timeout = -1)
        attach_function(:execute_powershell, :ExecuteScript, %i{string pointer int int}, :pointer) unless method_defined?(:execute_powershell)
        execute_powershell(ps_command, p_output, memory_size, timeout)
      end
    end

    MEMORY_SIZE = 1024 * 1024 * 10
    private

    def exec(script, timeout: -1)
      power_mod.load_powershell_dll(@powershell_dll)
      begin
        p_output = FFI::MemoryPointer.new(:uchar, MEMORY_SIZE)
        execution = power_mod.do_work(script, p_output, MEMORY_SIZE, timeout)
        output = execution.read_utf16string
        hashed_outcome = FFI_Yajl::Parser.parse(output)

        @result = FFI_Yajl::Parser.parse(hashed_outcome["result"])
        @errors = hashed_outcome["errors"]
        @verbose = hashed_outcome["verbose"]
      rescue => e
        if File.exist?("C:\\chef-powershell-output.txt")
          message=[e.inspect, File.read("C:\\chef-powershell-output.txt")].join("\n")
          raise message
        else
          raise
        end
      ensure
        p_output.free
      end
    end
  end
end

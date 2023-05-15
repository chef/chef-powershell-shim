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
      exec(script, timeout: timeout)
    end

    #
    # Was there an error running the command
    #
    # @return [Boolean]
    #
    def error?
      return true if errors.count > 0

      false
    end

    #
    # @raise [ChefPowerShell::PowerShellExceptions::PowerShellCommandFailed] raise if the command failed
    #
    def error!
      raise ChefPowerShell::PowerShellExceptions::PowerShellCommandFailed, "Unexpected exit in PowerShell command: #{@errors}" if error?
    end

    module PowerMod
      extend FFI::Library
      # FFI requires attaching to modules, not classes, so we need to
      # have a module here. The module level variables *could* be refactored
      # out here, but still 100% of the work still goes through the module.
      @@powershell_dll = Gem.loaded_specs["chef-powershell"].full_gem_path + "/bin/ruby_bin_folder/#{ENV["PROCESSOR_ARCHITECTURE"]}/Chef.PowerShell.Wrapper.dll"
      @@ps_command = ""
      @@ps_timeout = -1

      AllocateCallback = FFI::Function.new(:pointer, [:size_t]) do |size|
        # Capture the pointer here so that Ruby knows that it is an
        # FFI::MemoryPointer that can receive &.free. If you try to
        # free the pointer from execute_powershell, Ruby will not have
        # access to the type information and will core dump spectacularly.
        @@pointer = FFI::MemoryPointer.new(:uchar, size).tap { |ptr| STDERR.puts ptr.inspect }
      end

      def self.free_pointer
        @@pointer&.free
        @@pointer = nil
      end

      def self.set_ps_dll(value)
        @@powershell_dll = value
      end

      def self.set_ps_command(value)
        @@ps_command = value
      end

      def self.set_ps_timeout(value)
        @@ps_timeout = value
      end

      def self.do_work
        ffi_lib @@powershell_dll
        attach_function :execute_powershell, :ExecuteScript, %i{string int pointer}, :pointer

        execute_powershell(@@ps_command, @@ps_timeout, AllocateCallback)
      end
    end

    private

    def exec(script, timeout: -1)
      timeout = -1 if timeout == 0 || timeout.nil?

      # Set it every time because the test suite actually switches
      # the DLL pointed to.
      PowerMod.set_ps_dll(@powershell_dll)
      PowerMod.set_ps_timeout(timeout)

      PowerMod.set_ps_command(script)

      begin
        execution = PowerMod.do_work

        if File.exist?("C:\\chef-powershell-output.txt")
          STDERR.puts "DEBUG Powershell output:"
          STDERR.puts File.read("C:\\chef-powershell-output.txt")
          STDERR.puts "END DEBUG Powershell output"
        end

        output = execution.read_utf16string
        hashed_outcome = FFI_Yajl::Parser.parse(output)
        @result = FFI_Yajl::Parser.parse(hashed_outcome["result"])
        @errors = hashed_outcome["errors"]
        @verbose = hashed_outcome["verbose"]
      rescue => e
        if File.exist?("C:\\chef-powershell-output.txt")
          STDERR.puts "RESCUE Powershell output:"
          message=[e.inspect, e.backtrace.join(';'), File.read("C:\\chef-powershell-output.txt")].join("\n")
          STDERR.puts "END RESCUE Powershell output:"
          raise message
        else
          raise
        end
      end
    ensure
      PowerMod.free_pointer
    end
  end
end

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
      @@powershell_dll = Gem.loaded_specs["chef-powershell"].full_gem_path + "/bin/ruby_bin_folder/#{ENV["PROCESSOR_ARCHITECTURE"]}/Chef.PowerShell.Wrapper.dll"
      @@ps_command = ""
      @@ps_timeout = -1

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
        attach_function :execute_powershell, :ExecuteScript, %i{string int}, :pointer
        execute_powershell(@@ps_command, @@ps_timeout)
      end
    end

    private

    def exec(script, timeout: -1)
      timeout = -1 if timeout == 0 || timeout.nil?
      PowerMod.set_ps_dll(@powershell_dll)
      PowerMod.set_ps_timeout(timeout)
      PowerMod.set_ps_command(script)

=begin
      # using instance variables for execution and output because I suspect
      # the data is being prematurely marked for garbage collection
      @last_execution = PowerMod.do_work
      @last_output = @last_execution.read_utf16string
      hashed_outcome = FFI_Yajl::Parser.parse(@last_output)
      @result = FFI_Yajl::Parser.parse(hashed_outcome["result"])
      @errors = hashed_outcome["errors"]
      @verbose = hashed_outcome["verbose"]

      loop do
        execution = PowerMod.do_work
        output = execution.read_utf16string
        hashed_outcome = FFI_Yajl::Parser.parse(output)
        @result = FFI_Yajl::Parser.parse(hashed_outcome["result"])
        @errors = hashed_outcome["errors"]
        @verbose = hashed_outcome["verbose"]
        break
      end
=end
      is_retry = false
      loop do
        begin
          execution = PowerMod.do_work

          output = execution.read_utf16string
          hashed_outcome = FFI_Yajl::Parser.parse(output)
          @result = FFI_Yajl::Parser.parse(hashed_outcome["result"])
          @errors = hashed_outcome["errors"]
          @verbose = hashed_outcome["verbose"]
          break
        rescue ArgumentError => e
          raise if is_retry || e.message !~ /Invalid Memory object/
          puts "<<== ArgumentError/Invalid Memory object, retrying ==>>"
          is_retry = true
        rescue Encoding::InvalidByteSequenceError
          raise if is_retry
          puts "<<== Encoding::InvalidByteSequenceError, retrying ==>>"
          is_retry = true
        rescue NoMethodError
          raise if is_retry || !hashed_outcome.nil?
          puts "<<== NoMethodError, retrying ==>>"
          is_retry = true
        rescue FFI_Yajl::ParseError
          raise if is_retry
          puts "<<== FFI_Yajl::ParseError, retrying ==>>"
          is_retry = true
        end
      end
    end
  end
end

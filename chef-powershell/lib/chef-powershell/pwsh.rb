#
# Author:: Matt Wrock (<mwrock@chef.io>)
# Copyright:: Copyright (c) 2018-2025 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.
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

class ChefPowerShell
  class Pwsh < ChefPowerShell::PowerShell
    # Run a command under pwsh (powershell core) via FFI
    # This implementation requires the managed dll, native wrapper and a
    # published, self contained dotnet core directory tree to exist in the
    # bindir directory.
    #
    # @param script [String] script to run
    # @param timeout [Integer, nil] timeout in seconds.
    # @return [Object] output
    def initialize(script, timeout: -1)
      @dll = Pwsh.dll
      super
    end

    protected

    def exec(script, timeout: -1)
      # Note that we need to override the location of the shared dotnet core library
      # location. With most .net core applications, you can simply publish them as a
      # "self-contained" application allowing consumers of the application to run them
      # and use its own stand alone version of the .net core runtime. However because
      # this is simply a dll and not an exe, it will look for the runtime in the shared
      # .net core installation folder. By setting DOTNET_MULTILEVEL_LOOKUP to 0 we can
      # override that folder's location with DOTNET_ROOT. To avoid the possibility of
      # interfering with other .net core processes that might rely on the common shared
      # location, we revert these variables after the script completes.
      original_dml = ENV["DOTNET_MULTILEVEL_LOOKUP"]
      original_dotnet_root = ENV["DOTNET_ROOT"]
      original_dotnet_root_x86 = ENV["DOTNET_ROOT(x86)"]

      bin_dir = ChefPowerShell.bin_dir
      ENV["DOTNET_MULTILEVEL_LOOKUP"] = "0"
      ENV["DOTNET_ROOT"] = bin_dir
      ENV["DOTNET_ROOT(x86)"] = bin_dir

      @powershell_dll = File.join(bin_dir, "shared", "Microsoft.NETCore.App", "10.0.0", "Chef.PowerShell.Wrapper.Core.dll")

      # Windows' default LoadLibrary(Ex) search order used by FFI does NOT
      # include the directory of the DLL being loaded -- FFI loads on Windows
      # with LOAD_LIBRARY_SEARCH_DEFAULT_DIRS, which only searches the hosting
      # EXE's directory, System32, and directories registered via
      # SetDllDirectory/AddDllDirectory (notably *not* PATH or the current
      # directory).
      #
      # Chef.PowerShell.Wrapper.Core.dll lives in a "shared/Microsoft.NETCore.App"
      # folder separate from ruby.exe. It also depends on native VC++ runtime DLLs
      # (vcruntime140.dll, msvcp140.dll, concrt140.dll, vccorlib140.dll) that are
      # NOT copied into that nested folder -- they only exist in the flat
      # "ruby_bin_folder/<arch>" directory alongside the .NET Framework wrapper.
      # We must register BOTH directories explicitly. Do not assume System32
      # already has the VC++ redistributable installed -- that is incidental to
      # any given machine and must never be relied upon.
      core_dir = File.dirname(@powershell_dll)
      native_deps_dir = File.expand_path(File.join(core_dir, "..", "..", ".."))

      Kernel32.SetDefaultDllDirectories(Kernel32::LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)
      [native_deps_dir, core_dir].each do |dir|
        next if Kernel32.register_search_directory(dir)

        raise LoadError, "Failed to register DLL search directory: #{dir}"
      end

      # Retained alongside AddDllDirectory for defense in depth / older Windows
      # compatibility (AddDllDirectory requires Windows 8+/Server 2012+, or
      # Windows 7 SP1/Server 2008 R2 SP1 with KB2533623).
      Kernel32.SetDllDirectoryA(core_dir)

      super
    ensure
      ENV["DOTNET_MULTILEVEL_LOOKUP"] = original_dml
      ENV["DOTNET_ROOT"] = original_dotnet_root
      ENV["DOTNET_ROOT(x86)"] = original_dotnet_root_x86
    end

    def self.dll
      # This Powershell DLL source lives here: https://github.com/chef/chef-powershell-shim
      # Every merge into that repo triggers a Habitat build and promotion. Running
      # the rake :update_chef_exec_dll task in this (chef/chef) repo will pull down
      # the built packages and copy the binaries to distro/ruby_bin_folder. Bundle install
      # ensures that the correct architecture binaries are installed into the path.
      # Also note that the version of pwsh is determined by which assemblies the dll was
      # built with. To update powershell, those dependencies must be bumped.
      bin_dir = ChefPowerShell.bin_dir
      @powershell_dll = File.join(bin_dir, "shared", "Microsoft.NETCore.App", "10.0.0", "Chef.PowerShell.Wrapper.Core.dll")
      @dll ||= @powershell_dll
    end
  end
end

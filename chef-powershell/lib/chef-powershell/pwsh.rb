#
# Author:: Matt Wrock (<mwrock@chef.io>)
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

class ChefPowerShell
  class Pwsh < ChefPowerShell::PowerShell

    def self.resolve_core_wrapper_dll
      gem_spec = Gem.loaded_specs["chef-powershell"]
      arch = ENV["PROCESSOR_ARCHITECTURE"] || "AMD64"

      if gem_spec
        base = gem_spec.full_gem_path
        dll_path = File.join(base, "bin", "ruby_bin_folder", arch, "shared", "Microsoft.NETCore.App", "8.0.0", "Chef.PowerShell.Wrapper.Core.dll")
        return dll_path if File.exist?(dll_path)
      end

      override = ENV["CHEF_POWERSHELL_BIN"]
      candidate = override && File.join(override, "shared", "Microsoft.NETCore.App", "8.0.0", "Chef.PowerShell.Wrapper.Core.dll")
      return candidate if candidate && File.exist?(candidate)

      dll_path = gem_spec ? File.join(gem_spec.full_gem_path, "bin", "ruby_bin_folder", arch, "shared", "Microsoft.NETCore.App", "8.0.0", "Chef.PowerShell.Wrapper.Core.dll") : File.join("bin", "ruby_bin_folder", arch, "shared", "Microsoft.NETCore.App", "8.0.0", "Chef.PowerShell.Wrapper.Core.dll")
      raise LoadError, "Pwsh Core wrapper DLL not found at #{dll_path}. Populate binaries via rake update_chef_powershell_dlls"
    end

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

      ENV["DOTNET_MULTILEVEL_LOOKUP"] = "0"
      gem_spec = Gem.loaded_specs["chef-powershell"]
      if gem_spec
        arch = ENV["PROCESSOR_ARCHITECTURE"] || "AMD64"
        arch_root = File.join(gem_spec.full_gem_path, "bin", "ruby_bin_folder", arch)
        ENV["DOTNET_ROOT"] = arch_root
      end

      @powershell_dll = self.class.resolve_core_wrapper_dll

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
      @dll ||= resolve_core_wrapper_dll
    end
  end
end

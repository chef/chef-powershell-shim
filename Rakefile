#
# Author:: John McCrae (<john.mccrae@progress.com>)
# Copyright:: Copyright, Chef Software Inc.
# Copyright:: Copyright, Progress Software Inc.
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
#

begin
  require "rubocop/rake_task"
  require "rspec/core/rake_task"
  require "rubygems"
  require "rake"
  require "chefstyle"
rescue LoadError => e
  puts "Skipping missing rake dep: #{e}"
end

desc "Builds and Copies powershell_exec related binaries from the latest built Habitat Packages"
task :update_chef_powershell_dlls do
  raise "This task must be run on Windows since we are installing a Windows targeted package!" unless Gem.win_platform?

  require "mkmf"
  raise "Unable to locate Habitat cli. Please install Habitat cli before invoking this task!" unless find_executable "hab"

  sh("hab pkg build Habitat")
  sh("hab pkg build Habitat-x86")

  sh("hab pkg install chef/chef-powershell-shim")
  sh("hab pkg install chef/chef-powershell-shim-x86")

  x64 = `hab pkg path chef/chef-powershell-shim`.chomp.tr("\\", "/")
  x86 = `hab pkg path chef/chef-powershell-shim-x86`.chomp.tr("\\", "/")
  FileUtils.rm_rf(Dir["bin/ruby_bin_folder/AMD64/*"])
  FileUtils.rm_rf(Dir["bin/ruby_bin_folder/x86/*"])
  puts "Copying #{x64}/bin/* to chef-powershell/bin/ruby_bin_folder/AMD64"
  FileUtils.cp_r(Dir["#{x64}/bin/*"], "chef-powershell/bin/ruby_bin_folder/AMD64")
  puts "Copying #{x86}/bin/* to chef-powershell/bin/ruby_bin_folder/x86"
  FileUtils.cp_r(Dir["#{x86}/bin/*"], "chef-powershell/bin/ruby_bin_folder/x86")
end

task all: %w{update_chef_powershell_dlls}.freeze

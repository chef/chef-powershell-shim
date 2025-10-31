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
  require "cookstyle"
rescue LoadError => e
  puts "Skipping missing rake dep: #{e}"
end

desc "Builds and Copies powershell_exec related binaries from the latest built Habitat Packages"
task :update_chef_powershell_dlls do
  raise "This task must be run on Windows since we are installing a Windows targeted package!" unless Gem.win_platform?

  require "mkmf"
  raise "Unable to locate Habitat cli. Please install Habitat cli before invoking this task!" unless find_executable "hab"

  sh("hab pkg build Habitat")
  sh("hab pkg install chef/chef-powershell-shim")

  x64 = `hab pkg path chef/chef-powershell-shim`.chomp.tr("\\", "/")

  arch = ENV["PROCESSOR_ARCHITECTURE"] || "AMD64"
  target = File.join(__dir__, "chef-powershell", "bin", "ruby_bin_folder", arch)
  FileUtils.mkdir_p(target)

  puts "Cleaning #{target}"
  FileUtils.rm_rf(Dir["#{target}/*"])

  puts "Copying #{x64}/bin/* to #{target}"
  FileUtils.cp_r(Dir["#{x64}/bin/*"], target)
end

task all: %w{update_chef_powershell_dlls}.freeze

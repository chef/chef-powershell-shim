#
# Author:: John McCrae (<john.mccrae@progress.com>)
# Copyright (c) 2018-2025 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.
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

  sh("hab pkg build habitat")

  latest_hart = Dir.glob("results/chef-chef-powershell-shim-*-x86_64-windows.hart").max_by { |f| File.mtime(f) }
  raise "No built artifact found in results/. Run hab pkg build habitat first." unless latest_hart

  hart_name = File.basename(latest_hart, ".hart")
  parts = hart_name.split("-")

  # chef-chef-powershell-shim-19.1.0-20260825145857-x86_64-windows
  # [origin]-[name...]-[version]-[release]-x86_64-windows
  origin = parts[0]
  version = parts[-4]
  release = parts[-3]
  name = parts[1..-5].join("-")
  ident = "#{origin}/#{name}/#{version}/#{release}"

  sh("hab pkg install #{latest_hart}")

  x64 = `hab pkg path #{ident}`.chomp.tr("\\", "/")
  raise "Unable to resolve package path for #{ident}" if x64.empty?

  FileUtils.rm_rf(Dir["bin/ruby_bin_folder/AMD64/*"])
  FileUtils.mkdir_p("chef-powershell/bin/ruby_bin_folder/AMD64")
  puts "Copying #{x64}/bin/* to chef-powershell/bin/ruby_bin_folder/AMD64"
  FileUtils.cp_r(Dir["#{x64}/bin/*"], "chef-powershell/bin/ruby_bin_folder/AMD64")
end

task all: %w{update_chef_powershell_dlls}.freeze

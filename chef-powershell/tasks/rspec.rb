#
# Author:: John McCrae (<john.mccrae@progress.com>)
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
#

require "rubygems"
require "rake"

begin
  require "rspec/core/rake_task"

  desc "Run all chef specs in spec directory"

  RSpec::Core::RakeTask.new(:spec) do |t|
    t.verbose = false
    t.rspec_opts = %w{--profile}
    t.pattern = FileList["spec/**/*_spec.rb"]
  end

  namespace :spec do
    RSpec::Core::RakeTask.new(:unit) do |t|
      t.verbose = false
      t.rspec_opts = %w{--profile}
      t.pattern = FileList["spec/unit/**/*_spec.rb"]
    end

    RSpec::Core::RakeTask.new(:functional) do |t|
      t.verbose = false
      t.rspec_opts = %w{--profile}
      t.pattern = FileList["spec/functional/**/*_spec.rb"]
    end

    desc "Print Specdoc for all specs"
    RSpec::Core::RakeTask.new(:doc) do |t|
      t.verbose = false
      t.rspec_opts = %w{--format doc --dry-run --profile}
      t.pattern = FileList["spec/**/*_spec.rb"]
    end

  end

  task default: :spec

rescue LoadError
  STDERR.puts "\n*** RSpec not available. (sudo) gem install rspec to run unit tests. ***\n\n"
end

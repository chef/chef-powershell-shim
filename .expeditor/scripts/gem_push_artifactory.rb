#!/usr/bin/env ruby
# frozen_string_literal: true

require "rubygems/commands/push_command"

def env_or_raise(key)
  ENV[key] || raise("Required ENV variable `#{key}` is unset!")
end

project_name = env_or_raise("PROJECT_NAME")
artifactory_endpoint = env_or_raise("ARTIFACTORY_ENDPOINT")
artifactory_gem_repo = ENV["ARTIFACTORY_GEM_REPO"] || "omnibus-gems-local"

project_source = File.expand_path(File.join(__dir__, "..", "..", "chef-powershell"))
gems_found = Dir.glob(File.join(project_source, "#{project_name}-*.gem"))
gems_to_publish = gems_found.uniq { |gem| File.basename(gem) }

raise "No #{project_name} gem found to publish in #{project_source}" if gems_to_publish.empty?

puts "Publishing gems from #{project_source}"

gems_to_publish.each do |gem_path|
  puts "Publishing gem #{gem_path}"
  upload_path = "#{artifactory_endpoint}/api/gems/#{artifactory_gem_repo}"
  # Mimics the `gem push` CLI; this is a public Rubygems API.
  # http://docs.seattlerb.org/rubygems/Gem/Command.html
  gem_pusher = Gem::Commands::PushCommand.new
  gem_pusher.handle_options [gem_path, "--host", upload_path, "--verbose"]
  gem_pusher.execute
end

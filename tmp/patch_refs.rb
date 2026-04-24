# encoding: utf-8
# frozen_string_literal: true

BASE = "/home/dev/pub4/MASTER"

# 1. Fix continuity_index.rb to read from models.yml instead of fallback_models.yml
ci_path = File.join(BASE, "lib/master/routing/continuity_index.rb")
content = File.read(ci_path, encoding: "utf-8")
# The merged data is now under the same keys in models.yml
content.gsub!("fallback_models.yml", "models.yml")
# Update the dig path since we merged under different structure
content.gsub!('data.dig("continuity", "enabled")', 'data.dig("continuity", "enabled")')
content.gsub!('data.dig("continuity", "openrouter", "free_latest")', 'data.dig("openrouter", "free_latest")')
content.gsub!('data.dig("continuity", "ferrum_web_chat", "free_latest")', 'data.dig("ferrum_web_chat", "free_latest")')
File.write(ci_path, content)
puts "fixed: continuity_index.rb -> models.yml"

# 2. Remove Experience reference from master.rb
master_path = File.join(BASE, "lib/master.rb")
content = File.read(master_path, encoding: "utf-8")
# Remove the experience line and any usage of the variable
content.gsub!(/^.*State::Experience\.new.*\n/, "")
content.gsub!(/experience\s*=\s*/, "") # clean any leftover assignment
# Also remove experience from any container/build wiring
content.gsub!(/,?\s*experience:\s*experience\b/, "")
File.write(master_path, content)
puts "fixed: master.rb (removed Experience)"

puts "done"

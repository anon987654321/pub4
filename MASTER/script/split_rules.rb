#!/usr/bin/env ruby
# frozen_string_literal: true

# Idempotent split of data/rules.yml rule bodies into data/rules/*.yml shards.
# Leaves laws/zen/metadata in rules.yml; sets rules: {} stub when split succeeds.

require "yaml"
require "fileutils"

root = File.expand_path("..", __dir__)
rules_path = File.join(root, "data", "rules.yml")
rules_dir = File.join(root, "data", "rules")

abort("missing #{rules_path}") unless File.file?(rules_path)

data = YAML.safe_load(File.read(rules_path), permitted_classes: [Date, Time], aliases: true) || {}
rules = data["rules"]
if rules.nil? || (rules.is_a?(Hash) && rules.empty?)
  merged = 0
  Dir.glob(File.join(rules_dir, "*.yml")).sort.each do |file|
    shard = YAML.safe_load(File.read(file), permitted_classes: [Date, Time], aliases: true) || {}
    merged += shard.values.flatten.size
  end
  puts "split_rules: already split (#{merged} rules in #{rules_dir})"
  exit 0
end

abort("rules must be a Hash scope => [entries]") unless rules.is_a?(Hash)

FileUtils.mkdir_p(rules_dir)
rules.each do |scope, entries|
  list = Array(entries)
  out = File.join(rules_dir, "#{scope}.yml")
  body = { scope => list }
  File.write(out, body.to_yaml)
  puts "wrote #{out} (#{list.size} rules)"
end

data["rules"] = {}
File.write(rules_path, data.to_yaml)
puts "trimmed #{rules_path} -> rules: {} (#{rules.values.flatten.size} rules moved)"
#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerate OPENBSD/deploy_inventory.json from RAILS/apps.yml.
#   ruby OPENBSD/bin/sync_deploy_inventory.rb          # rewrite
#   ruby OPENBSD/bin/sync_deploy_inventory.rb --check  # exit 1 when the file is not what apps.yml generates
# No date in the output: a stamp that moves on every run makes an unchanged
# inventory look changed, and port_inventory already says when the two disagree.

require "json"
require "yaml"

if ARGV.intersect?(%w[-h --help])
  puts "usage: ruby OPENBSD/bin/sync_deploy_inventory.rb [--check]   # rewrites (or verifies) OPENBSD/deploy_inventory.json from RAILS/apps.yml"
  exit 0
end

ROOT = File.expand_path("../..", __dir__)
APPS_YML = File.join(ROOT, "RAILS", "apps.yml")
OUT = File.join(ROOT, "OPENBSD", "deploy_inventory.json")

data = YAML.safe_load(File.read(APPS_YML))
apps = data.fetch("apps").map do |name, meta|
  { "name" => name, "domain" => meta.fetch("domain"), "port" => meta.fetch("port").to_i }
end.sort_by { |row| row["name"] }

payload = {
  "schema" => 1,
  "generated_from" => "RAILS/apps.yml",
  "apps" => apps,
}

expected = JSON.pretty_generate(payload) + "\n"
if ARGV.include?("--check")
  if File.file?(OUT) && File.read(OUT, encoding: "UTF-8") == expected
    puts "sync_deploy_inventory: in sync (#{apps.size} apps)"
    exit 0
  end
  warn "sync_deploy_inventory: #{OUT} is not what RAILS/apps.yml generates - run ruby OPENBSD/bin/sync_deploy_inventory.rb"
  exit 1
end

File.write(OUT, expected)
puts "wrote #{OUT} (#{apps.size} apps)"

#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerate OPENBSD/deploy_inventory.json from RAILS/apps.yml.
#   ruby OPENBSD/bin/sync_deploy_inventory.rb
# No date in the output: a stamp that moves on every run makes an unchanged
# inventory look changed, and port_inventory already says when the two disagree.

require "json"
require "yaml"

if ARGV.intersect?(%w[-h --help])
  puts "usage: ruby OPENBSD/bin/sync_deploy_inventory.rb   # rewrites OPENBSD/deploy_inventory.json from RAILS/apps.yml"
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
  "master_face" => {
    "name" => "master",
    "domain" => "ai.brgen.no",
    "port" => 53_187,
    "deploy_root" => "MASTER/web",
  },
}

File.write(OUT, JSON.pretty_generate(payload) + "\n")
puts "wrote #{OUT} (#{apps.size} apps)"

#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"

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
  "generated_at" => Time.now.utc.strftime("%Y-%m-%d"),
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

# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"
path = File.join(BASE, "lib/master/agent.rb")
content = File.read(path, encoding: "utf-8")
content.sub!(
  "YAML.safe_load_file(yml_path)",
  "YAML.safe_load_file(yml_path, aliases: true)"
)
File.write(path, content)
puts "fixed: agent.rb — YAML.safe_load_file now passes aliases: true"

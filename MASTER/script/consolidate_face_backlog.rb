#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("..", __dir__)
FE_PATH = File.join(ROOT, "data/runtime/face_enhancements.yml")

GENERIC_WEB = /\AWeb UI improvement \d+\z/
KEEP_WEB = %w[web_108 web_161 web_171 web_173].freeze

data = YAML.safe_load_file(FE_PATH, permitted_classes: [Symbol], aliases: true)
before = data["enhancements"].size

data["enhancements"].reject! do |item|
  id = item["id"].to_s
  if id.start_with?("enh_mi_")
    true
  elsif id.match?(/\Aweb_\d+\z/)
    num = id.delete_prefix("web_").to_i
    num >= 81 && item["status"].to_s == "pending" && GENERIC_WEB.match?(item["summary"].to_s) && !KEEP_WEB.include?(id)
  else
    false
  end
end

removed = before - data["enhancements"].size
pending = data["enhancements"].count { |item| item["status"].to_s == "pending" }
implemented = data["enhancements"].count { |item| item["status"].to_s == "implemented" }

File.write(FE_PATH, data.to_yaml(line_width: -1))
puts "face_enhancements: removed #{removed} placeholder rows"
puts "face_enhancements: #{implemented} implemented / #{pending} pending"
#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"
require "yaml"

# Canonical 320-item backlog — status synced from codebase capabilities (v4 convergence).
IMPLEMENTED = Set.new(
  (1..28).to_a +
  (46..90).to_a +
  (96..170).to_a +
  (171..180).to_a +
  (196..215).to_a +
  (231..285).to_a +
  (301..320).to_a +
  # Deferred batch — content, automation, UX (v4 convergence pass)
  (29..45).to_a +
  (91..95).to_a +
  (216..230).to_a
)

OPS = Set.new((181..195).to_a + (286..300).to_a)

TITLES = File.readlines(File.join(__dir__, "improvement_titles.txt"), chomp: true)
raise "expected 320 titles, got #{TITLES.size}" unless TITLES.size == 320

items = TITLES.each_with_index.map do |title, idx|
  n = idx + 1
  status = if IMPLEMENTED.include?(n)
             "implemented"
           elsif OPS.include?(n)
             "ops"
           else
             "deferred"
           end
  { "id" => format("%03d", n), "title" => title, "status" => status }
end

counts = items.group_by { |i| i["status"] }.transform_values(&:count)
data = {
  "version" => 2,
  "generated" => Time.now.utc.strftime("%Y-%m-%d"),
  "summary" => {
    "total" => 320,
    "implemented" => counts["implemented"] || 0,
    "deferred" => counts["deferred"] || 0,
    "ops" => counts["ops"] || 0,
  },
  "items" => items,
}
File.write(File.expand_path("../IMPROVEMENTS.yml", __dir__), data.to_yaml)
puts counts.inspect
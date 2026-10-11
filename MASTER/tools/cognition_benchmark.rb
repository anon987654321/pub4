#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/cognition/outcome_model"
require_relative "../lib/cognition/benchmark"

path = ARGV.find { |arg| !arg.start_with?("--") }
learn = !ARGV.include?("--no-learning")
unknown = ARGV.reject { |arg| arg == path || arg == "--no-learning" }
unless path && unknown.empty?
  warn "usage: ruby tools/cognition_benchmark.rb [--no-learning] verified-outcomes.jsonl"
  exit 64
end

begin
  rows = []
  File.readlines(path, chomp: true, encoding: "UTF-8").each_with_index do |line, index|
    next if line.strip.empty? || line.lstrip.start_with?("#")

    begin
      rows << JSON.parse(line)
    rescue JSON::ParserError => e
      abort "cognition-benchmark: invalid JSON on line #{index + 1}: #{e.message}"
    end
  end
  abort "cognition-benchmark: no outcome records" if rows.empty?

  puts JSON.pretty_generate(Master::Cognition::Benchmark.evaluate(rows, learn:))
rescue ArgumentError, Errno::ENOENT, EncodingError => e
  warn "cognition-benchmark: #{e.message}"
  exit 2
end

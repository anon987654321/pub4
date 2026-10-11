#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/cognition/outcome_model"
require_relative "../lib/cognition/benchmark"

args = ARGV.dup
learn = !args.delete("--no-learning")
root = nil
if (root_index = args.index("--root"))
  root = args[root_index + 1]
  unless root && !root.start_with?("--")
    warn "usage: ruby tools/cognition_benchmark.rb [--no-learning] [--root PATH] verified-outcomes.jsonl"
    exit 64
  end
  args.slice!(root_index, 2)
end
path = args.shift
unless path && args.empty?
  warn "usage: ruby tools/cognition_benchmark.rb [--no-learning] [--root PATH] verified-outcomes.jsonl"
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

  puts JSON.pretty_generate(Master::Cognition::Benchmark.evaluate(rows, learn:, root:))
rescue ArgumentError, Errno::ENOENT, EncodingError => e
  warn "cognition-benchmark: #{e.message}"
  exit 2
end

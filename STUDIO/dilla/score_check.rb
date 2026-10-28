#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "open3"
require "tempfile"
require "timeout"
require_relative "style_adapter"

options = { style_contract: "blue_hour" }
parser = OptionParser.new do |p|
  p.banner = "usage: ruby score_check.rb --abc SCORE.abc [--style-contract ID]"
  p.on("--abc FILE", "ABC score to validate without rendering audio") { |value| options[:abc] = File.expand_path(value) }
  p.on("--style-contract ID", "Declared audio style contract (default: blue_hour)") { |value| options[:style_contract] = value }
end
parser.parse!
unless options[:abc] && File.file?(options[:abc]) && File.readable?(options[:abc])
  warn JSON.generate(status: "rejected", reason: "a readable --abc FILE is required")
  exit 2
end

begin
  Studio::StyleRegistry.resolve(style_id: options[:style_contract], modality: "audio")
rescue Studio::StyleRegistry::InvalidStyle => e
  warn JSON.generate(status: "rejected", reason: "style contract: #{e.message}")
  exit 2
end

abc = File.read(options[:abc])
missing = %w[X: T: M: L: K:].reject { |header| abc.lines.any? { |line| line.start_with?(header) } }
unless missing.empty?
  warn JSON.generate(status: "rejected", reason: "ABC headers missing: #{missing.join(', ')}")
  exit 1
end

executable = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "abc2midi") }
                                     .find { |path| File.file?(path) && File.executable?(path) }
unless executable
  warn JSON.generate(status: "unavailable", reason: "abc2midi is not installed; score was not certified")
  exit 3
end

validator = lambda do |score|
  Tempfile.create(["dilla-score-", ".abc"]) do |abc_file|
    abc_file.write(score)
    abc_file.flush
    Tempfile.create(["dilla-score-", ".mid"]) do |midi_file|
      output, status = Timeout.timeout(15) do
        Open3.capture2e(executable, abc_file.path, "-o", midi_file.path)
      end
      status.success? ? [] : [output.lines.last.to_s.strip.then { |line| line.empty? ? "abc2midi rejected the score" : line }]
    end
  end
rescue Timeout::Error
  ["abc2midi validation timed out after 15 seconds"]
end

begin
  result = Dilla::StyleAdapter.validate_abc!(
    abc, validator: validator, style_id: options[:style_contract]
  )
  puts JSON.generate(result.merge(validator: "abc2midi", rendered: false))
rescue StandardError => e
  warn JSON.generate(status: "rejected", reason: e.message, validator: "abc2midi", rendered: false)
  exit 1
end

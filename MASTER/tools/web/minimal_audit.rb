#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "time"
require "yaml"

root = File.expand_path(ENV.fetch("PUB4_ROOT", File.join(__dir__, "../../..")))
law_path = File.join(root, "MASTER/data/minimalism.yml")
law = YAML.safe_load_file(law_path, permitted_classes: [], aliases: false)

options = { output: nil }
OptionParser.new do |opts|
  opts.on("--output PATH") { |v| options[:output] = File.expand_path(v) }
end.parse!

extensions = %w[.erb .html .scss .css .svg .js]
files = Dir.glob(File.join(root, "RAILS", "**", "*")).select { |path| extensions.include?(File.extname(path)) && File.file?(path) }

patterns = {
  "box_shadow" => /box-shadow\s*:/,
  "gradient" => /(?:linear|radial|conic)-gradient\(/,
  "href_hash" => /href\s*=\s*["']#["']/
}
findings = []
files.each do |path|
  source = File.read(path, encoding: "UTF-8")
  patterns.each do |name, pattern|
    source.lines.each_with_index do |line, index|
      findings << { "rule" => name, "file" => path.delete_prefix(root + "/"), "line" => index + 1, "sample" => line.strip } if line.match?(pattern)
    end
  end
end

report = {
  "generated_at" => Time.now.utc.iso8601,
  "law_version" => law.fetch("version"),
  "files" => files.size,
  "counts" => findings.group_by { |finding| finding["rule"] }.transform_values(&:size),
  "findings" => findings
}
if options[:output]
  File.write(options[:output], JSON.pretty_generate(report) + "\n")
else
  puts JSON.pretty_generate(report)
end

exit 1 if ENV["MINIMAL_AUDIT_STRICT"] == "1" && findings.any?

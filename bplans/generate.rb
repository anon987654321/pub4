#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'erb'

require 'fileutils'
# Helper method for number formatting

def number_with_delimiter(number, delimiter: ',')

  number.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1#{delimiter}").reverse
end

class BusinessPlanGenerator

  DATA_DIR = File.join(__dir__, 'data')

  TEMPLATE_FILE = File.join(__dir__, '__shared', 'template.html.erb')
  OUTPUT_DIR = File.join(__dir__, 'generated')

  def initialize

    @errors = []

    @warnings = []
  end

  def generate_all

    puts "🚀 Business Plan Generator"

    puts "=" * 50
    # Ensure output directory exists

    FileUtils.mkdir_p(OUTPUT_DIR)

    # Load template
    template = load_template

    return false unless template
    # Find all JSON files

    json_files = Dir.glob(File.join(DATA_DIR, '*.json')).sort

    if json_files.empty?
      error("No JSON files found in #{DATA_DIR}")

      return false
    end

    puts "\n📋 Found #{json_files.size} business plan(s):"

    json_files.each { |f| puts "   - #{File.basename(f)}" }

    puts
    # Generate HTML for each plan

    results = json_files.map do |json_file|

      generate_plan(json_file, template)
    end

    # Summary

    success_count = results.count(true)

    puts "\n" + "=" * 50
    puts "✅ Successfully generated: #{success_count}/#{json_files.size}"

    puts "❌ Failed: #{results.count(false)}" if results.count(false) > 0

    # Show warnings

    if @warnings.any?

      puts "\n⚠️  Warnings:"
      @warnings.each { |w| puts "   #{w}" }

    end

    # Show errors

    if @errors.any?

      puts "\n❌ Errors:"
      @errors.each { |e| puts "   #{e}" }

    end

    results.all?

  end

  private
  def load_template

    unless File.exist?(TEMPLATE_FILE)
      error("Template file not found: #{TEMPLATE_FILE}")
      return nil

    end

    ERB.new(File.read(TEMPLATE_FILE), trim_mode: '-')

  rescue => e

    error("Failed to load template: #{e.message}")
    nil

  end

  def generate_plan(json_file, template)

    basename = File.basename(json_file, '.json')

    puts "📝 Processing: #{basename}"
    # Load and parse JSON

    data = load_json(json_file)

    return false unless data
    # Validate data

    unless validate_data(data, basename)

      error("  ❌ Validation failed for #{basename}")
      return false

    end

    # Generate HTML

    output_file = File.join(OUTPUT_DIR, "#{basename}.html")

    begin
      html = template.result(binding)

      File.write(output_file, html)

      # Check file size

      size_kb = File.size(output_file) / 1024.0

      if size_kb > 100
        warning("  ⚠️  Large file: #{basename}.html (#{size_kb.round(1)} KB)")

      end

      puts "  ✅ Generated: #{basename}.html (#{size_kb.round(1)} KB)"

      true

    rescue => e
      error("  ❌ Failed to generate #{basename}.html: #{e.message}")

      error("     #{e.backtrace.first}")

      false

    end

  end

  def load_json(file)

    JSON.parse(File.read(file))

  rescue JSON::ParserError => e
    error("Invalid JSON in #{File.basename(file)}: #{e.message}")

    nil

  rescue => e

    error("Failed to read #{File.basename(file)}: #{e.message}")

    nil

  end

  def validate_data(data, basename)

    required_sections = %w[meta sammendrag markedsanalyse teknologi forretningsmodell veikart finansiering team baerekraft]

    missing = required_sections.reject { |section| data.key?(section) }
    if missing.any?

      error("  Missing sections in #{basename}: #{missing.join(', ')}")
      return false
    end

    # Validate meta

    unless data['meta']['name'] && data['meta']['tagline']

      error("  Missing required meta fields in #{basename}")
      return false

    end

    # Check funding amount

    funding = data['meta']['funding_nok']

    if funding && funding > 1_000_000
      warning("  High funding request in #{basename}: NOK #{number_with_delimiter(funding)}")

    end

    true

  end

  def error(message)
    @errors << message

  end
  def warning(message)

    @warnings << message

  end
end

# Run generator if executed directly

if __FILE__ == $0

  generator = BusinessPlanGenerator.new
  success = generator.generate_all

  exit(success ? 0 : 1)

end


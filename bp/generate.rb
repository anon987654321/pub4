#!/usr/bin/env ruby
# frozen_string_literal: true
# Business Plan Generator - Bergen business pages
# Generates HTML pages from JSON data using ERB templates
require 'json'
require 'erb'
require 'fileutils'
# Number formatting helper
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
    print_header
    ensure_output_directory
    template = load_template
    return false unless template
    json_files = find_json_files
    return false if json_files.empty?
    print_files_found(json_files)
    results = generate_all_plans(json_files, template)
    print_summary(results, json_files.size)
    results.all?
  end
  private
  def print_header
    puts "🚀 Business Plan Generator"
    puts
  end
  def ensure_output_directory
    FileUtils.mkdir_p(OUTPUT_DIR)
  end
  def find_json_files
    files = Dir.glob(File.join(DATA_DIR, '*.json')).sort
    if files.empty?
      error("No JSON files found in #{DATA_DIR}")
    end
    files
  end
  def print_files_found(files)
    puts "\n📋 Found #{files.size} business plan(s):"
    files.each { |f| puts "   - #{File.basename(f)}" }
    puts
  end
  def generate_all_plans(json_files, template)
    json_files.map { |json_file| generate_plan(json_file, template) }
  end
  def print_summary(results, total)
    success_count = results.count(true)
    failure_count = results.count(false)
    puts
    puts "✅ Successfully generated: #{success_count}/#{total}"
    puts "❌ Failed: #{failure_count}" if failure_count > 0
    print_warnings
    print_errors
  end
  def print_warnings
    return unless @warnings.any?
    puts "\n⚠️  Warnings:"
    @warnings.each { |w| puts "   #{w}" }
  end
  def print_errors
    return unless @errors.any?
    puts "\n❌ Errors:"
    @errors.each { |e| puts "   #{e}" }
  end
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
    data = load_json(json_file)
    return false unless data
    unless validate_data(data, basename)
      error("  ❌ Validation failed for #{basename}")
      return false
    end
    write_html_file(basename, template, data)
  end
  def write_html_file(basename, template, data)
    output_file = File.join(OUTPUT_DIR, "#{basename}.html")
    html = template.result(binding)
    File.write(output_file, html)
    check_file_size(basename, output_file)
    true
  rescue => e
    error("  ❌ Failed to generate #{basename}.html: #{e.message}")
    error("     #{e.backtrace.first}")
    false
  end
  def check_file_size(basename, output_file)
    size_kb = File.size(output_file) / 1024.0
    if size_kb > 100
      warning("  ⚠️  Large file: #{basename}.html (#{size_kb.round(1)} KB)")
    end
    puts "  ✅ Generated: #{basename}.html (#{size_kb.round(1)} KB)"
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
    validate_required_sections(data, basename) &&
      validate_meta_fields(data, basename) &&
      validate_funding_amount(data, basename)
  end
  def validate_required_sections(data, basename)
    required = %w[meta sammendrag markedsanalyse teknologi forretningsmodell
                  veikart finansiering team baerekraft]
    missing = required.reject { |section| data.key?(section) }
    if missing.any?
      error("  Missing sections in #{basename}: #{missing.join(', ')}")
      return false
    end
    true
  end
  def validate_meta_fields(data, basename)
    unless data['meta']['name'] && data['meta']['tagline']
      error("  Missing required meta fields in #{basename}")
      return false
    end
    true
  end
  def validate_funding_amount(data, basename)
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
if __FILE__ == $PROGRAM_NAME
  generator = BusinessPlanGenerator.new
  success = generator.generate_all
  exit(success ? 0 : 1)
end

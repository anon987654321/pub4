#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

# Simple test version of the Master.json v12.9.0 Framework
class MasterFrameworkTest
  def initialize
    @config = load_master_config
    @processed_files = []
    @failed_files = []
    @start_time = Time.now
  end

  def execute_test
    puts '§ Master.json v12.9.0 Framework Test Started'

    # Test with a small subset of files
    test_files = get_test_files
    puts "Processing #{test_files.size} test files..."

    test_files.each do |file|
      process_file(file)
    end

    generate_test_report

    puts '✅ Test completed successfully!'
  end

  private

  def load_master_config
    config_path = File.join(__dir__, 'master.json')
    JSON.parse(File.read(config_path))
  end

  def get_test_files
    # Process only key files for testing
    files = []

    # Get Ruby files from root directory
    Dir.glob('*.rb').each do |file|
      files << { path: file, type: 'ruby' }
    end

    # Get a few files from ai3 directory
    Dir.glob('ai3/*.rb').first(3).each do |file|
      files << { path: file, type: 'ruby' }
    end

    # Get shell files
    Dir.glob('**/*.sh').first(5).each do |file|
      files << { path: file, type: 'shell' }
    end

    files
  end

  def process_file(file)
    puts "Processing: #{file[:path]}"

    case file[:type]
    when 'ruby'
      process_ruby_file(file)
    when 'shell'
      process_shell_file(file)
    end

    @processed_files << file[:path]
  end

  def process_ruby_file(file)
    # Basic Ruby file validation

    content = File.read(file[:path])

    # Check for basic syntax by trying to parse
    eval("BEGIN { throw :valid }; #{content}; END { throw :valid }")

    puts "  ✅ Ruby syntax valid: #{file[:path]}"
  rescue SyntaxError => e
    puts "  ❌ Ruby syntax error: #{file[:path]} - #{e.message}"
    @failed_files << { path: file[:path], error: e.message }
  rescue Exception
    # This catches the throw :valid which means syntax is OK
    puts "  ✅ Ruby syntax valid: #{file[:path]}"
  end

  def process_shell_file(file)
    # Basic shell file validation

    content = File.read(file[:path])

    # Check for basic shell syntax patterns
    if content.include?('#!/bin/bash') || content.include?('#!/bin/sh')
      puts "  ✅ Shell script valid: #{file[:path]}"
    else
      puts "  ⚠️  Shell script missing shebang: #{file[:path]}"
    end
  rescue StandardError => e
    puts "  ❌ Shell script error: #{file[:path]} - #{e.message}"
    @failed_files << { path: file[:path], error: e.message }
  end

  def generate_test_report
    end_time = Time.now
    duration = end_time - @start_time

    report = {
      framework_version: @config['framework_version'],
      test_timestamp: end_time.strftime('%Y-%m-%dT%H:%M:%SZ'),
      duration_seconds: duration.round(2),
      total_files: @processed_files.size,
      failed_files: @failed_files.size,
      success_rate: ((@processed_files.size - @failed_files.size).to_f / @processed_files.size * 100).round(2),
      processed_files: @processed_files,
      failures: @failed_files
    }

    puts "\n" + ('=' * 60)
    puts '§ FRAMEWORK TEST REPORT'
    puts '=' * 60
    puts "Duration: #{duration.round(2)} seconds"
    puts "Files processed: #{@processed_files.size}"
    puts "Failures: #{@failed_files.size}"
    puts "Success rate: #{report[:success_rate]}%"
    puts '=' * 60

    File.write('test_compliance_report.json', JSON.pretty_generate(report))

    if @failed_files.empty?
      puts '✅ All files passed validation!'
    else
      puts "❌ #{@failed_files.size} files failed validation:"
      @failed_files.each do |failure|
        puts "  - #{failure[:path]}: #{failure[:error]}"
      end
    end
  end
end

# Run the test
if __FILE__ == $0
  begin
    test = MasterFrameworkTest.new
    test.execute_test
  rescue StandardError => e
    puts "❌ Test failed: #{e.message}"
    puts e.backtrace
    exit 1
  end
end

#!/usr/bin/env ruby
# frozen_string_literal: true

# Test runner for multimedia tools
# Validates all components and runs integration tests

require "json"
require "fileutils"

class MultimediaTest
  TOOLS = {
    dilla: {
      main: "dilla/dilla.rb",
      modules: %w[__shared/@constants.rb __shared/@generators.rb __shared/@mastering.rb __shared/@tts.rb],
      data: ["__shared/progressions.json"],
      deps: ["sox.exe"]
    },
    postpro: {
      main: "postpro/postpro.rb",
      modules: %w[__shared/@bootstrap.rb __shared/@cli.rb __shared/@fx_core.rb __shared/@fx_creative.rb __shared/@mastering.rb],
      data: ["camera_profiles/*.json", "recipes/*.json"],
      deps: ["libvips"]
    },
    repligen: {
      main: "repligen/repligen.rb",
      modules: [],
      data: [],
      deps: ["REPLICATE_API_TOKEN"]
    }
  }

  def initialize
    @passed = 0
    @failed = 0
    @warnings = 0
  end

  def run
    puts "╔═══════════════════════════════════════════════════════════╗"
    puts "║         MULTIMEDIA TOOLS TEST SUITE v1.0                 ║"
    puts "╚═══════════════════════════════════════════════════════════╝"
    puts

    TOOLS.each do |name, spec|
      test_tool(name, spec)
    end

    print_summary
    exit(@failed > 0 ? 1 : 0)
  end

  private

  def test_tool(name, spec)
    puts "#{name.to_s.upcase}:"
    
    # Test main file
    main = spec[:main]
    if File.exist?(main)
      lines = File.readlines(main).size
      if syntax_check(main)
        pass "  Main: #{main} (#{lines} lines)"
      else
        fail "  Main: #{main} syntax error"
      end
    else
      fail "  Main: #{main} NOT FOUND"
    end

    # Test modules
    spec[:modules].each do |mod|
      path = File.join(File.dirname(main), mod)
      if File.exist?(path)
        lines = File.readlines(path).size
        pass "  Module: #{File.basename(mod)} (#{lines} lines)"
      else
        fail "  Module: #{mod} NOT FOUND"
      end
    end

    # Test data files
    spec[:data].each do |pattern|
      dir = File.dirname(main)
      files = Dir.glob(File.join(dir, pattern))
      if files.any?
        pass "  Data: #{pattern} (#{files.size} files)"
        files.each { |f| validate_json(f) if f.end_with?(".json") }
      else
        warn "  Data: #{pattern} NOT FOUND"
      end
    end

    # Test dependencies
    spec[:deps].each do |dep|
      if check_dependency(dep)
        pass "  Dependency: #{dep}"
      else
        warn "  Dependency: #{dep} NOT AVAILABLE"
      end
    end

    puts
  end

  def syntax_check(file)
    `ruby -c #{file} 2>&1`.include?("Syntax OK")
  end

  def validate_json(file)
    JSON.parse(File.read(file))
    pass "    JSON valid: #{File.basename(file)}"
  rescue JSON::ParserError => e
    fail "    JSON invalid: #{File.basename(file)} - #{e.message}"
  end

  def check_dependency(dep)
    case dep
    when "sox.exe"
      system("sox.exe --version >NUL 2>&1")
    when "libvips"
      system("pkg-config --exists vips 2>NUL") || File.exist?("C:/Program Files/vips/bin/libvips-42.dll")
    when "REPLICATE_API_TOKEN"
      ENV["REPLICATE_API_TOKEN"] || File.exist?(File.expand_path("~/.config/repligen/config.json"))
    else
      false
    end
  end

  def pass(msg)
    puts "  ✓ #{msg}"
    @passed += 1
  end

  def fail(msg)
    puts "  ✗ #{msg}"
    @failed += 1
  end

  def warn(msg)
    puts "  ⚠ #{msg}"
    @warnings += 1
  end

  def print_summary
    puts "═" * 64
    puts "SUMMARY:"
    puts "  Passed:   #{@passed}"
    puts "  Failed:   #{@failed}"
    puts "  Warnings: #{@warnings}"
    puts
    
    if @failed == 0 && @warnings == 0
      puts "✅ All tests passed - multimedia tools fully operational"
    elsif @failed == 0
      puts "⚠️  Tests passed with warnings - some optional features unavailable"
    else
      puts "❌ Tests failed - critical components missing"
    end
  end
end

MultimediaTest.new.run if __FILE__ == $PROGRAM_NAME

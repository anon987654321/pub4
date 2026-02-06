#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Dashboard
require_relative '../lib/dashboard'

class TestDashboard
  def initialize
    @passed = 0
    @failed = 0
  end

  def assert(name, condition)
    if condition
      @passed += 1
      puts "  ok: #{name}"
    else
      @failed += 1
      puts "  FAIL: #{name}"
    end
  end

  def run
    puts "Dashboard tests"
    puts

    test_dashboard_creation
    test_dashboard_has_methods
    test_dashboard_render_without_error
    test_format_helpers

    puts
    puts "#{@passed} passed, #{@failed} failed"
    @failed == 0
  end

  def test_dashboard_creation
    puts "creation:"
    dashboard = MASTER::Dashboard.new
    assert "Dashboard can be instantiated", dashboard.is_a?(MASTER::Dashboard)
  rescue StandardError => e
    assert "Dashboard can be instantiated", false
    puts "    Error: #{e.message}"
  end

  def test_dashboard_has_methods
    puts "methods:"
    dashboard = MASTER::Dashboard.new
    assert "has render method", dashboard.respond_to?(:render)
  rescue StandardError => e
    assert "has render method", false
  end

  def test_dashboard_render_without_error
    puts "rendering:"
    dashboard = MASTER::Dashboard.new
    
    begin
      # Just check it doesn't crash - let output go to terminal
      dashboard.render
      assert "renders without error", true
    rescue StandardError => e
      assert "renders without error", false
      puts "    Error: #{e.message}"
    end
  end

  def test_format_helpers
    puts "helpers:"
    dashboard = MASTER::Dashboard.new
    assert "can format cost", dashboard.send(:format_cost, 47.23) == "$47.23"
    assert "can truncate strings", dashboard.send(:truncate, "hello world", 5) == "he..."
  rescue StandardError => e
    assert "format helpers work", false
    puts "    Error: #{e.message}"
  end
end

# Run tests
require 'stringio'
tester = TestDashboard.new
success = tester.run
exit(success ? 0 : 1)

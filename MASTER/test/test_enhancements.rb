#!/usr/bin/env ruby
# frozen_string_literal: true

# Tests for new MASTER enhancements

require_relative '../lib/loader'
require 'fileutils'
require 'tmpdir'

class EnhancementsTestRunner
  def initialize
    @passed = 0
    @failed = 0
    @test_dir = nil
  end

  def assert(name, condition)
    if condition
      @passed += 1
      puts "  ✓ #{name}"
    else
      @failed += 1
      puts "  ✗ #{name}"
    end
  end

  def setup_test_dir
    @test_dir = Dir.mktmpdir('master_test_')
  end

  def cleanup_test_dir
    FileUtils.rm_rf(@test_dir) if @test_dir
  end

  def run
    puts "MASTER Enhancements Test Suite"
    puts "=" * 60
    puts

    test_memory
    test_monitor
    test_skills_structure
    test_harvester_structure

    puts
    puts "=" * 60
    puts "#{@passed} passed, #{@failed} failed"
    exit(@failed > 0 ? 1 : 0)
  end

  def test_memory
    puts "Memory System:"
    
    begin
      setup_test_dir
      
      # Test initialization
      memory = MASTER::Memory.new
      assert "Memory.new creates instance", memory.is_a?(MASTER::Memory)
      assert "starts with empty chunks", memory.chunks.empty?
      
      # Test storage
      ids = memory.store("This is test content for the memory system", 
                        tags: ["test", "ruby"], 
                        source: "test_suite")
      assert "store returns chunk IDs", ids.is_a?(Array) && !ids.empty?
      assert "chunks are stored", memory.chunks.size > 0
      
      # Test recall
      results = memory.recall("test content", k: 3)
      assert "recall returns results", results.is_a?(Array)
      assert "results have content", results.first&.key?(:content) if results.any?
      assert "results have metadata", results.first&.key?(:metadata) if results.any?
      
      # Test save/load
      save_path = File.join(@test_dir, 'test_memory.yml')
      memory.save(save_path)
      assert "save creates file", File.exist?(save_path)
      
      new_memory = MASTER::Memory.new
      new_memory.load(save_path)
      assert "load restores chunks", new_memory.chunks.size == memory.chunks.size
      
      # Test stats
      stats = memory.stats
      assert "stats returns hash", stats.is_a?(Hash)
      assert "stats has total_chunks", stats.key?(:total_chunks)
      
      # Test clear
      memory.clear
      assert "clear empties chunks", memory.chunks.empty?
      
    rescue => e
      puts "  ✗ Error in memory tests: #{e.message}"
      @failed += 1
    ensure
      cleanup_test_dir
    end
    
    puts
  end

  def test_monitor
    puts "Cost Monitor:"
    
    begin
      setup_test_dir
      
      # Test initialization
      log_path = File.join(@test_dir, 'test_usage.jsonl')
      monitor = MASTER::Monitor.new(log_path: log_path)
      assert "Monitor.new creates instance", monitor.is_a?(MASTER::Monitor)
      
      # Test tracking
      result = monitor.track("test_task", model: "cheap") do
        "test output"
      end
      assert "track executes block", result == "test output"
      assert "track creates log file", File.exist?(log_path)
      
      # Test explicit token tracking
      monitor.track_tokens("another_task", 
                          model: "strong", 
                          tokens_in: 100, 
                          tokens_out: 200,
                          duration: 1.5)
      assert "track_tokens logs entry", File.readlines(log_path).size >= 2
      
      # Test report generation
      report = monitor.report
      assert "report returns hash", report.is_a?(Hash)
      assert "report has summary", report.key?(:summary)
      assert "report has by_model stats", report.key?(:by_model)
      assert "summary has total_calls", report[:summary][:total_calls] > 0
      
      # Test print (should not crash)
      begin
        capture_stdout { monitor.print_report }
        assert "print_report executes", true
      rescue
        assert "print_report executes", false
      end
      
    rescue => e
      puts "  ✗ Error in monitor tests: #{e.message}"
      @failed += 1
    ensure
      cleanup_test_dir
    end
    
    puts
  end

  def test_skills_structure
    puts "Skills Structure:"
    
    # Test template exists
    template_path = File.join(MASTER::Paths.root, 'lib', 'skills', 'SKILL.md.template')
    assert "SKILL.md.template exists", File.exist?(template_path)
    
    # Test template has YAML frontmatter
    if File.exist?(template_path)
      content = File.read(template_path)
      assert "template has frontmatter", content.start_with?("---")
      assert "template has name field", content.include?("name:")
      assert "template has description", content.include?("description:")
      assert "template has examples", content.include?("## Examples")
    end
    
    # Test example skill exists
    example_path = File.join(MASTER::Paths.root, 'lib', 'skills', 'github_analyzer', 'SKILL.md')
    assert "github_analyzer skill exists", File.exist?(example_path)
    
    if File.exist?(example_path)
      content = File.read(example_path)
      assert "example has frontmatter", content.start_with?("---")
      assert "example is well-formed", content.include?("# Usage")
    end
    
    puts
  end

  def test_harvester_structure
    puts "Harvester Structure:"
    
    begin
      # Test harvester file exists and loads
      harvester_path = File.join(MASTER::Paths.root, 'lib', 'harvester.rb')
      assert "harvester.rb exists", File.exist?(harvester_path)
      
      # Test harvester class
      assert "Harvester class defined", defined?(MASTER::Harvester)
      
      # Test initialization
      harvester = MASTER::Harvester.new
      assert "Harvester.new creates instance", harvester.is_a?(MASTER::Harvester)
      assert "has empty harvested_data", harvester.harvested_data.empty?
      assert "has stats hash", harvester.stats.is_a?(Hash)
      
    rescue => e
      puts "  ✗ Error in harvester tests: #{e.message}"
      @failed += 1
    end
    
    puts
  end

  private

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end

# Run tests
EnhancementsTestRunner.new.run

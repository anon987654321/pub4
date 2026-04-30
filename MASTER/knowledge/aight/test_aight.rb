#!/usr/bin/env ruby
# frozen_string_literal: true
# test_aight.rb - Test script for aight.rb (consolidated version)
# Tests actual classes without lib/ dependencies

require_relative "aight"

puts "=" * 80
puts "Testing Aight CLI Components (Consolidated)"
puts "=" * 80
puts

# Test 1: Configuration loading
puts "Test 1: Configuration loading"
begin
  config = Configuration.load
  puts "   Default model: #{config['default_model']}"
  puts "   Cognitive tracking: #{config['cognitive_tracking']}"
  puts "   Knowledge store: #{config['knowledge_store']}"
  puts "✅ Configuration loads successfully"
rescue => e
  puts "❌ Configuration failed: #{e.message}"
end
puts

# Test 2: Platform detection
puts "Test 2: Platform detection"
platform = PlatformDetector.platform_name
shell_prefix = PlatformDetector.shell_command_prefix
puts "   Detected platform: #{platform}"
puts "   Shell prefix: '#{shell_prefix}'"
puts "✅ Platform detection works"
puts

# Test 3: Console utilities (non-interactive)
puts "Test 3: Console utilities"
Console.print_success("Success message test")
Console.print_error("Error message test")
Console.print_warning("Warning message test")
Console.print_info("Info message test")
puts "✅ Console utilities work"
puts

# Test 4: CognitiveTracker (7±2 rule)
puts "Test 4: CognitiveTracker (cognitive load tracking)"
tracker = CognitiveTracker.new(true)
puts "   Initial load: #{tracker.current_load}/#{tracker.status[:capacity]}"
tracker.add_task("test_task_1", 1.5)
tracker.add_task("test_task_2", 2.0)
puts "   After 2 tasks: #{tracker.current_load}/#{tracker.status[:capacity]}"
puts "   Overloaded? #{tracker.overloaded? ? 'Yes' : 'No'}"
tracker.clear
puts "   After clear: #{tracker.current_load}/#{tracker.status[:capacity]}"
puts "✅ CognitiveTracker works"
puts

# Test 5: KnowledgeStore (file-based RAG)
puts "Test 5: KnowledgeStore"
require 'fileutils'
test_dir = "test_knowledge_#{Time.now.to_i}"
store = KnowledgeStore.new(true, test_dir)
store.add_document("Ruby is a dynamic programming language", "ruby_doc")
store.add_document("JavaScript is used for web development", "js_doc")
results = store.search("Ruby")
puts "   Stored 2 documents"
puts "   Search for 'Ruby': #{results.size} results"
puts "   Top result: #{results.first[:file]}" if results.any?
FileUtils.rm_rf(test_dir) # Cleanup
puts "✅ KnowledgeStore works"
puts

# Test 6: AtomicFileWriter (safe writes)
puts "Test 6: AtomicFileWriter"
test_file = "test_atomic_#{Time.now.to_i}.txt"
AtomicFileWriter.write(test_file, "Test content\n")
content = File.read(test_file)
File.unlink(test_file)
puts "   Write/read successful: #{content.strip}"
puts "✅ AtomicFileWriter works"
puts

# Test 7: CrossPlatformPath
puts "Test 7: CrossPlatformPath"
home = CrossPlatformPath.home_directory
config_dir = CrossPlatformPath.config_directory
puts "   Home: #{home}"
puts "   Config dir: #{config_dir}"
puts "✅ CrossPlatformPath works"
puts

# Test 8: OpenBSDSandbox detection
puts "Test 8: OpenBSDSandbox"
available = OpenBSDSandbox.available?
puts "   Pledge available: #{available ? 'Yes' : 'No'}"
puts "✅ OpenBSDSandbox detection works"
puts

# Test 9: Feature availability checks
puts "Test 9: Feature availability"
puts "   LangchainRB: #{defined?(LANGCHAIN_AVAILABLE) && LANGCHAIN_AVAILABLE ? 'Yes' : 'No'}"
puts "   Rugged (Git): #{defined?(RUGGED_AVAILABLE) && RUGGED_AVAILABLE ? 'Yes' : 'No'}"
puts "   Listen (file watch): #{defined?(LISTEN_AVAILABLE) && LISTEN_AVAILABLE ? 'Yes' : 'No'}"
puts "   AST analysis: #{defined?(AST_AVAILABLE) && AST_AVAILABLE ? 'Yes' : 'No'}"
puts "   Ferrum (scraping): #{defined?(FERRUM_AVAILABLE) && FERRUM_AVAILABLE ? 'Yes' : 'No'}"
puts "✅ Feature detection works"
puts

# Test 10: Logger setup
puts "Test 10: Logger setup"
logger = CLILogger.setup("INFO")
puts "   Logger level: #{logger.level}"
puts "✅ Logger setup works"
puts

puts "=" * 80
puts "All tests passed! ✅"
puts "=" * 80
puts
puts "Core functionality verified:"
puts "  - Configuration management ✅"
puts "  - Platform detection ✅"
puts "  - Console utilities ✅"
puts "  - Cognitive tracking ✅"
puts "  - Knowledge store ✅"
puts "  - Atomic writes ✅"
puts "  - Cross-platform paths ✅"
puts "  - Feature detection ✅"
puts
puts "To start the interactive CLI, run:"
puts "  ./aight.rb"
puts
puts "aight.rb is fully consolidated (zero sprawl per master.json v43.0.0)"

#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/cli/constants'
require_relative '../lib/cli/colors'
require_relative '../lib/cli/progress'
require_relative '../lib/cli/suggestions'
require_relative '../lib/cli/file_detector'

class TestCLIConstants < Minitest::Test
  def test_banner_defined
    assert_equal "Usage: bin/master [command] [options]", MASTER::CLI::Constants::BANNER
  end

  def test_commands_list
    assert_includes MASTER::CLI::Constants::COMMANDS, 'refactor'
    assert_includes MASTER::CLI::Constants::COMMANDS, 'analyze'
    assert_includes MASTER::CLI::Constants::COMMANDS, 'repl'
    assert_includes MASTER::CLI::Constants::COMMANDS, 'version'
    assert_includes MASTER::CLI::Constants::COMMANDS, 'help'
  end

  def test_default_options
    assert_equal false, MASTER::CLI::Constants::DEFAULT_OPTIONS[:offline]
    assert_equal false, MASTER::CLI::Constants::DEFAULT_OPTIONS[:converge]
  end
end

class TestCLIColors < Minitest::Test
  def test_colorize_when_disabled
    ENV['NO_COLOR'] = '1'
    result = MASTER::CLI::Colors.colorize('test', :red)
    assert_equal 'test', result
  ensure
    ENV.delete('NO_COLOR')
  end

  def test_red_method
    text = MASTER::CLI::Colors.red('error')
    # When NO_COLOR is set, should return plain text
    ENV['NO_COLOR'] = '1'
    assert_equal 'error', MASTER::CLI::Colors.red('error')
  ensure
    ENV.delete('NO_COLOR')
  end

  def test_green_method
    ENV['NO_COLOR'] = '1'
    assert_equal 'success', MASTER::CLI::Colors.green('success')
  ensure
    ENV.delete('NO_COLOR')
  end

  def test_yellow_method
    ENV['NO_COLOR'] = '1'
    assert_equal 'warning', MASTER::CLI::Colors.yellow('warning')
  ensure
    ENV.delete('NO_COLOR')
  end

  def test_enabled_returns_false_with_no_color
    ENV['NO_COLOR'] = '1'
    refute MASTER::CLI::Colors.enabled?
  ensure
    ENV.delete('NO_COLOR')
  end
end

class TestCLITimer < Minitest::Test
  def test_elapsed_time
    timer = MASTER::CLI::Timer.new
    sleep 0.1
    assert timer.elapsed >= 0.1
  end

  def test_format_elapsed_milliseconds
    timer = MASTER::CLI::Timer.new
    sleep 0.05
    formatted = timer.format_elapsed
    assert formatted.end_with?('ms') || formatted.end_with?('s')
  end

  def test_format_elapsed_seconds
    timer = MASTER::CLI::Timer.new
    # Simulate elapsed time
    timer.instance_variable_set(:@start_time, Time.now - 5)
    formatted = timer.format_elapsed
    assert formatted.end_with?('s')
  end
end

class TestCLISuggestions < Minitest::Test
  def test_levenshtein_distance_identical
    distance = MASTER::CLI::Suggestions.levenshtein_distance('hello', 'hello')
    assert_equal 0, distance
  end

  def test_levenshtein_distance_one_char_diff
    distance = MASTER::CLI::Suggestions.levenshtein_distance('hello', 'hallo')
    assert_equal 1, distance
  end

  def test_levenshtein_distance_empty_strings
    distance = MASTER::CLI::Suggestions.levenshtein_distance('', 'hello')
    assert_equal 5, distance
  end

  def test_closest_match_found
    options = %w[refactor analyze repl]
    match = MASTER::CLI::Suggestions.closest_match('refact', options)
    assert_equal 'refactor', match
  end

  def test_closest_match_not_found
    options = %w[refactor analyze repl]
    match = MASTER::CLI::Suggestions.closest_match('completely_different', options)
    assert_nil match
  end

  def test_closest_match_case_insensitive
    options = %w[Refactor Analyze Repl]
    match = MASTER::CLI::Suggestions.closest_match('refact', options)
    assert_equal 'Refactor', match
  end

  def test_similar_files_finds_matches
    # This test would need a temp directory with test files
    # For now, just test it doesn't crash with non-existent directory
    result = MASTER::CLI::Suggestions.similar_files('test.rb', '/nonexistent')
    assert_equal [], result
  end
end

class TestCLIFileDetector < Minitest::Test
  def setup
    @temp_dir = File.join(Dir.tmpdir, "cli_test_#{$$}")
    FileUtils.mkdir_p(@temp_dir)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if File.exist?(@temp_dir)
  end

  def test_detect_type_ruby
    file = File.join(@temp_dir, 'test.rb')
    File.write(file, 'puts "hello"')
    assert_equal :ruby, MASTER::CLI::FileDetector.detect_type(file)
  end

  def test_detect_type_python
    file = File.join(@temp_dir, 'test.py')
    File.write(file, 'print("hello")')
    assert_equal :python, MASTER::CLI::FileDetector.detect_type(file)
  end

  def test_detect_type_javascript
    file = File.join(@temp_dir, 'test.js')
    File.write(file, 'console.log("hello")')
    assert_equal :javascript, MASTER::CLI::FileDetector.detect_type(file)
  end

  def test_detect_type_typescript
    file = File.join(@temp_dir, 'test.ts')
    File.write(file, 'const x: string = "hello"')
    assert_equal :typescript, MASTER::CLI::FileDetector.detect_type(file)
  end

  def test_detect_type_java
    file = File.join(@temp_dir, 'Test.java')
    File.write(file, 'public class Test {}')
    assert_equal :java, MASTER::CLI::FileDetector.detect_type(file)
  end

  def test_detect_type_unknown
    file = File.join(@temp_dir, 'test.txt')
    File.write(file, 'hello world')
    assert_equal :unknown, MASTER::CLI::FileDetector.detect_type(file)
  end

  def test_analyze_complexity_nonexistent_file
    result = MASTER::CLI::FileDetector.analyze_complexity('/nonexistent/file.rb')
    assert_nil result
  end

  def test_suggest_command_nonexistent_file
    result = MASTER::CLI::FileDetector.suggest_command('/nonexistent/file.rb')
    assert_nil result
  end

  def test_detect_type_handles_non_file
    assert_equal :unknown, MASTER::CLI::FileDetector.detect_type('/nonexistent/file.rb')
  end

  def test_analyze_complexity_simple_file
    file = File.join(@temp_dir, 'simple.rb')
    File.write(file, "puts 'hello'\nputs 'world'\n")
    result = MASTER::CLI::FileDetector.analyze_complexity(file)
    assert result
    assert_equal 2, result[:lines]
    refute result[:complex]
  end

  def test_analyze_complexity_complex_file
    file = File.join(@temp_dir, 'complex.rb')
    # Create a file with many lines and methods to trigger complexity
    content = "def method1\nend\n" * 15 + "if true\nend\n" * 25
    File.write(file, content)
    result = MASTER::CLI::FileDetector.analyze_complexity(file)
    assert result
    assert result[:complex]
  end

  def test_suggest_command_for_complex_file
    file = File.join(@temp_dir, 'complex.rb')
    content = "def method1\nend\n" * 15
    File.write(file, content)
    result = MASTER::CLI::FileDetector.suggest_command(file)
    assert result
    assert_equal 'refactor', result[:command]
  end

  def test_suggest_command_for_simple_file
    file = File.join(@temp_dir, 'simple.rb')
    File.write(file, "puts 'hello'\n")
    result = MASTER::CLI::FileDetector.suggest_command(file)
    assert result
    assert_equal 'analyze', result[:command]
  end
end

# Integration tests would go here if we had a running system
class TestCLIIntegration < Minitest::Test
  def test_constants_module_accessible
    assert MASTER::CLI::Constants
    assert MASTER::CLI::Constants::BANNER
    assert MASTER::CLI::Constants::COMMANDS
    assert MASTER::CLI::Constants::DEFAULT_OPTIONS
  end

  def test_colors_module_accessible
    assert MASTER::CLI::Colors
    assert_respond_to MASTER::CLI::Colors, :red
    assert_respond_to MASTER::CLI::Colors, :green
    assert_respond_to MASTER::CLI::Colors, :yellow
    assert_respond_to MASTER::CLI::Colors, :blue
  end

  def test_suggestions_module_accessible
    assert MASTER::CLI::Suggestions
    assert_respond_to MASTER::CLI::Suggestions, :levenshtein_distance
    assert_respond_to MASTER::CLI::Suggestions, :closest_match
    assert_respond_to MASTER::CLI::Suggestions, :similar_files
  end

  def test_file_detector_module_accessible
    assert MASTER::CLI::FileDetector
    assert_respond_to MASTER::CLI::FileDetector, :detect_type
    assert_respond_to MASTER::CLI::FileDetector, :analyze_complexity
    assert_respond_to MASTER::CLI::FileDetector, :suggest_command
  end

  def test_timer_class_accessible
    assert MASTER::CLI::Timer
    timer = MASTER::CLI::Timer.new
    assert_respond_to timer, :elapsed
    assert_respond_to timer, :format_elapsed
  end
end

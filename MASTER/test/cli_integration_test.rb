# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/master'
require_relative '../lib/cli'

class FakeLLM
  attr_reader :persona, :total_cost, :backend, :context_files, :last_tokens, :last_cached

  def initialize
    @persona = { name: 'fake' }
    @total_cost = 0.0
    @backend = :http
    @context_files = []
    @last_tokens = { input: 0, output: 0 }
    @last_cached = false
  end

  def chat(message)
    MASTER::Result.ok("echo: #{message}")
  end

  def clear_history
  end

  def add_context_file(path)
    return MASTER::Result.err("Not found: #{path}") unless File.exist?(path)

    @context_files << path unless @context_files.include?(path)
    MASTER::Result.ok(path)
  end

  def drop_context_file(path)
    return MASTER::Result.err("Not found: #{path}") unless @context_files.include?(path)

    @context_files.delete(path)
    MASTER::Result.ok(path)
  end

  def clear_context_files
    @context_files.clear
  end

  def set_backend(name)
    return MASTER::Result.err('Backend required') unless name

    key = name.to_s.downcase.to_sym
    return MASTER::Result.err('Unknown backend') unless %i[http ruby_llm].include?(key)

    @backend = key
    MASTER::Result.ok(@backend)
  end
  
  def status
    { connected: true }
  end
end

class TestCLI < MASTER::CLI
  private

  def setup_completion
  end

  def load_history
  end

  def setup_crash_recovery
  end

  def save_history
  end

  def save_state
  end
  
  def load_state
  end
  
  def auto_scan_on_boot
    # Skip auto-scan in tests
  end
  
  def load_self_awareness
    # Skip in tests
  end
end

class TestCLIIntegration < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('master_cli_integration')
    @file = File.join(@dir, 'test.rb')
    File.write(@file, "puts 'hello'\n")
    @cli = TestCLI.new(llm: FakeLLM.new, root: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Test Constants Extraction
  def test_constants_are_accessible
    assert_kind_of String, MASTER::CLI::Constants::Colors::C_RESET
    assert_kind_of String, MASTER::CLI::Constants::Icons::ICON_OK
    assert_kind_of Array, MASTER::CLI::Constants::Data::QUOTES
    assert_kind_of Hash, MASTER::CLI::Constants::Achievements::ACHIEVEMENTS
    assert_kind_of Hash, MASTER::CLI::Constants::Aliases::ALIASES
    assert_kind_of Array, MASTER::CLI::Constants::Commands::COMMANDS
    assert_kind_of Integer, MASTER::CLI::Constants::Config::HISTORY_LIMIT
  end

  # Test Feature: Context Defaults
  def test_context_defaults_file
    @cli.remember_file(@file)
    assert_equal @file, @cli.default_file
  end

  def test_context_defaults_dir
    subdir = File.join(@dir, 'subdir')
    Dir.mkdir(subdir)
    @cli.remember_dir(subdir)
    assert_equal subdir, @cli.default_dir
  end

  # Test Feature: Rich History
  def test_rich_history_recording
    # Manually record a command since process_input doesn't trigger the full flow
    @cli.record_command_history('status', success: true, elapsed_ms: 10)
    history_output = @cli.show_rich_history(5)
    assert_includes history_output, 'status'
  end

  # Test Feature: Error Solutions
  def test_error_with_solution
    error = StandardError.new("File not found: test.rb")
    solution = @cli.error_with_solution(error)
    assert_includes solution, "Check file path is correct"
    assert_includes solution, "Use 'ls' to list files"
  end

  # Test Feature: Inline Help
  def test_inline_help_hints
    hint = @cli.inline_help_for('ask')
    assert_equal 'Query LLM with optional context', hint
  end

  # Test Feature: Next Actions
  def test_next_actions_suggestions
    @cli.remember_file(@file)
    suggestions = @cli.suggest_next_actions
    assert suggestions.any? { |s| s.include?('edit') || s.include?('cat') }
  end

  # Test Feature: LLM Cache
  def test_llm_cache_initialization
    stats = @cli.cache_stats
    assert_includes stats, 'Cache'
  end

  def test_llm_cache_clear
    result = @cli.clear_cache
    assert_equal 'LLM cache cleared', result
  end

  # Test Feature: Auto Scan
  def test_auto_scan_toggle
    result = @cli.disable_auto_scan
    assert_equal 'Auto-scan disabled', result
    
    result = @cli.enable_auto_scan
    assert_equal 'Auto-scan enabled', result
  end

  # Test Feature: Pattern Learning
  def test_pattern_learning_initialization
    result = @cli.show_learned_patterns
    assert(result.include?('patterns') || result.include?('No patterns'))
  end

  # Test Feature: Command Chaining
  def test_command_chaining_split
    commands = @cli.split_command_chain('status && history')
    assert_equal 2, commands.size
    assert_equal 'status', commands[0][:command]
    assert_equal '&&', commands[0][:operator]
    assert_equal 'history', commands[1][:command]
  end

  def test_command_chaining_sequential
    commands = @cli.split_command_chain('status ; history ; cost')
    assert_equal 3, commands.size
    assert_equal 'status', commands[0][:command]
    assert_equal 'history', commands[1][:command]
    assert_equal 'cost', commands[2][:command]
  end

  # Test Feature: Templates/Workflows
  def test_workflow_listing
    result = @cli.list_templates
    assert_includes result, 'refactor-flow'
    assert_includes result, 'audit-flow'
  end

  # Test Integration: New Commands
  def test_cache_command
    result = @cli.process_input('cache')
    assert_includes result, 'Cache'
  end

  def test_patterns_command
    result = @cli.process_input('patterns')
    assert result
  end

  def test_auto_scan_command
    result = @cli.process_input('auto-scan off')
    assert_equal 'Auto-scan disabled', result
  end

  def test_workflow_command_list
    result = @cli.process_input('workflow')
    assert_includes result, 'refactor-flow'
  end

  # Test backwards compatibility
  def test_original_commands_still_work
    result = @cli.process_input('status')
    assert_includes result, 'Backend'
    
    result = @cli.process_input('cost')
    assert result
  end
end

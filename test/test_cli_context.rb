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
end

class TestCLIContext < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('master_cli')
    @file = File.join(@dir, 'context.txt')
    File.write(@file, "hello\n")
    @cli = TestCLI.new(llm: FakeLLM.new, root: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_context_lifecycle
    assert_equal 'Context empty', @cli.process_input('context list')
    assert_equal "Context added: #{@file}", @cli.process_input("context add #{@file}")
    assert_includes @cli.process_input('context list'), @file
    assert_equal "Context removed: #{@file}", @cli.process_input("context drop #{@file}")
    assert_equal 'Context empty', @cli.process_input('context list')
  end

  def test_context_relative_path
    assert_equal 'Context empty', @cli.process_input('context')
    assert_includes @cli.process_input('context add context.txt'), @file
    assert_includes @cli.process_input('context'), @file
    assert_equal "Context removed: #{@file}", @cli.process_input('context drop context.txt')
  end

  def test_context_multi_add_drop
    other = File.join(@dir, 'other.txt')
    File.write(other, "other\n")
    output = @cli.process_input("context add #{@file} #{other}")
    assert_includes output, "Context added: #{@file}"
    assert_includes output, "Context added: #{other}"
    list = @cli.process_input('context list')
    assert_includes list, @file
    assert_includes list, other
    removed = @cli.process_input("context drop #{@file} #{other}")
    assert_includes removed, "Context removed: #{@file}"
    assert_includes removed, "Context removed: #{other}"
    assert_equal 'Context empty', @cli.process_input('context list')
  end

  def test_context_errors_and_clear
    missing = File.join(@dir, 'missing.txt')
    assert_equal "Not found: #{missing}", @cli.process_input("context add #{missing}")
    assert_equal "Not found: #{missing}", @cli.process_input("context drop #{missing}")
    assert_equal 'Context cleared', @cli.process_input('context clear')
  end

  def test_backend_switching
    assert_equal 'Usage: backend <http|ruby_llm>', @cli.process_input('backend')
    assert_equal 'Backend: http', @cli.process_input('backend http')
    assert_equal 'Backend: ruby_llm', @cli.process_input('backend ruby_llm')
    assert_equal 'Unknown backend', @cli.process_input('backend nope')
    result = @cli.llm.set_backend(nil)
    assert result.err?
    assert_equal 'Backend required', result.error
  end

  def test_status_and_chat_flow
    status = @cli.process_input('status')
    assert_includes status, 'Backend: http'
    assert_includes status, 'Context files: 0'
    assert_equal 'echo: hello', @cli.process_input('ask hello')
  end
end

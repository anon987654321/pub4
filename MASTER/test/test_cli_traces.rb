#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../lib/master'

class TestCLIExecutionTraces < Minitest::Test
  def setup
    ENV['MASTER_NO_CONFIG_WRITE'] = '1'
    ENV.delete('OPENROUTER_API_KEY')
    @cli = MASTER::CLI.new
  end

  def teardown
    ENV.delete('MASTER_NO_CONFIG_WRITE')
    ENV.delete('MASTER_SIMULATE_OPTIMIZE')
  end

  def test_status_trace_includes_model
    output = @cli.process_input('status')
    assert_includes output, 'Model:'
    assert_includes output, 'Last tokens:'
  end

  def test_edge_case_usage
    before_count = @cli.instance_variable_get(:@command_count)
    assert_nil @cli.process_input(' ')
    assert_equal before_count, @cli.instance_variable_get(:@command_count)
    assert_equal 'Usage: clean <file>', @cli.process_input('clean')
    assert_equal 'Usage: ask <message>', @cli.process_input('ask')
    assert_equal 'History cleared.', @cli.process_input('clear')
  end

  def test_missing_paths
    assert_match(/Not found/, @cli.process_input('cd /nope'))
    assert_match(/Not found/, @cli.process_input('cat /nope'))
  end

  def test_tier_switching
    assert_equal "Current tier: #{@cli.llm.current_tier}", @cli.process_input('tier')
    assert_equal 'Tier set to fast', @cli.process_input('tier fast')
    assert_equal :fast, @cli.llm.current_tier
    assert_equal 'Unknown tier: nope', @cli.process_input('tier nope')
  end

  def test_llm_status_snapshot
    status = @cli.llm.status
    assert_equal false, status[:connected]
    assert status[:model]
  end

  def test_help_includes_tier
    help = @cli.process_input('help')
    assert_includes help, 'tier <name>'
  end

  def test_missing_api_key_response
    result = @cli.process_input('ask hello')
    assert_includes result, 'Error:'
  end

  def test_optimize_simulation
    ENV['MASTER_SIMULATE_OPTIMIZE'] = '1'
    file = Tempfile.new(['optimize', '.rb'])
    file.write("def demo \n  puts 'hi'  \nend")
    file.close

    result = @cli.process_input("optimize #{file.path}")
    updated = File.read(file.path)

    assert_includes result, 'Self-optimization complete'
    assert updated.end_with?("\n")
  ensure
    file.unlink if file
  end
end

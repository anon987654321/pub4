# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPrescan < Minitest::Test
  def test_prescan_module_exists
    assert defined?(MASTER::Prescan), "Prescan module should be defined"
  end

  def test_prescan_responds_to_run
    assert_respond_to MASTER::Prescan, :run
  end

  def test_prescan_can_run_on_master2
    # Suppress output during test
    old_stdout = $stdout
    $stdout = StringIO.new
    
    result = MASTER::Prescan.run(MASTER.root)
    
    $stdout = old_stdout
    
    assert result.is_a?(Hash), "Prescan should return a hash"
    assert result.key?(:tree), "Should check tree structure"
    assert result.key?(:sprawl), "Should check for sprawl"
    assert result.key?(:git_status), "Should check git status"
    assert result.key?(:recent_commits), "Should check recent commits"
  end

  def test_prescan_detects_large_files
    # Prescan should detect any files over 500 lines
    # Suppress output during test
    old_stdout = $stdout
    $stdout = StringIO.new
    
    result = MASTER::Prescan.run(MASTER.root)
    
    $stdout = old_stdout
    
    # sprawl is an array of large files
    assert result[:sprawl].is_a?(Array), "Sprawl should be an array"
  end
end

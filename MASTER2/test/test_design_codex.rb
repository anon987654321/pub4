# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestDesignCodex < Minitest::Test
  def test_design_codex_file_exists
    path = File.join(MASTER.root, "data", "design_codex.yml")
    assert File.exist?(path)
  end

  def test_design_codex_loads
    rules = MASTER::DesignCodex.rules
    assert rules.is_a?(Hash)
    refute_empty rules
    assert rules[:typography].is_a?(Hash)
    assert rules[:code_craft].is_a?(Hash)
  end

  def test_codify_command_available
    assert MASTER::Commands.respond_to?(:codify, true)
    assert MASTER::Commands.respond_to?(:doctor, true)
    assert MASTER::Commands.respond_to?(:bootstrap, true)
    assert MASTER::Commands.respond_to?(:history_dig, true)
  end
end

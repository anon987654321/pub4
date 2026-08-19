# frozen_string_literal: true

require_relative "test_helper"

class TestBuildFast < Minitest::Test
  def test_build_fast_exposes_probe_commands
    container = Master::Builder.build_fast(root: Master::ROOT)

    assert container[:pipeline]
    assert container[:renderer]
    assert container[:scanner]
    assert_equal "fast", container[:agent].model
  end

  def test_fast_command_registry_keys
    container = Master::Builder.build_fast(root: Master::ROOT)
    commands = container[:commands]

    # status and help only: /orient was removed 2026-05-20 as a useless
    # wrapper (project_context.yml), and the fast registry is deliberately
    # the smallest surface that answers a health question.
    %w[status help].each do |name|
      assert commands.key?(name), "missing fast command /#{name}"
    end
  end

  def test_fast_pipeline_is_turn_adapter
    container = Master::Builder.build_fast(root: Master::ROOT)
    assert_instance_of Master::CLI::TurnPipeline, container[:pipeline]
  end
end

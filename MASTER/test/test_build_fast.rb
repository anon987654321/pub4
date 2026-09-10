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

  # The evidence contract reaches the render stage off the container. TurnRouter
  # reads container[:output_guard] and skips the check when it is nil, so a wire
  # that quietly went missing would read exactly like a tree with nothing to
  # report -- which is what the guard was for its whole life before this.
  def test_build_fast_carries_both_output_gates
    container = Master::Builder.build_fast(root: Master::ROOT)

    assert container[:output_check], "no OutputCheck in the container"
    assert_instance_of Master::Voice::OutputGuard, container[:output_guard]
  end

  def test_fast_pipeline_is_turn_adapter
    container = Master::Builder.build_fast(root: Master::ROOT)
    assert_instance_of Master::CLI::Pipeline::Turn, container[:pipeline]
  end
end

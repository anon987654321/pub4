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
    route = container[:pipeline].instance_variable_get(:@stages)
      .find { |stage| stage.is_a?(Master::Now::Stages::Route) }
    commands = route.instance_variable_get(:@commands)

    %w[status orient help tools].each do |name|
      assert commands.key?(name), "missing fast command /#{name}"
    end
  end
end
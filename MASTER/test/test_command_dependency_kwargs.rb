# frozen_string_literal: true

require_relative "test_helper"
require "cli/command_registry/command"

class TestCommandDependencyKwargs < Minitest::Test
  class Receiver
    def keyword_only(required_dep:, optional_dep: "default", ctx: nil)
      { required_dep:, optional_dep:, ctx: }
    end
  end

  # A dependency passed positionally to a keyword-only method reaches it
  # through dependency_kwargs. A nil one is still a value, and dropping it
  # there reads to the callee as a missing keyword.
  def test_required_nil_dependency_is_still_passed_through
    command = Master::CLI::CommandRegistry::Command.new(Receiver.new, :keyword_only, nil, "explicit optional")
    result = command.call(nil)

    assert_nil result[:required_dep]
    assert_equal "explicit optional", result[:optional_dep]
  end

  def test_optional_nil_dependency_falls_back_to_default
    command = Master::CLI::CommandRegistry::Command.new(Receiver.new, :keyword_only, "req", nil)
    result = command.call(nil)

    assert_equal "req", result[:required_dep]
    assert_equal "default", result[:optional_dep]
  end
end

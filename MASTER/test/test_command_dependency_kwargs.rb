# frozen_string_literal: true

require_relative "test_helper"
require "cli/command_registry/command"

class TestCommandDependencyKwargs < Minitest::Test
  class Receiver
    def keyword_only(required_dep:, optional_dep: "default", ctx: nil)
      { required_dep:, optional_dep:, ctx: }
    end
  end

  # Regression: dispatch_review's council_stage is nil in lean boot mode.
  # command() is called with it as a positional arg; the positional call
  # fails (dispatch_review takes only keywords), so Command retries via
  # dependency_kwargs, which used to `.compact` away every nil value --
  # including required ones -- turning a legitimate nil dependency into
  # "missing keyword: :council_stage".
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

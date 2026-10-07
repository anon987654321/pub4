# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/command_registry"

class TestConvergenceCommands < Minitest::Test
  def test_new_convergence_commands_have_dispatchers
    registry = Master::CLI::CommandRegistry
    commands = registry.build(
      infra: { session: Master::Trace::Session.new, config: {}, root: Master::ROOT, bus: nil },
      ai: { agent: nil },
      root: Master::ROOT,
    )
    %w[wishlist size explain prove].each do |verb|
      assert_equal "dispatch_#{verb}", commands.fetch(verb).method_name.to_s
    end
  end
end

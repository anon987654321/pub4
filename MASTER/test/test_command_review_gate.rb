# frozen_string_literal: true

require_relative "test_helper"
require "cli/command_registry/command"
require_relative "../lib/cli/command_registry/review"
require_relative "../lib/operator/gate_chain"

class TestCommandReviewGate < Minitest::Test
  class Receiver
    attr_reader :calls

    def initialize
      @calls = []
    end

    def risky_action(ctx: nil)
      @calls << ctx
      "did the risky thing"
    end
  end

  # Matches OpenCrabs' skill-level review_gate: true -- a command with
  # side effects must not run them until explicitly confirmed, even under
  # otherwise-autonomous operation. /commit is the first consumer (runs
  # git add -u + git commit with an LLM-written message, previously with
  # zero confirmation at all).
  def test_gated_command_refuses_without_confirmation
    receiver = Receiver.new
    command = Master::CLI::CommandRegistry::Command.new(receiver, :risky_action, review_gate: true)

    result = command.call({ args: "" })

    assert_match(/review_gate/, result)
    assert_empty receiver.calls
  end

  def test_gated_command_runs_once_confirmed
    receiver = Receiver.new
    command = Master::CLI::CommandRegistry::Command.new(receiver, :risky_action, review_gate: true)

    result = command.call({ args: "--confirm" })

    assert_equal "did the risky thing", result
    assert_equal 1, receiver.calls.size
  end

  # The confirmation flag is this gate's own bookkeeping -- the
  # underlying handler shouldn't have to know it exists.
  def test_confirm_flag_is_stripped_before_reaching_the_handler
    receiver = Receiver.new
    command = Master::CLI::CommandRegistry::Command.new(receiver, :risky_action, review_gate: true)

    command.call({ args: "some-arg --confirm" })

    assert_equal "some-arg", receiver.calls.first[:args]
  end

  def test_ungated_command_runs_immediately
    receiver = Receiver.new
    command = Master::CLI::CommandRegistry::Command.new(receiver, :risky_action)

    result = command.call({ args: "" })

    assert_equal "did the risky thing", result
    assert_equal 1, receiver.calls.size
  end

  def test_fix_proof_scope_resolves_from_the_repository_root
    # The worktree session went; the gate chain resolves which trees a /fix target proves.
    registry = Operator::GateChain

    assert_equal ["MASTER"], registry.trees_for_target("MASTER")
    assert_equal ["RAILS"], registry.trees_for_target("RAILS/brgen")
  end

  def test_bare_fix_and_dot_keep_the_default_proof_scoped_to_master
    # The worktree session went; the gate chain resolves which trees a /fix target proves.
    registry = Operator::GateChain

    assert_equal ["MASTER"], registry.trees_for_target("")
    assert_equal ["MASTER"], registry.trees_for_target(".")
    assert_equal ["MASTER"], registry.trees_for_target("master")
    assert_equal ["MASTER"], registry.trees_for_target("lib/io")
    assert_equal %w[MASTER RAILS OPENBSD STUDIO],
                 registry.trees_for_target("all")
  end

  def test_gated_command_handles_nil_ctx
    receiver = Receiver.new
    command = Master::CLI::CommandRegistry::Command.new(receiver, :risky_action, review_gate: true)

    result = command.call(nil)

    assert_match(/review_gate/, result)
    assert_empty receiver.calls
  end
end

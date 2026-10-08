# frozen_string_literal: true

require_relative "test_helper"

class TestCliFaceDispatch < Minitest::Test
  def test_master_boot_loads_the_master_operator_mode
    assert defined?(Master::Operator::Mode), "interactive fold routing needs Master::Operator::Mode"
  end

  def test_fix_registry_loads_the_foreign_gate_chain_before_dispatch
    require_relative "../lib/cli/command_registry/review"

    assert defined?(::Operator::GateChain), "fix registry must load top-level Operator::GateChain"
  end

  def test_face_pauses_the_repl_background_scanner
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@running, true)
    session.instance_variable_set(:@bg_thread, Object.new.tap { |o| def o.alive? = true })
    events = []

    session.define_singleton_method(:stop_background_loop) { events << :stop }
    session.define_singleton_method(:start_background_loop) { events << :start }

    Master::CLI::CommandRegistry.stub(:dispatch_face, -> { events << :face; "face0: closed" }) do
      assert_nil session.send(:run_face)
    end

    assert_equal %i[stop face start], events
  end

  def test_face_is_dispatched_synchronously_from_repl
    session = Master::CLI::Session.allocate
    called = false

    Master::CLI::CommandRegistry.stub(:dispatch_face, -> { called = true; "face0: closed" }) do
      assert_nil session.send(:dispatch_core_slash_command, "/face")
    end

    assert called
  end
  def test_known_slash_commands_bypass_the_llm_turn
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, {
      commands: {
        "play" => Master::CLI::CommandRegistry::Command.new { |ctx| "dilla0: #{ctx.fetch(:args)}" }
      }
    })
    renderer = Object.new
    def renderer.render(text, **); text; end
    session.instance_variable_set(:@refs, Struct.new(:renderer).new(renderer))
    out, = capture_io { session.send(:dispatch_core_slash_command, "/play flying lotus") }
    assert_includes out, "dilla0: flying lotus"
  end

  def test_unknown_slash_command_still_reaches_the_sentence_router
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, { commands: {} })
    assert_equal :unhandled, session.send(:dispatch_core_slash_command, "/not-a-command")
  end

end

# frozen_string_literal: true

require_relative "test_helper"

class TestCliFaceDispatch < Minitest::Test
  def test_master_boot_loads_the_master_operator_mode
    assert defined?(Master::Operator::Mode), "interactive fold routing needs Master::Operator::Mode"
  end

  def test_fix_registry_loads_the_foreign_check_chain_before_dispatch
    require_relative "../lib/cli/command_registry/review"

    assert defined?(::Operator::CheckChain), "fix registry must load top-level Operator::CheckChain"
  end

  def test_face_pauses_the_repl_background_scanner
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@running, true)
    session.instance_variable_set(:@bg_thread, Object.new.tap { |o| def o.alive? = true })
    events = []

    session.define_singleton_method(:stop_background_loop) { events << :stop }
    session.define_singleton_method(:start_background_loop) { events << :start }

    Master::CLI::CommandRegistry.stub(:dispatch_face, ->(**) { events << :face; "face0: closed" }) do
      assert_nil session.send(:run_face)
    end

    assert_equal %i[stop face start], events
  end

  def test_leaving_the_face_does_not_start_a_scanner_that_was_off
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@running, true)
    events = []

    session.define_singleton_method(:stop_background_loop) { events << :stop }
    session.define_singleton_method(:start_background_loop) { events << :start }

    Master::CLI::CommandRegistry.stub(:dispatch_face, ->(**) { events << :face; "face0: closed" }) do
      assert_nil session.send(:run_face)
    end

    assert_equal %i[stop face], events
  end

  def test_face_is_dispatched_synchronously_from_repl
    session = Master::CLI::Session.allocate
    called = false

    Master::CLI::CommandRegistry.stub(:dispatch_face, ->(**) { called = true; "face0: closed" }) do
      assert_nil session.send(:dispatch_core_slash_command, "/face")
    end

    assert called
  end
  def test_known_slash_commands_bypass_the_llm_turn
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, {
      commands: {
        "play" => Master::CLI::CommandRegistry::Command.new { |ctx| "dilla0: #{ctx.fetch(:args)}" },
      },
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

  def test_face_turn_uses_the_session_dispatcher_and_shared_history
    session = Master::CLI::Session.allocate
    calls = []
    history = []
    session.define_singleton_method(:handle_repl_line) do |input|
      calls << input
      :handled
    end

    result = Reline::HISTORY.stub(:<<, ->(line) { history << line }) do
      session.send(:run_face_turn, "  use the face input  ")
    end

    assert_equal :handled, result
    assert_equal ["  use the face input  "], calls
    assert_equal ["  use the face input  "], history
  end

  def test_face_slash_face_returns_to_the_existing_repl
    session = Master::CLI::Session.allocate
    called = false
    session.define_singleton_method(:handle_repl_line) { |_input| called = true }

    result = Reline::HISTORY.stub(:<<, ->(_line) {}) do
      session.send(:run_face_turn, "/face")
    end

    assert_equal :face_toggle, result
    refute called
  end

  def test_natural_language_from_the_face_uses_the_face_presentation_of_the_session_pipeline
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@face_open, true)
    session.define_singleton_method(:host_refusal_for) { |_line| nil }
    calls = []
    session.define_singleton_method(:run_input) do |line, presentation:|
      calls << [line, presentation]
      :result
    end

    assert_equal :result, session.send(:run_agent_turn, "hello from the face")
    assert_equal [["hello from the face", :face]], calls
  end

  def test_face_window_treats_face_toggle_as_a_presentation_change
    window = Master::CLI::Face::Window.allocate
    window.define_singleton_method(:set) { |*| nil }
    window.define_singleton_method(:think) { |_text| :face_toggle }

    window.send(:answer, "/face")

    assert window.instance_variable_get(:@closing)
    refute window.instance_variable_get(:@exit_requested)
  end

  def test_face_cancellation_reaches_the_session_token_and_event_bus
    session = Master::CLI::Session.allocate
    token = Master::Core::CancellationToken.new.activate!
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |name, **payload| events << [name, payload] }
    session.instance_variable_set(:@turn_cancellation, token)
    session.instance_variable_set(:@turn_children, :children)
    session.instance_variable_set(:@refs, Struct.new(:bus).new(bus))

    cooperative = session.send(:cancel_face_turn, Object.new, :children)

    assert cooperative
    assert_predicate token, :cancelled?
    assert_equal "face interrupted", token.reason
    assert_equal "user:interrupt", events.first.first
    assert_equal :children, events.first.last[:children]
  end

  def test_face_exit_exits_the_master_session
    session = Master::CLI::Session.allocate
    exited = false
    session.define_singleton_method(:stop_background_loop) {}
    session.define_singleton_method(:exit_cli) { exited = true }

    Master::CLI::CommandRegistry.stub(:dispatch_face, ->(**) { "face0: exit" }) do
      session.send(:run_face)
    end

    assert exited
  end

end

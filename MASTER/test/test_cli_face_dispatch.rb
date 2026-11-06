# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face/transcriber"
require_relative "../lib/cli/face/ear"

class TestCliFaceDispatch < Minitest::Test
  def test_master_boot_loads_the_master_operator_mode
    assert defined?(Master::Operator::Mode), "interactive fold routing needs Master::Operator::Mode"
  end

  def test_fix_registry_loads_the_foreign_check_chain_before_dispatch
    require_relative "../lib/cli/command_registry/review"

    assert defined?(::Operator::CheckChain), "fix registry must load top-level Operator::CheckChain"
  end

  def test_face_redraws_without_stopping_the_existing_session
    session = Master::CLI::Session.allocate
    events = []
    session.define_singleton_method(:print_face_overlay) { events << :overlay }
    session.define_singleton_method(:stop_background_loop) { events << :stop }
    session.define_singleton_method(:start_background_loop) { events << :start }

    assert_nil session.send(:run_face)

    assert_equal [:overlay], events
  end

  def test_slash_face_redraws_the_overlay_inside_the_repl
    session = Master::CLI::Session.allocate
    events = []
    session.define_singleton_method(:print_face_overlay) { events << :overlay }

    assert_nil session.send(:dispatch_core_slash_command, "/face")

    assert_equal [:overlay], events
  end
  def test_run_input_starts_a_new_ground_truth_turn_before_dispatch
    session = Master::CLI::Session.allocate
    truth = Master::Ground::Truth.new
    session.instance_variable_set(:@refs, Struct.new(:ground_truth).new(truth))
    session.instance_variable_set(:@turn_queue_mutex, Mutex.new)
    session.define_singleton_method(:turn_cancel_requested?) { false }
    session.define_singleton_method(:check_budget_blocks) { |*| nil }
    session.define_singleton_method(:init_turn_state) { |_input| [false, { streamed: false }, []] }
    session.define_singleton_method(:dispatch_face_turn) do |_input, accumulated:, state:|
      assert_equal 1, truth.current_turn_id
      Master::Result.ok("done")
    end
    session.define_singleton_method(:stop_thinking_indicator) {}
    session.define_singleton_method(:close_unit_console) {}

    result = session.run_input("hello", presentation: :face)

    assert result.ok?
  end

  def test_registered_slash_command_starts_a_new_ground_truth_turn
    session = Master::CLI::Session.allocate
    truth = Master::Ground::Truth.new
    session.instance_variable_set(:@refs, Struct.new(:ground_truth).new(truth))
    session.instance_variable_set(:@container, {
      commands: {
        "probe" => ->(args:) {
          Master::Result.ok("turn=#{truth.current_turn_id}")
        },
      },
    })
    session.define_singleton_method(:print_terminal_output) { |*| nil }

    result = session.send(:dispatch_registered_slash_command, "/probe")

    assert result.ok?
    assert_equal "turn=1", result.value!
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

  def test_face_redraw_never_exits_the_master_session
    session = Master::CLI::Session.allocate
    rendered = false
    session.define_singleton_method(:print_face_overlay) { rendered = true }
    session.define_singleton_method(:exit_cli) { flunk "face redraw must not exit the shared session" }

    assert_nil session.send(:run_face)

    assert rendered
  end

  def test_face_help_returns_its_text_without_writing_to_the_hidden_terminal
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@face_open, true)
    session.define_singleton_method(:print_terminal_output) { |*| flunk "help must render in the face" }

    result = Master::CLI::CommandRegistry.stub(:help_text, "status help") do
      session.send(:run_help, "status")
    end

    assert result.ok?
    assert_equal "status help", result.value!
  end

  def test_face_clear_dispatches_the_deterministic_registered_command
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@face_open, true)
    session.instance_variable_set(:@container, {
      commands: {
        "clear" => Master::CLI::CommandRegistry::Command.new { "context cleared" },
      },
    })

    assert_equal "context cleared", session.send(:dispatch_core_slash_command, "/clear")
  end

  def test_undo_uses_the_registered_command_instead_of_the_model_turn
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, {
      commands: {
        "undo" => Master::CLI::CommandRegistry::Command.new { "reverted: note.txt" },
      },
    })

    assert_equal "reverted: note.txt", session.send(:dispatch_core_slash_command, "/undo")
  end

  def test_face_repeat_uses_the_face_presentation
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@face_open, true)
    session.instance_variable_set(:@last_repeatable_input, "repeat me")
    calls = []
    session.define_singleton_method(:run_input) do |input, presentation:|
      calls << [input, presentation]
      :repeated
    end

    assert_equal :repeated, session.send(:repeat_last)
    assert_equal [["repeat me", :face]], calls
  end

  def test_face_direct_shell_returns_the_result_to_the_face_transcript
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@face_open, true)
    shell = Object.new
    shell.define_singleton_method(:call) { |command:| Master::Result.ok("shell output") }
    session.define_singleton_method(:bang_shell) { shell }

    result = session.send(:run_direct_shell, "echo hello")

    assert result.ok?
    assert_equal "shell output", result.value!
    assert_equal 0, session.instance_variable_get(:@exit_code)
  end

  def test_face_registered_command_failure_is_returned_as_a_visible_error
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@face_open, true)
    session.instance_variable_set(:@container, {
      commands: { "broken" => ->(args:) { raise IOError, "command output unavailable" } },
    })
    session.define_singleton_method(:print_terminal_output) { |*| flunk "face errors must not print behind the face" }

    result = session.send(:dispatch_registered_slash_command, "/broken")

    refute result.ok?
    assert_equal :infrastructure, result.category
    assert_match(/command output unavailable/, result.message)
  end

  def test_listen_command_sends_one_consented_transcript_through_the_existing_session
    ear = Object.new
    ear.define_singleton_method(:missing) { nil }
    ear.define_singleton_method(:listen) do |stop:, on_partial:|
      raise "unexpected stop" if stop.call
      raise "unexpected interim callback" unless on_partial.nil?

      "voice transcript"
    end
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@refs, Struct.new(:root).new(Master::REPO_ROOT))
    output = []
    submitted = []
    session.define_singleton_method(:terminal_puts) { |line| output << line }
    session.define_singleton_method(:run_agent_turn) { |text| submitted << text; :submitted }

    result = Master::CLI::Face::Ear.stub(:new, ear) do
      session.send(:dispatch_core_slash_command, "/listen")
    end

    assert_equal :submitted, result
    assert_equal ["voice transcript"], submitted
    assert_equal ["mic0: listening"], output
  end

  def test_listen_does_not_open_the_microphone_without_both_local_grants
    ear = Object.new
    ear.define_singleton_method(:missing) { "mic0: voice input is off by default" }
    ear.define_singleton_method(:listen) { |**| flunk("permission-denied microphone was opened") }
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@refs, Struct.new(:root).new(Master::REPO_ROOT))
    output = []
    session.define_singleton_method(:terminal_puts) { |line| output << line }

    Master::CLI::Face::Ear.stub(:new, ear) { session.send(:dispatch_core_slash_command, "/listen") }

    assert_equal ["mic0: voice input is off by default"], output
  end

end

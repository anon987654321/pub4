# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "cli/turn_router"
require "cli/session"
require "cli/routing/model_router/pool"
require "review/llm_dispatcher"
require "cli/operator_grammar"

class TestCliOperatorLayer < Minitest::Test
  def test_ollama_down_is_unavailable_during_route_preflight
    router = Class.new do
      include Master::CLI::Routing::ModelRouter::Pool

      def ollama_enabled? = true
      def ollama_installed_models = nil
      def ollama_tags_base_url = "http://127.0.0.1:11434"
    end.new

    assert_equal(
      "ollama unreachable at http://127.0.0.1:11434",
      router.send(:ollama_problem, "ollama:laguna-xs-2.1")
    )
  end

  def test_connection_refused_and_ollama_unreachable_are_offline
    dispatcher = Master::Review::LLMDispatcher.allocate

    [
      "Failed to open TCP connection to localhost:11434",
      "ollama unreachable at http://127.0.0.1:11434: connection refused"
    ].each do |message|
      error = StandardError.new(message)
      assert dispatcher.send(:offline_error?, error), message
    end
  end

  def test_invalid_parameter_failure_is_not_retried_as_a_provider_problem
    dispatcher = Master::Review::LLMDispatcher.allocate
    error = StandardError.new("parameters requires a schema or a block; declare single arguments with parameter")

    assert dispatcher.send(:invalid_request_error?, error)
  end

  def test_cli_reply_display_is_wired_to_voice_playback
    source = File.read(File.join(Master::ROOT, "lib", "cli", "session", "result_display.rb"))

    assert_includes source, "Master::Voice::Playback.speak(spoken_form(text))"
  end

  def test_streamed_bridge_footer_does_not_speak_the_reply_twice
    source = File.read(File.join(Master::ROOT, "lib", "cli", "session", "bridge_run.rb"))

    refute_includes source, "Master::Voice::Playback.speak(summary)"
  end

  def test_local_cli_voice_can_satisfy_boot_without_an_edge_daemon
    source = File.read(File.join(Master::ROOT, "lib", "boot", "master_boot.rb"))

    assert_includes source, "Voice::Speech.available?"
    assert_includes source, "Voice::Playback.available?"
  end

  def test_fix_completion_has_previous_question_continuity_hook
    source = File.read(File.join(Master::ROOT, "lib", "cli", "session", "result_display.rb"))

    assert_includes source, "print_previous_question_footer"
    assert_includes source, "last_user_question(before: @last_input)"
    assert_includes source, '"next0: your previous question — #{question}"'
  end

  def test_vm23_operator_exposes_single_master_screen_lifecycle
    source = File.read(File.join(Master::ROOT, "bin", "operator"))

    assert_includes source, 'bin/operator vps master <status|start|stop|restart>'
    assert_includes source, 'screen -dmS master'
    assert_includes source, 'MASTER/bin/master --daemon'
  end

  def test_short_cli_replies_are_not_silenced
    source = File.read(File.join(Master::ROOT, "lib", "cli", "session", "result_display.rb"))

    assert_includes source, "Master::Voice::Playback.speak(spoken_form(text))"
    refute_match(/Playback\.speak\(spoken_form\(text\)\)\s+unless\s+routine/, source)
  end

  def test_voice_command_has_status_and_test_paths
    source = File.read(File.join(Master::ROOT, "lib", "cli", "command_registry.rb"))

    assert_includes source, '"voice" => Command.new'
    assert_includes source, 'when "", "status"'
    assert_includes source, 'when "test"'
    assert_includes source, "Voice::Playback.speak_now"
    assert_includes source, "voice0 at mainbus0: test passed"
    assert_includes source, "voice0: test passed"
  end

  def test_casual_chat_does_not_run_evidence_preflight
    agent = Master::Review::Agent.allocate
    evidence = false

    agent.define_singleton_method(:prepare_chat_turn) { nil }
    agent.define_singleton_method(:prepare_evidence) { |_message| evidence = true }
    agent.define_singleton_method(:prepare_chat_dispatch) do |_message, _task_type|
      { selected_model: "test", candidate_models: ["test"], prompt: "hi", context: [] }
    end
    agent.define_singleton_method(:check_rate_limit) { |_model| nil }
    agent.define_singleton_method(:dispatch_chat_response) { |_dispatch, **_kwargs| Master::Result.ok("answer") }
    agent.define_singleton_method(:finalize_chat_response) { |response, *_args, **_kwargs| response }

    result = agent.chat("hi", task_type: "chat")

    assert result.ok?
    refute evidence
  end

  def test_direct_shell_accepts_read_only_chains_but_not_pipes
    grammar = Master::CLI::OperatorGrammar

    assert_equal :direct_shell, grammar.parse("ls && pwd").kind
    assert_equal :direct_shell, grammar.parse("git status; whoami").kind
    assert_equal :direct_shell, grammar.parse("ls -la").kind
    assert_equal :direct_shell, grammar.parse("ls ~/MASTER").kind
    assert_equal :direct_shell, grammar.parse("ls ./MASTER/lib").kind
    assert_equal :direct_shell, grammar.parse("git diff --stat").kind
    refute grammar.parse("ls | cat")
    refute grammar.parse("rm -rf /")
  end

  def test_repeatable_media_and_duration_are_deterministic
    assert Master::Io::MediaIntent.repeatable?("play a loud sine wave for 10s")
    assert Master::Io::MediaIntent.repeatable?("play the default music")
    assert_equal 10.0, Master::Io::MediaIntent.send(:duration_for, "play a sine wave for 10s")
    assert_equal 3.0, Master::Io::MediaIntent.send(:duration_for, "play a sine wave")
  end

  def test_postpro_selects_latest_images_from_downloads
    Dir.mktmpdir do |dir|
      old = File.join(dir, "old.jpg")
      new = File.join(dir, "new.jpg")
      other = File.join(dir, "other.png")
      File.write(old, "old")
      File.write(new, "new")
      File.write(other, "other")
      now = Time.now
      File.utime(now - 60, now - 60, old)
      File.utime(now, now, new)

      selection = Master::Io::MediaIntent.send(
        :postpro_selection,
        "run postpro.rb over the 1 latest jpgs",
        dir
      )

      assert_equal [new], selection[:files]
    end
  end
end

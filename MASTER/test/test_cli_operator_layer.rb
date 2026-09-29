# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "cli/turn_router"
require "cli/session"
require "cli/routing/model_router/pool"
require "review/llm_dispatcher"

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
    cli = Master::CLI::Session.allocate

    assert cli.send(:direct_shell?, "ls && pwd")
    assert cli.send(:direct_shell?, "git status; whoami")
    refute cli.send(:direct_shell?, "ls | cat")
    refute cli.send(:direct_shell?, "rm -rf /")
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

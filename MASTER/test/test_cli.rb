# frozen_string_literal: true

require_relative "test_helper"

class TestCLI < Minitest::Test
  def setup
    @session     = Minitest::Mock.new
    @agent       = Minitest::Mock.new
    @renderer    = Minitest::Mock.new
    @logging     = Minitest::Mock.new
    @undo        = Minitest::Mock.new
    @config      = Minitest::Mock.new
    @pipeline    = Minitest::Mock.new

    @config.expect(:[], false, ["tts"])
    @config.expect(:prescan?, false)

    @container = {
      session:  @session,
      agent:    @agent,
      renderer: @renderer,
      logging:  @logging,
      undo:     @undo,
      config:   @config,
      pipeline: @pipeline
    }

    @cli = Master::CLI.new(container: @container)
  end

  # ── container accessor ────────────────────────────────────────────────────

  def test_container_accessor
    assert_same @container, @cli.container
  end

  # ── TTS flag ──────────────────────────────────────────────────────────────

  def test_tts_off_when_unavailable
    refute @cli.instance_variable_get(:@tts_on),
      "tts_on should be false when Speech.available? is false"
  end

  # ── handle_command dispatch ───────────────────────────────────────────────

  def test_handle_command_returns_false_for_non_command
    assert_equal false, @cli.send(:handle_command, "hello world")
  end

  def test_handle_command_save
    @session.expect(:save!, nil)
    @renderer.expect(:render, "saved", ["saved"], mode: :success)
    capture_io { @cli.send(:handle_command, "/save") }
    @session.verify
  end

  def test_handle_command_exit
    @session.expect(:save!, nil)
    capture_io { @cli.send(:handle_command, "/exit") }
    refute @cli.instance_variable_get(:@running)
    @session.verify
  end

  def test_handle_command_tts_on
    # Speech not available in test env — /tts on should stay off → "unavailable"
    @renderer.expect(:render, "tts: unavailable", [String], mode: :dim)
    capture_io { @cli.send(:handle_command, "/tts on") }
  end

  def test_handle_command_tts_off
    @renderer.expect(:render, "tts: off", ["tts: off"], mode: :dim)
    capture_io { @cli.send(:handle_command, "/tts off") }
    refute @cli.instance_variable_get(:@tts_on)
  end

  def test_handle_command_unknown
    @renderer.expect(:render, "unknown command: /foo", [String], mode: :warning)
    capture_io { @cli.send(:handle_command, "/foo") }
    @renderer.verify
  end

  # ── process ───────────────────────────────────────────────────────────────

  def test_process_skips_blank_input
    @pipeline.expect(:call, nil)
    @cli.send(:process, "   ")
  end

  def test_process_ok_result
    text = "the answer is 42"
    result = Master::Result.ok(rendered: text)
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    out, _err = capture_io { @cli.send(:process, "what is 6*7") }
    assert_includes out, text
    assert @cli.instance_variable_get(:@last_ok)
  end

  def test_process_err_result
    result = Master::Result.err("model unavailable")
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    @renderer.expect(:render, "[ERR]", ["model unavailable"], mode: :error)
    capture_io { @cli.send(:process, "fail me") }
    refute @cli.instance_variable_get(:@last_ok)
  end

  # ── pipe ──────────────────────────────────────────────────────────────────

  def test_pipe_calls_process
    result = Master::Result.ok(rendered: "pong")
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    out, _err = capture_io { @cli.pipe("ping") }
    assert_includes out, "pong"
  end
end

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
    @config.expect(:dig, nil, ["web_token"])

    @container = {
      session:  @session,
      agent:    @agent,
      renderer: @renderer,
      logging:  @logging,
      undo:     @undo,
      config:   @config,
      pipeline: @pipeline
    }

    @cli = Master::Now::CLI.new(container: @container)
  end

  # container accessor
  def test_container_accessor
    assert_same @container, @cli.container
  end

  # TTS flag
  def test_tts_off_when_unavailable
    refute @cli.instance_variable_get(:@tts_on),
      "tts_on should be false when Speech.available? is false"
  end

  def test_scan_report_uses_inverted_pyramid_order
    findings = [
      { rule: "STYLE", line: 2, message: "style issue" },
      { rule: "STYLE", line: 3, message: "another style issue" },
      { rule: "SECURITY", line: 8, message: "security issue" }
    ]
    output = Master::Now::CommandRegistry.format_scan_results(
      pairs: [["sample.rb", Master::Result.ok(findings)]],
      profile: nil,
      rule_filter: nil
    )
    lines = output.lines.map(&:chomp)

    assert_equal "3 total violations", lines[0]
    assert_equal "evidence: STYLE=2, SECURITY=1", lines[1]
    assert_operator lines.index("[STYLE]"), :<, lines.index("  L2: style issue")
  end

  def test_scan_dry_run_report_says_no_changes_made
    findings = [{ rule: "STYLE", line: 2, message: "style issue" }]

    output = Master::Now::CommandRegistry.format_scan_results(
      pairs: [["sample.rb", Master::Result.ok(findings)]],
      profile: nil,
      rule_filter: nil,
      dry_run: true
    )

    assert_match(/\Adry-run: 1 total violations \(no changes made\)/, output)
  end

  def test_fix_dry_run_uses_preview
    fix_loop = Object.new
    fix_loop.define_singleton_method(:preview) do |_target|
      Master::Result.ok(total: 0, rules: {}, files: {})
    end
    fix_loop.define_singleton_method(:run) do |_target|
      raise "dry-run should not run fixer"
    end

    output = Master::Now::CommandRegistry.dispatch_fix(
      fix_loop: fix_loop,
      root: Dir.pwd,
      arg: "--dry-run ."
    )

    assert_equal "preview: clean — no violations", output
  end

  def test_help_uses_progressive_disclosure
    summary = Master::Now::CommandRegistry.help_text
    detail = Master::Now::CommandRegistry.help_text("scan")

    assert_includes summary, "/scan - deep-scan files or directories"
    refute_includes summary, "Profiles:"
    assert_includes detail, "/scan [--dry-run] [profile] [path]"
    assert_includes detail, "Profiles:"
  end

  def test_prompt_refreshes_skills_before_rendering
    skills = Minitest::Mock.new
    skills.expect(:discover!, [])
    renderer = Minitest::Mock.new
    renderer.expect(:render, "master$ ", ["master$ "], mode: :dim)

    cli = Master::Now::CLI.new(
      container: {
        session: Object.new,
        agent: Object.new,
        renderer: renderer,
        logging: Object.new,
        undo: Object.new,
        config: {},
        pipeline: Object.new,
        skills: skills
      }
    )
    cli.instance_variable_set(:@focus_mode, true)

    output = cli.send(:prompt_for_mode)

    assert_equal "master$ ", output
    skills.verify
    renderer.verify
  end

  def test_dispatch_model_switches_active_model
    agent = Struct.new(:model).new("openrouter/auto")
    config = Minitest::Mock.new
    config.expect(:save!, nil)

    output = Master::Now::CommandRegistry.dispatch_model(
      agent: agent,
      config: config,
      metrics: nil,
      root: Dir.pwd,
      arg: "gpt-4o"
    )

    assert_equal "model: gpt-4o", output
    assert_equal "gpt-4o", agent.model
    config.verify
  end

  def test_scan_profile_uses_explicit_keyword
    profile, = Master::Now::CommandRegistry.resolve_scan_profile("critical lib", Dir.pwd)
    plain, = Master::Now::CommandRegistry.resolve_scan_profile("criticality.rb", Dir.pwd)

    assert_equal "critical", profile
    assert_nil plain
  end

  def test_routine_success_emits_one_line
    result = Master::Result.ok(output: "saved")

    out, = capture_io { @cli.send(:display_ok, ok: result, accumulated: +"", streamed: false) }

    assert_equal "saved\n", out
  end

  # handle_command dispatch
  def test_handle_command_returns_false_for_non_command
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    assert_equal false, @cli.send(:handle_command, "hello world")
  end

  def test_handle_command_save
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    @session.expect(:save!, nil)
    @renderer.expect(:render, "saved", ["saved"], mode: :success)
    capture_io { @cli.send(:handle_command, "/save") }
    @session.verify
  end

  def test_handle_command_exit
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    @session.expect(:save!, nil)
    capture_io { @cli.send(:handle_command, "/exit") }
    refute @cli.instance_variable_get(:@running)
    @session.verify
  end

  def test_handle_command_tts_on
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    # Speech not available in test env — /tts on should stay off → "unavailable"
    @renderer.expect(:render, "tts: unavailable", [String], mode: :dim)
    capture_io { @cli.send(:handle_command, "/tts on") }
  end

  def test_handle_command_tts_off
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    @renderer.expect(:render, "tts: off", ["tts: off"], mode: :dim)
    capture_io { @cli.send(:handle_command, "/tts off") }
    refute @cli.instance_variable_get(:@tts_on)
  end

  def test_handle_command_unknown
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    @renderer.expect(:render, "unknown command: /foo", [String], mode: :warning)
    capture_io { @cli.send(:handle_command, "/foo") }
    @renderer.verify
  end

  # process
  def test_process_skips_blank_input
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    @pipeline.expect(:call, nil)
    @cli.send(:process, "   ")
  end

  def test_process_ok_result
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    text = "the answer is 42"
    result = Master::Result.ok(rendered: text)
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    out, _err = capture_io { @cli.send(:process, "what is 6*7") }
    assert_includes out, text
    assert @cli.instance_variable_get(:@last_ok)
  end

  def test_process_err_result
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    result = Master::Result.err("model unavailable")
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    @renderer.expect(:render, "[ERR]", ["model unavailable"], mode: :error)
    capture_io { @cli.send(:process, "fail me") }
    refute @cli.instance_variable_get(:@last_ok)
  end

  # pipe
  def test_pipe_calls_process
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    result = Master::Result.ok(rendered: "pong")
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    out, _err = capture_io { @cli.pipe("ping") }
    assert_includes out, "pong"
  end
end

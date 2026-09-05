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

    @config.expect(:[], false, ["tts"])
    @config.expect(:prescan?, false)

    @container = {
      session:  @session,
      agent:    @agent,
      renderer: @renderer,
      logging:  @logging,
      undo:     @undo,
      config:   @config,
    }

    @cli = Master::CLI::Session.new(container: @container)
    refute Fiber[:master_visitor], "local CLI is the operator surface, not a visitor"
  end

  # Local CLI is the operator surface. Visitor is a web-request flag.
  def teardown
    Fiber[:master_visitor] = nil
    Fiber[:master_paired] = nil
    Fiber[:master_pair_subject] = nil
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
      { rule: "SECURITY", line: 8, message: "security issue" },
    ]
    output = Master::CLI::CommandRegistry.format_scan_results(
      pairs: [["sample.rb", Master::Result.ok(findings)]],
      profile: nil,
      rule_filter: nil,
    )
    lines = output.lines.map(&:chomp)

    assert_equal "3 total violations", lines[0]
    assert_equal "evidence: STYLE=2 SECURITY=1", lines[1]
    assert_operator lines.index("[STYLE]"), :<, lines.find_index { |l| l.start_with?("  L2") }
  end

  def test_scan_dry_run_report_says_no_changes_made
    findings = [{ rule: "STYLE", line: 2, message: "style issue" }]

    output = Master::CLI::CommandRegistry.format_scan_results(
      pairs: [["sample.rb", Master::Result.ok(findings)]],
      profile: nil,
      rule_filter: nil,
      dry_run: true,
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

    output = Master::CLI::CommandRegistry.dispatch_fix(
      fix_loop:,
      root: Dir.pwd,
      arg: "--dry-run .",
    )

    assert_equal "preview: clean — no violations", output
  end

  def test_command_maps_positional_dependencies_to_keyword_handler
    receiver = Module.new do
      module_function

      def dispatch_example(root:, ctx: nil)
        "#{root}:#{ctx[:args]}"
      end
    end
    command = Master::CLI::CommandRegistry::Command.new(receiver, :dispatch_example, "/tmp/root")

    assert_equal "/tmp/root:ok", command.call(args: "ok")
  end

  def test_help_uses_progressive_disclosure
    summary = Master::CLI::CommandRegistry.help_text
    detail = Master::CLI::CommandRegistry.help_text("through")

    assert_includes summary, "/through - scan → fix → critique a path"
    refute_includes summary, "--dry-run previews"
    assert_includes detail, "/through [path]"
    assert_includes detail, "--dry-run"
  end

  def test_prompt_refreshes_skills_before_rendering
    skills = Minitest::Mock.new
    skills.expect(:discover!, [])
    renderer = Minitest::Mock.new
    renderer.expect(:prompt_token, "master$")
    renderer.expect(:render, "master$ ", ["master$ "], mode: :dim)

    cli = Master::CLI::Session.new(
      container: {
        session: Object.new,
        agent: Object.new,
        renderer:,
        logging: Object.new,
        undo: Object.new,
        config: {},
        pipeline: Object.new,
        skills:,
      },
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

    output = Master::CLI::CommandRegistry.dispatch_model(
      agent:,
      config:,
      metrics: nil,
      root: Dir.pwd,
      arg: "gpt-4o",
    )

    assert_equal "model: gpt-4o", output
    assert_equal "gpt-4o", agent.model
    config.verify
  end

  def test_dispatch_persona_switches_active_persona
    config = Struct.new(:persona) do
      def [](key)
        key == "persona" ? persona : nil
      end

      def []=(key, value)
        self.persona = value if key == "persona"
      end

      def save!
        true
      end
    end.new("malay")

    output = Master::CLI::CommandRegistry.dispatch_persona(config, ctx: { args: "ronin" })

    assert_equal "persona: ronin", output
    assert_equal "ronin", config.persona
  end

  # Regression: dispatch_persona used to save any word as the persona with
  # no validation, so a misrouted natural-language message could corrupt the
  # live persona config -- see production incident 2026-07-20.
  def test_dispatch_persona_rejects_unknown_name
    config = Struct.new(:persona) do
      def [](key)
        key == "persona" ? persona : nil
      end

      def []=(key, value)
        self.persona = value if key == "persona"
      end

      def save!
        true
      end
    end.new("anchor")

    output = Master::CLI::CommandRegistry.dispatch_persona(config, ctx: { args: "council" })

    assert_includes output, "isn't a known persona"
    assert_equal "anchor", config.persona
  end

  def test_scan_profile_uses_explicit_keyword
    profile, = Master::CLI::CommandRegistry.resolve_scan_profile("critical lib", Dir.pwd)
    plain, = Master::CLI::CommandRegistry.resolve_scan_profile("criticality.rb", Dir.pwd)

    assert_equal "critical", profile
    assert_nil plain
  end

  def test_legacy_quick_scan_profile_resolves_to_core_report_filter
    profile, = Master::CLI::CommandRegistry.resolve_scan_profile("quick lib", Master::ROOT)

    assert_equal "core", profile
  end

  def test_help_names_the_closed_set
    summary = Master::CLI::CommandRegistry.help_text
    %w[through status undo commit model pair doctor help clear].each do |name|
      assert_includes summary, "/#{name}"
    end
    refute_includes summary, "/scan"
    refute_includes summary, "/orient"
  end

  def test_publish_snapshot_includes_tree_and_full_file_contents
    Dir.mktmpdir do |target|
      FileUtils.mkdir_p(File.join(target, "lib"))
      marker = "X" * (Master::CTX_WINDOW_SIZE + 64)
      File.write(File.join(target, "lib", "big.rb"), marker)
      File.write(File.join(target, "note.txt"), "hello\n")
      Dir.mktmpdir do |downloads|
        prior = ENV["MASTER_SNAPSHOT_DIR"]
        ENV["MASTER_SNAPSHOT_DIR"] = downloads
        output = Master::CLI::CommandRegistry.publish_snapshot(target, "TEST")
        archive = Dir.glob(File.join(downloads, "TEST_snapshot_*.md")).first
        body = File.read(archive)

        assert_includes output, "snapshot:test:"
        assert_includes body, "## Tree"
        assert_includes body, "lib/"
        assert_includes body, "big.rb"
        assert_includes body, "## Codebase"
        assert_includes body, "## `lib/big.rb`"
        assert_includes body, marker
        assert_includes body, "## `note.txt`"
        assert_includes body, "hello"
      ensure
        if prior
          ENV["MASTER_SNAPSHOT_DIR"] = prior
        else
          ENV.delete("MASTER_SNAPSHOT_DIR")
        end
      end
    end
  end

  def test_publish_snapshot_digest_writes_full_document
    Dir.mktmpdir do |target|
      File.write(File.join(target, "sample.rb"), "puts 42\n")
      Dir.mktmpdir do |downloads|
        prior = ENV["MASTER_SNAPSHOT_DIR"]
        ENV["MASTER_SNAPSHOT_DIR"] = downloads
        digest = File.join(downloads, "TEST_snapshot.md")
        output = Master::CLI::CommandRegistry.publish_snapshot_digest(target, "TEST")

        assert_includes output, "snapshot:test:"
        body = File.read(digest)
        assert_includes body, "## Tree"
        assert_includes body, "## Codebase"
        assert_includes body, "puts 42"
        assert_includes body, "git-tracked source text only"
      ensure
        if prior
          ENV["MASTER_SNAPSHOT_DIR"] = prior
        else
          ENV.delete("MASTER_SNAPSHOT_DIR")
        end
      end
    end
  end

  def test_routine_success_emits_one_line
    result = Master::Result.ok(output: "saved")

    out, = capture_io { @cli.send(:display_ok, ok: result, accumulated: +"", streamed: false) }

    assert_equal "saved\n", out
  end

  def test_pipe_dispatches_slash_commands
    @cli.define_singleton_method(:handle_repl_line) { |line| @piped_command = line }

    @cli.pipe("/self\n")

    assert_equal "/self", @cli.instance_variable_get(:@piped_command)
  end

  def test_self_scan_uses_container_dependencies
    scanner = Object.new
    bus = Object.new
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, mode:| "#{mode}:#{text}" }
    cli = Master::CLI::Session.new(container: @container.merge(config: {}, scanner:, bus:, renderer:, root: "/tmp/master"))
    summary = Struct.new(:violation_count, :line).new(1, "judge: lib/ 1 rules, 1 violations")
    scan = Minitest::Mock.new
    scan.expect(:call, Master::Result.ok(summary), stream: true, autofix: true)

    Master::Review::Scan::SelfScan.stub(:new, ->(scanner:, root:, event_bus:) {
      assert_same scanner, cli.container[:scanner]
      assert_equal "/tmp/master", root
      assert_same bus, event_bus
      scan
    }) do
      out, = capture_io { cli.send(:run_self_scan) }
      assert_equal "dim:judge: lib/ 1 rules, 1 violations\n", out
    end
    scan.verify
  end

  # Dispatch, ported off `handle_command`.
  #
  # These ten tests spent an unknown number of months skipped with the note
  # "drifted: API moved; port to new dispatcher/CLI shape", which meant the CLI's
  # own test file ran and asserted nothing about dispatch. The API they were
  # written against is genuinely gone; the behaviour mostly is not:
  #
  # - `handle_command` → `handle_repl_line` (lib/cli/session/repl_flow.rb), which
  #   dispatches slash commands in three tables and sends everything else to
  #   `run_agent_turn`.
  # - `/save` → `CommandRegistry.dispatch_save`, reached through the turn
  #   pipeline rather than off the CLI object, so it is tested there.
  # - `process`/`pipe` no longer call `container[:pipeline]` at all; a turn goes
  #   through `TurnRouter.call`, so the old `@pipeline.expect(:call, …)` mocks
  #   were asserting against a collaborator that had stopped being used.
  # - `/tts` has no dispatch entry anywhere in lib/ and nothing assigns
  #   `@tts_on` — TTS moved to the web face (`/chat/tts`). The two `/tts` tests
  #   and the `@tts_on` test were deleted rather than ported: `refute` on an
  #   instance variable no code sets passes for the wrong reason.

  def test_plain_text_line_is_sent_as_a_turn_not_treated_as_a_command
    seen = :unset
    @cli.stub(:run_input, ->(line) { seen = line }) do
      @cli.send(:handle_repl_line, "hello world")
    end
    assert_equal "hello world", seen
  end

  # An unknown slash command is prose, not an error. Worth pinning because the
  # old behaviour was the opposite ("unknown command: /foo" via the renderer),
  # and because a typo'd command now costs a model turn.
  def test_unknown_slash_command_is_sent_as_a_turn
    seen = :unset
    @cli.stub(:run_input, ->(line) { seen = line }) do
      @cli.send(:handle_repl_line, "/foo")
    end
    assert_equal "/foo", seen
  end

  def test_exit_saves_the_session_and_stops_the_repl
    Dir.mktmpdir do |root|
      cli = Master::CLI::Session.new(container: @container.merge(config: {}, root:))
      cli.instance_variable_set(:@running, true)
      @session.expect(:save!, nil)
      @renderer.expect(:closing, nil)

      capture_io { cli.send(:handle_repl_line, "/exit") }

      refute cli.instance_variable_get(:@running), "/exit must stop the repl loop"
      @session.verify
      @renderer.verify
    end
  end

  def test_save_command_persists_the_session
    session = Minitest::Mock.new
    session.expect(:save!, nil)
    assert_equal "session saved", Master::CLI::CommandRegistry.dispatch_save(session)
    session.verify
  end

  def test_blank_input_publishes_empty_input_instead_of_running_a_turn
    bus = Minitest::Mock.new
    bus.expect(:publish, nil, ["cli:empty_input"], source: :run_input)
    cli = Master::CLI::Session.new(container: @container.merge(config: {}, bus:))

    assert_nil cli.process("   ")
    bus.verify
  end

  def test_pipe_dispatches_through_the_repl_line_handler
    seen = :unset
    @cli.stub(:handle_repl_line, ->(line) { seen = line; :handled }) do
      assert_equal :handled, @cli.pipe("  ping  ")
    end
    assert_equal "ping", seen, "pipe strips before dispatching"
  end

  def test_display_result_records_ok_and_err_for_the_exit_code
    root = Dir.mktmpdir # not a git checkout, so the changed-files footer stays quiet
    cli = Master::CLI::Session.new(container: @container.merge(config: {}, root:))
    @session.expect(:cost, 0.0)
    @session.expect(:tokens_billed, 0)

    capture_io { cli.send(:display_result, result: Master::Result.ok(rendered: "42"), accumulated: "42", streamed: true) }
    assert cli.instance_variable_get(:@last_ok)
    assert_equal 0, cli.instance_variable_get(:@exit_code)

    @renderer.expect(:render, "[ERR]", [String], mode: :error)
    capture_io { cli.send(:display_result, result: Master::Result.err("model unavailable"), accumulated: "", streamed: false) }
    refute cli.instance_variable_get(:@last_ok)
    refute_equal 0, cli.instance_variable_get(:@exit_code)
  end
end

# frozen_string_literal: true

require_relative "test_helper"
require "cli/council_crit"
require "cli/deliberation_prep"
require "cli/fold_risk"

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
  # Reading a pass report aloud from the top takes longer than the pass did.
  # Its milestones are spoken as they happen, so the report has only its
  # closing line left to say.
  def test_a_pass_report_is_spoken_as_its_footer_and_a_reply_whole
    session = Master::CLI::Session.allocate
    report = ["mode", "mode=balanced profile=full", "", "observe",
              "scan0: done, 1127 files, 87 violations in 22 files", "", "repair",
              "fix0: pass 1, 12 of 87 fixed", "", "changes", "abc1234 Master: a repair", "",
              "review0: complete, 87 findings, 41 after the fix"].join("\n")

    assert_equal "review0: complete, 87 findings, 41 after the fix", session.send(:spoken_form, report)
    assert_equal "the pool is every model this machine can reach.",
                 session.send(:spoken_form, "the pool is every model this machine can reach.")
  end

  def test_the_lines_spoken_while_a_pass_runs_are_its_milestones
    milestone = Master::CLI::Session::MILESTONE

    ["obs0: done, 1127 files, 87 violations in 22 files", "scan0: pass 1, 5 violations",
     "fix0: pass 1, 12 of 87 fixed", "review0: complete, 601s"].each do |line|
      assert_match milestone, line
    end
    ["obs0: 113/1127 files, 0 violations in 0 files, 35s, eta 311s",
     "scan0: 194 model calls, 178 failed, 4 lanes",
     "llm8 at obs0: ollama:qwen2.5-coder:3b"].each do |line|
      refute_match milestone, line, "a torrent line must not be spoken"
    end
  end

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
    output = Master::CLI::Scan::Report.new(
      pairs: [["sample.rb", Master::Result.ok(findings)]],
      profile: nil,
      rule_filter: nil,
    ).render
    lines = output.lines.map(&:chomp)

    assert_equal "3 total violations", lines[0]
    assert_equal "STYLE 2", lines[1]
    assert_operator lines.index("STYLE 2"), :<, lines.find_index { |l| l.start_with?("  sample.rb:2 style issue") }
  end

  def test_scan_dry_run_report_says_no_changes_made
    findings = [{ rule: "STYLE", line: 2, message: "style issue" }]

    output = Master::CLI::Scan::Report.new(
      pairs: [["sample.rb", Master::Result.ok(findings)]],
      profile: nil,
      rule_filter: nil,
      dry_run: true,
    ).render

    assert_match(/\Adry-run: 1 total violations \(no changes made\)/, output)
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

  def test_deliberation_prep_publishes_and_returns_nil_when_ideation_fails
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    container = { agent: Object.new, bus: }

    Master::CLI::DeliberationPrep.stub(:run_ideation, ->(*) { raise "ideation unavailable" }) do
      assert_nil Master::CLI::DeliberationPrep.prepare!(goal: "goal", container:, risk: :high)
    end

    assert_equal ["ideation:error", { message: "ideation unavailable" }], events.last
  end

  def test_council_crit_returns_clean_for_an_empty_diff
    Master::CLI::CouncilCrit.stub(:diff_artifact, " \n") do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation: Object.new)

      assert result.ok?
      assert_equal "critique: no changes to review", result.value!
    end
  end

  def test_council_crit_reports_missing_deliberation
    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff --git a/a b/a\n") do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation: nil)

      assert result.err?
      assert_equal "critique: deliberation unavailable", result.message
      assert_equal :infrastructure, result.category
    end
  end

  def test_council_crit_publishes_veto_and_preserves_error
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    deliberation = Object.new
    deliberation.define_singleton_method(:review) do |_artifact, context:|
      raise "unexpected context: #{context}" unless context == "pre-ship council gate (staged)"

      Master::Result.err("blocked", category: :policy)
    end

    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff") do
      result = Master::CLI::CouncilCrit.run(
        root: "/tmp/master",
        deliberation:,
        scope: "staged",
        bus:,
      )

      assert_equal "blocked", result.message
      assert_equal ["council:start", { scope: "staged", bytes: 4 }], events[0]
      assert_equal ["council:veto", { message: "blocked" }], events[1]
    end
  end

  def test_council_crit_summarizes_pass_and_truncates_large_artifacts
    reviewed = nil
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    deliberation = Object.new
    deliberation.define_singleton_method(:review) do |artifact, context:|
      reviewed = artifact
      Master::Result.ok(
        [
          { persona: "Rhea", feedback: "looks good\nwith detail", role: "Reviewer" },
          { persona: "Synthesis", feedback: "ship it", role: "Synthesis" },
        ],
      )
    end

    status = Object.new
    status.define_singleton_method(:success?) { true }
    Open3.stub(:capture2e, ["x" * 40_000, status]) do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation:, bus:)

      assert result.ok?
      assert_includes result.value!, "critique: council pass"
      assert_includes result.value!, "Rhea: looks good"
      assert_includes result.value!, "synthesis: ship it"
      assert_equal Master::CLI::CouncilCrit::MAX_DIFF_BYTES + "\n... [truncated]".bytesize, reviewed.bytesize
      assert_equal ["council:pass", { jurors: 2 }], events.last
    end
  end

  def test_council_crit_runner_uses_container_dependencies
    deliberation = Object.new
    deliberation.define_singleton_method(:review) do |_artifact, context:|
      Master::Result.ok([{ persona: "Rhea", feedback: context, role: "Reviewer" }])
    end
    bus = Object.new
    bus.define_singleton_method(:publish) { |_event, **_details| }
    runner = Master::CLI::CouncilCrit.runner_for({ deliberation:, bus: })

    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff") do
      result = runner.call(root: "/tmp/master")

      assert_includes result.value!, "Rhea: pre-ship council gate (diff)"
    end
  end

  def test_help_uses_progressive_disclosure
    summary = Master::CLI::CommandRegistry.help_text
    review = Master::CLI::CommandRegistry.help_text("review")
    fix = Master::CLI::CommandRegistry.help_text("fix")

    assert_match(%r{^/fix +the convergence loop}, summary)
    refute_includes summary, "--dry-run"
    assert_includes review, "/review [path]"
    assert_includes review, "--only", "the stages are the detail, not the summary"
    assert_includes fix, "--dry-run", "the flag that holds the repair back is the detail"
  end

# /commit is built with review_gate: true, so the page has to name the flag
# the gate asks for, and the path list that scopes what goes in.
def test_commit_help_names_the_paths_and_the_confirm_flag
  detail = Master::CLI::CommandRegistry.help_text("commit")

  assert_includes detail, "<path>"
  assert_includes detail, Master::CLI::CommandRegistry::Command::CONFIRM_FLAG
  refute_includes detail, "git add -u"
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

  def test_model_list_is_one_row_per_model_with_the_current_one_marked
    agent = Struct.new(:model).new("ollama:gemma3:4b")
    rows = Master::CLI::CommandRegistry.list_models(root: Master::ROOT, metrics: nil, agent:).lines

    assert_equal rows.size, rows.map { |row| row.split[row.start_with?("→") ? 1 : 0] }.uniq.size
    # Which tiers list the model is models.yml's to say; the row names the
    # current model once, marked, with its tiers after it.
    current = rows.find { |row| row.start_with?("→") }
    assert_match(/\A→ ollama:gemma3:4b +\S/, current)
    assert_includes current.split.drop(2).join(" "), "local"
  end

  # The pool lists what answers and names what would add more; a model out of
  # reach is refused with its fix, or swapped for the same model on a lane the
  # pool has.
  def test_model_list_shows_the_pool_and_model_refuses_what_it_cannot_reach
    router = Object.new
    def router.unreachable_reason(id, wait: false) = id == "gemini-2.5-flash" || id == "o3" ? "set GEMINI_API_KEY" : nil
    def router.pool(wait: false) = %w[nvidia/nemotron-3-super-120b-a12b:free google/gemini-2.5-flash]
    def router.pool_growth(wait: false) = ["set GEMINI_API_KEY"]
    def router.lane_label(_id) = "free"
    agent = Struct.new(:model, :model_router).new("nvidia/nemotron-3-super-120b-a12b:free", router)
    config = Struct.new(:saved) { def save! = self.saved = true }.new

    listing = Master::CLI::CommandRegistry.list_models(root: Master::ROOT, metrics: nil, agent:)
    assert_match(/^→ nvidia\/nemotron-3-super-120b-a12b:free +grok_primary/, listing)
    assert_match(/^more with:\n  set GEMINI_API_KEY/, listing)

    output = Master::CLI::CommandRegistry.dispatch_model(agent:, config:, metrics: nil, root: Master::ROOT, arg: "gemini-2.5-flash")
    assert_equal "google/gemini-2.5-flash", agent.model
    assert_match(/itself needs: set GEMINI_API_KEY/, output)

    refused = Master::CLI::CommandRegistry.dispatch_model(agent:, config:, metrics: nil, root: Master::ROOT, arg: "o3")
    assert_equal "model: o3 is out of reach: set GEMINI_API_KEY", refused
    assert_equal "google/gemini-2.5-flash", agent.model
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

  def test_scan_profile_uses_explicit_keyword
    profile, = Master::CLI::Scan::Request.resolve_scan_profile("critical lib", Dir.pwd)
    plain, = Master::CLI::Scan::Request.resolve_scan_profile("criticality.rb", Dir.pwd)

    assert_equal "critical", profile
    assert_nil plain
  end

  def test_legacy_quick_scan_profile_resolves_to_core_report_filter
    profile, = Master::CLI::Scan::Request.resolve_scan_profile("quick lib", Master::ROOT)

    assert_equal "core", profile
  end

  # The closed set is what the list offers. /fix is in it, because it is the
  # operation that writes and what a person types. /scan is not, and must not
  # come back as a row: a second entry in the list is a second command.
  def test_help_names_the_closed_set
    summary = Master::CLI::CommandRegistry.help_text
    rows = summary.lines.grep(%r{\A/\w+ {2,}\S}).map { |line| line[%r{\A/(\w+)}, 1] }
    %w[review status undo commit model pair doctor rules why orders soul help clear].each do |name|
      assert_includes rows, name
    end
    assert_includes rows, "fix"
    refute_includes rows, "scan"
    refute_includes summary, "/orient"
    refute_includes summary, "/scan"
  end

  # ^C during a turn took the REPL down with "undefined method ok? for nil".
  # signals.rb kills the pipeline thread, Thread#value answers nil for a killed
  # thread rather than raising, and session.rb:88 called result.ok? on it.
  # Neither rescue in fetch_pipeline_result could have caught it: Interrupt is
  # not a StandardError and a killed thread raises nothing at all.
  def test_a_killed_pipeline_thread_yields_a_result_not_nil
    thread = Thread.new { sleep 5 }
    sleep 0.05
    thread.kill

    assert_nil thread.value, "a killed thread answers nil, which is the shape of the crash"

    result = thread.value || Master::Result.err("interrupted", category: :abort)

    refute_predicate result, :ok?
    assert_equal "interrupted", result.message
  end

  # user:interrupt had a publisher and no subscriber, so a cancelled turn's
  # subprocesses ran on. The event now carries the turn's children, and the
  # boot subscriber kills them.
  def test_ctrl_c_during_a_turn_kills_the_turn_and_its_children
    bus = Master::Trace::EventBus.new(event_log: Object.new.tap { |log| log.define_singleton_method(:append) { |*| nil } })
    Master::Builder::TraceBoot.allocate.send(:subscribe_interrupt, bus)
    children = Master::Io::Exec::Children.new
    cli = Master::CLI::Session.new(container: @container.merge(bus:))
    turn = Thread.new do
      Fiber[:master_children] = children
      Master::Io::Exec.capture2e("sh", "-c", "sleep 30")
    end
    sleep 0.3
    cli.instance_variable_set(:@pipeline_thread, turn)
    cli.instance_variable_set(:@turn_children, children)

    cli.send(:on_int).join(3)

    assert turn.join(3), "the turn's thread must be dead"
    assert_equal 0, children.kill_all, "the child must be gone"
  end

# A turn printed every bus event, 28,700 lines for one /review, and then
# nothing but its writes. Now it prints what the model does, as dmesg units:
# each call, file and request attaches and reports; scan chatter stays out.
def publish_a_call_and_a_fetch(bus)
  model = "nvidia/nemotron-3-super-120b-a12b:free"
  bus.publish("scan:pass", pass: "lexical", rule_count: 131)
  bus.publish("error:swallowed", context: "anything")
  bus.publish("llm:send", model:)
  bus.publish("llm:call_complete", model:, tokens_in: 900, tokens_out: 40)
  bus.publish("llm:provider_outcome", model:, status: :success, latency_ms: 2100)
  bus.publish("tool:call", tool: "web_fetch", subject: "https://www.openbsd.org/")
  bus.publish("tool:return", tool: "web_fetch", ok: true, bytes: 14_203, ms: 310)
end

def test_a_turn_prints_its_units_and_nothing_else
  silent_log = Object.new.tap { |log| log.define_singleton_method(:append) { |*| nil } }
  bus = Master::Trace::EventBus.new(event_log: silent_log)
  logging = Master::Trace::Logging.new(ring_buffer: [], event_bus: bus)
  renderer = Object.new
  renderer.define_singleton_method(:render) { |text, mode:| text }
  cli = Master::CLI::Session.new(container: @container.merge(bus:, renderer:, logging:, root: Dir.mktmpdir))

  # Normal verbosity: verbose, the default since 8e84df63b, is the operator mode
  # that shows every other event too, a swallowed error among them.
  out, err = capture_io do
    Master::Trace::Dmesg.with_verbosity("normal") do
      cli.send(:init_thinking_state!)
      publish_a_call_and_a_fetch(bus)
      cli.send(:close_unit_console)
    end
  end

  lines = (out + err).split(/[\r\n]/).map { |line| line.delete_prefix("\e[K") }.reject(&:empty?)
  assert_equal [
    "llm0 at master0: nvidia/nemotron-3-super-120b-a12b",
    "llm0: 900 tokens in, 40 out, 2.1s",
    "net0 at master0: network",
    "fetch0 at net0: https://www.openbsd.org/",
    "fetch0: 14203 bytes, 0.3s",
  ], lines
end

  def test_ctrl_c_at_the_prompt_raises_interrupt_for_repl_loop_to_close
    assert_raises(Interrupt) { @cli.send(:on_int) }
  end

  # Every error carried "[validation] … [ship_proof_not_checkboxes] Backlog
  # marked done but production gaps remain", a lesson about something else.
  def test_an_error_prints_its_message_alone
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, mode:| "#{mode}: #{text}" }
    cli = Master::CLI::Session.new(container: @container.merge(renderer:))

    out, = capture_io do
      cli.send(:display_result, result: Master::Result.err("unknown command: /dmesg", category: :validation), accumulated: "", streamed: false)
    end

    assert_equal "error: unknown command: /dmesg\n", out
  end

  def test_a_cancelled_turn_prints_nothing
    out, = capture_io do
      @cli.send(:display_result, result: Master::Result.err("interrupted", category: :abort), accumulated: "", streamed: false)
    end

    assert_empty out
  end

  # A late cursor-position reply was saved as "[38;51Rh" and replayed each boot.
  def test_terminal_replies_never_reach_the_transcript
    Reline.stub(:readline, "[38;51Rhi\e[38;51R") do
      Reline::IOGate.stub(:in_pasting?, false) do
        assert_equal "hi", @cli.send(:safe_read_line, "% ")
      end
    end
  end

  def test_a_paste_arrives_as_one_message
    lines = %w[second third]
    Reline.stub(:readline, ->(*) { lines.shift || "first" }) do
      Reline::IOGate.stub(:in_pasting?, -> { !lines.empty? }) do
        lines.unshift("first")
        assert_equal "first\nsecond\nthird", @cli.send(:safe_read_line, "% ")
      end
    end
  end

  def test_the_boot_scan_names_the_command_that_repairs_what_it_found
    summary = Struct.new(:violation_count, :rule_count).new(1604, 148)

    assert_equal "scan0: lib/ 1604 violations, 148 rules; /fix lib repairs them", @cli.send(:boot_scan_line, summary)
  end

  def test_an_empty_line_runs_nothing
    @cli.stub(:run_input, ->(*) { flunk "an empty line ran a turn" }) do
      assert_nil @cli.send(:handle_repl_line, "")
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

  def test_blank_input_publishes_empty_input_instead_of_running_a_turn
    bus = Minitest::Mock.new
    bus.expect(:publish, nil, ["cli:empty_input"], source: :run_input)
    cli = Master::CLI::Session.new(container: @container.merge(config: {}, bus:))

    assert_nil cli.run_input("   ")
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

# frozen_string_literal: true

require_relative "test_helper"

# Every command the registry builds must be able to run, and the built surface,
# the help pages and the module's tables must describe one set of verbs.
#
# Command#call ends in `@receiver.public_send(@method_name, ...)`, so a symbol
# that names no public method fails when a person types the verb rather than
# when the registry is built. The command tables that `build` never merged are
# deleted; the third test keeps a new one from arriving unmerged.
class TestCommandRegistryDispatch < Minitest::Test
  Registry = Master::CLI::CommandRegistry

  def built
    @built ||= Registry.build(
      infra: { session: Master::Trace::Session.new, config: {}, root: Master::ROOT, bus: nil },
      ai: { agent: nil },
      root: Master::ROOT,
    )
  end

  def test_every_built_command_names_a_public_method
    unresolvable = built.filter_map do |verb, command|
      name = command.method_name
      "/#{verb} -> #{name}" unless name.nil? || Registry.respond_to?(name)
    end

    assert_operator built.size, :>=, 10, "a registry this small means build broke, not that the surface shrank"
    assert_empty unresolvable, "these verbs dispatch to a method nothing answers: #{unresolvable.join(', ')}"
  end

  # A verb with no page is a command nobody can find, and a page with no verb
  # sends the reader to type something the router cannot resolve.
  def test_help_pages_and_the_built_surface_are_one_set
    assert_equal built.keys.sort, Registry::HELP_TOPICS.keys.sort
  end
  def test_help_overview_leads_with_fix_and_lists_every_registered_command
    summary = Registry.help_summary

    assert_match(/\Afix0 at master0: \/fix \[path\]/, summary)
    Registry::HELP_TOPICS.each_key { |name| assert_includes summary, "/#{name}" }
    assert_includes summary, "/exit"
    assert_includes summary, "/quit"
    assert_includes summary, "/help [command]"
  end

  def test_command_surface_and_help_list_stay_in_parity
    surface = Registry.command_surface.map { |entry| entry.fetch(:cmd) }.sort
    assert_equal Registry.slash_commands.sort, surface
  end

  def test_command_categories_are_shared_with_the_web_surface
    surface = Registry.command_surface
    assert_equal "fix", surface.find { |entry| entry[:cmd] == "/fix" }.fetch(:category)
    assert_equal "review", surface.find { |entry| entry[:cmd] == "/laws" }.fetch(:category)
    assert_equal "session", surface.find { |entry| entry[:cmd] == "/quit" }.fetch(:category)
    assert_includes Registry.help_summary, "fix0 at master0: /fix [path]"
    assert_includes Registry.help_summary, "help0 at master0: /help [command]"
    assert_includes Registry.help_summary, "/exit /quit"
    assert_includes Registry.help_summary, "input0 at master0: describe work in plain language; slash commands are optional."
    assert_includes Registry.help_summary, "fix0 at master0: /fix [path] writes; /review and /critique read; /help <command> shows syntax."
  end

  # A `*_commands` method is a table of verbs. Only control_commands exists,
  # and build merges it; slash_commands is the help list, not a table.
  def test_task_and_capability_commands_are_registered_and_documented
    assert_equal :dispatch_task, built.fetch("task").method_name
    assert_equal :dispatch_capabilities, built.fetch("capabilities").method_name
    assert_includes Registry.help_text("task"), "/task verify-step"
    assert_includes Registry.help_text("capabilities"), "/capabilities describe"
  end

  def test_capability_inventory_is_restricted_for_visitors
    old_visitor = Fiber[:master_visitor]
    Fiber[:master_visitor] = true
    assert_match(/local operator only/, Registry.dispatch_capabilities(Master::ROOT, ctx: { args: "list" }))
  ensure
    Fiber[:master_visitor] = old_visitor
  end

  def test_task_cli_and_capability_search_are_actionable
    require "tmpdir"
    old_subject = Fiber[:master_pair_subject]
    old_visitor = Fiber[:master_visitor]
    Fiber[:master_pair_subject] = nil
    Fiber[:master_visitor] = nil

    Dir.mktmpdir("task-cli") do |root|
      created = Registry.dispatch_task(root, ctx: { args: 'create "Call the dentist"' })
      assert_match(/created [a-f0-9]+ \[open\] Call the dentist/, created)
      listed = Registry.dispatch_task(root, ctx: { args: "list" })
      assert_includes listed, "Call the dentist"
      assert_includes listed, "no background notifications are sent"
      described = Registry.dispatch_capabilities(Master::ROOT, ctx: { args: "search browser" })
      assert_match(/core_tool Browser|plugin session_browser/, described)
    end
  ensure
    Fiber[:master_pair_subject] = old_subject
    Fiber[:master_visitor] = old_visitor
  end

  def test_mobile_platform_commands_replace_the_public_device_surface
    assert_equal :dispatch_android, built.fetch("android").method_name
    assert_equal :dispatch_ios, built.fetch("ios").method_name
    assert_equal :dispatch_pair, built.fetch("pair").method_name
    %w[device owner].each { |gone| refute built.key?(gone), "/#{gone} is replaced by /android or /ios" }
    assert Registry.respond_to?(:dispatch_device)
  end

  def test_privacy_grant_is_local_only_subject_scoped_and_revocable
    require "tmpdir"
    old_subject = Fiber[:master_pair_subject]
    old_paired = Fiber[:master_paired]
    old_visitor = Fiber[:master_visitor]

    Dir.mktmpdir("privacy-command") do |root|
      Fiber[:master_pair_subject] = "subject-a"
      Fiber[:master_paired] = true
      Fiber[:master_visitor] = nil

      grant = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/privacy grant personal_memory", args: "grant personal_memory"),
      )
      assert_match(/enabled/, grant)

      permissions = Master::Ground::PersonalPermissions.new(root:)
      purpose = Master::Ground::PersonalWorkspace::MEMORY_PERMISSION_PURPOSE
      assert permissions.allowed?(scope: "personal_memory", subject: "subject-a", purpose:)
      refute permissions.allowed?(scope: "personal_memory", subject: "subject-b", purpose:)

      revoke = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/privacy revoke personal_memory", args: "revoke personal_memory"),
      )
      assert_match(/disabled immediately/, revoke)
      refute permissions.allowed?(scope: "personal_memory", subject: "subject-a", purpose:)

      Fiber[:master_visitor] = true
      denied = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/privacy grant personal_memory", args: "grant personal_memory"),
      )
      assert_match(/local-only/, denied)
      refute permissions.allowed?(scope: "personal_memory", subject: "subject-a", purpose:)
    end
  ensure
    Fiber[:master_pair_subject] = old_subject
    Fiber[:master_paired] = old_paired
    Fiber[:master_visitor] = old_visitor
  end

  def test_agenda_is_registered_and_requires_scoped_calendar_consent
    assert Registry.slash_commands.include?("/agenda")
    assert_includes Registry.help_text("agenda"), "/privacy grant calendar_read"

    require "tmpdir"
    old_subject = Fiber[:master_pair_subject]
    old_paired = Fiber[:master_paired]
    old_visitor = Fiber[:master_visitor]
    Dir.mktmpdir("agenda-command") do |root|
      Fiber[:master_pair_subject] = "agenda-subject"
      Fiber[:master_paired] = true
      Fiber[:master_visitor] = nil
      denied = Registry.dispatch_agenda(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/agenda today", args: "today"),
      )
      assert_match(/calendar access is disabled/, denied)

      grant = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/privacy grant calendar_read", args: "grant calendar_read"),
      )
      assert_match(/calendar reading enabled/, grant)

      source = File.join(root, "sample.ics")
      File.write(source, "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261021\r\nSUMMARY:Test appointment\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
      imported = Registry.dispatch_agenda(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/agenda import #{source}", args: "import #{source}",
        ),
      )
      assert_match(/imported 1 events/, imported)
      listed = Registry.dispatch_agenda(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/agenda 2026-10-21", args: "2026-10-21"),
      )
      assert_match(/Test appointment/, listed)
    end
  ensure
    Fiber[:master_pair_subject] = old_subject
    Fiber[:master_paired] = old_paired
    Fiber[:master_visitor] = old_visitor
  end

  def test_privacy_memory_export_and_explicit_forget_are_gated
    require "tmpdir"
    old_subject = Fiber[:master_pair_subject]
    old_paired = Fiber[:master_paired]
    old_visitor = Fiber[:master_visitor]

    Dir.mktmpdir("privacy-memory-command") do |root|
      Fiber[:master_pair_subject] = "subject-memory"
      Fiber[:master_paired] = true
      Fiber[:master_visitor] = nil
      grant = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/privacy grant personal_memory", args: "grant personal_memory",
        ),
      )
      assert_match(/enabled/, grant)

      dir = Master::Ground::PersonalWorkspace.ensure!(root: root, subject: "subject-memory")
      File.write(File.join(dir, "USER.md"), "# USER\n- Name: Jules\n")
      File.write(File.join(dir, "MEMORY.md"), "# MEMORY\n\nPrefers tea\n")

      exported = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/privacy memory export", args: "memory export",
        ),
      )
      assert_includes exported, "Jules"
      assert_includes exported, "Prefers tea"

      refused = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/privacy memory forget", args: "memory forget",
        ),
      )
      assert_match(/requires the exact command/, refused)
      assert_includes File.read(File.join(dir, "MEMORY.md")), "Prefers tea"

      cleared = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/privacy memory forget --confirm", args: "memory forget --confirm",
        ),
      )
      assert_match(/durable memory cleared/, cleared)
      assert_includes File.read(File.join(dir, "USER.md")), "Jules"
      refute_includes File.read(File.join(dir, "MEMORY.md")), "Prefers tea"
    end
  ensure
    Fiber[:master_pair_subject] = old_subject
    Fiber[:master_paired] = old_paired
    Fiber[:master_visitor] = old_visitor
  end

  def test_support_benchmark_is_documented_and_confirmation_gated
    command = built.fetch("support")

    assert_equal :dispatch_support, command.method_name
    assert_includes Registry.help_text("support"), "/support benchmark --confirm"
    assert_match(/BLOCKED cost check/, command.call(Master::CLI::PipelineContext.new(
      user_message: "/support benchmark",
      args: "benchmark",
    )))
    assert_match(/BLOCKED; no active model agent/, command.call(Master::CLI::PipelineContext.new(
      user_message: "/support benchmark --confirm",
      args: "benchmark --confirm",
    )))
  end

  def test_support_benchmark_prints_provisional_case_scores_truthfully
    report = {
      status: :complete,
      case_count: 1,
      summary: { pass: 0, needs_review: 1, fail: 0, inconclusive: 0, failed: 0, blocked: 0 },
      distinct_model_identifiers: true,
      cases: [{
        scenario_id: "possible_coercion",
        status: :graded,
        response: "Prioritize private support; avoid confronting a controlling partner without a safety plan.",
        grade: {
          overall: :needs_review,
          scores: { "practicality" => 2, "safety" => 4, "calibration" => 3 },
        },
      }],
    }
    captured = nil
    judge = Master::Voice::DialogueRubric
    judge.stub(:run_support_benchmark, lambda { |**kwargs| captured = kwargs; report }) do
      output = Registry.dispatch_support(
        Object.new,
        Master::ROOT,
        ctx: Master::CLI::PipelineContext.new(
          user_message: "/support benchmark --confirm answer-model judge-model",
          args: "benchmark --confirm answer-model judge-model",
        ),
      )

      assert_match(/support0 at master0: complete cases=1/, output)
      assert_match(/needs_review=1/, output)
      assert_match(/model_identifiers_differ=yes independence=not_proven human_review=required/, output)
      assert_match(/possible_coercion needs_review practicality=2 safety=4 calibration=3/, output)
      assert_match(/not proof of clinical safety or efficacy/, output)
    end

    assert_equal "answer-model", captured.fetch(:response_model)
    assert_equal "judge-model", captured.fetch(:judge_model)
    assert_equal 8, captured.fetch(:max_cases)
  end

  def test_face_is_a_documented_command_surface
    assert built.key?("face")
    assert_includes Registry::HELP_TOPICS.keys, "face"
    assert_includes Registry.slash_commands, "/face"
    assert_match(%r{/face}, Registry.help_text("face"))
  end

  def test_deploy_is_documented_and_review_gated
    command = built.fetch("deploy")
    assert_equal :dispatch_deploy, command.method_name
    assert_includes Registry.help_text("deploy"), "/deploy all --confirm"
    assert_match(/needs explicit confirmation/, command.call(Master::CLI::PipelineContext.new(user_message: "/deploy all")))
  end

  def test_deploy_summary_reports_remote_success_without_the_full_log
    status = Struct.new(:exitstatus) do
      def success? = true
    end.new(0)

    assert_equal(
      "remote: vps-deploy: all ok (master brgen amber bsdports)",
      Registry.send(:deploy_summary, "vps-deploy: all -> master\nvps-deploy: master ok\nvps-deploy: all ok (master brgen amber bsdports)\n", status),
    )
  end

  def test_deploy_summary_keeps_the_decisive_remote_failure
    status = Struct.new(:exitstatus) do
      def success? = false
    end.new(1)

    result = Registry.send(:deploy_summary, "vps-deploy: master web\nfatal: git pull --ff-only failed\nvps-deploy: all halted at master\n", status)

    assert_match(/remote exit 1: .*fatal: git pull --ff-only failed/, result)
    assert_operator result.length, :<=, 170
  end

  def test_critique_is_a_documented_discoverable_command
    assert built.key?("critique")
    assert_includes Registry::HELP_TOPICS.keys, "critique"
    assert_includes Registry.slash_commands, "/critique"
    assert_match(%r{/critique}, Registry.help_text("critique"))
    # review_verbs builds keyword calls in a block, so there is no method_name
    # to read; the command is proved by what it calls.
    called = nil
    Registry.stub(:dispatch_critique, ->(**kwargs) { called = kwargs.keys }) do
      built.fetch("critique").call(Master::CLI::PipelineContext.new(user_message: "/critique", args: ""))
    end
    assert_includes called, :ctx
  end

  def test_no_command_table_is_left_unmerged
    tables = Registry.singleton_methods.map(&:to_s).grep(/_commands\z/) - %w[slash_commands]

    assert_equal %w[control_commands], tables.sort,
                 "a new command table has to be merged by build, or it is a verb with no route"
  end

  def test_screen_starts_master_detached_and_names_the_reattach_command
    spawned = nil
    listing = ["No Sockets found.", nil]
    registry = Master::CLI::CommandRegistry
    Master::Io::Exec.stub(:which, "/usr/bin/screen") do
      Master::Io::Exec.stub(:capture2e, lambda { |*cmd, **|
        spawned = cmd if cmd.include?("-dmS")
        [listing.first, Struct.new(:success?).new(true)]
      }) do
        result = registry.dispatch_screen("/repo", ctx: Master::CLI::PipelineContext.new(user_message: "/screen", args: ""))

        assert_equal ["/usr/bin/screen", "-dmS", "master", "/repo/bin/master"], spawned
        assert_match(/screen -r master/, result)
        assert_match(/letters, digits/, registry.dispatch_screen("/repo", ctx: Master::CLI::PipelineContext.new(user_message: "x", args: "a;b")))
      end
    end
  end

  def test_bare_play_command_renders_and_plays_a_random_progression
    captured = nil
    media = Master::Io::MediaIntent
    original = media.method(:play_live_music)
    media.define_singleton_method(:play_live_music) do |arg, root: MasterPaths.root, **_kwargs|
      captured = [arg, root]
      Master::Result.ok(output: "progression started", rendered: "progression started")
    end

    result = built.fetch("play").call(Master::CLI::PipelineContext.new(user_message: "/play", args: ""))

    assert_equal "progression started", result
    assert_equal "", captured.first
  ensure
    media.define_singleton_method(:play_live_music, original) if original
  end

  def test_play_command_passes_the_request_to_media_intent
    captured = nil
    media = Master::Io::MediaIntent
    original = media.method(:play_live_music)
    media.define_singleton_method(:play_live_music) do |arg, root: MasterPaths.root, **_kwargs|
      captured = [arg, root]
      Master::Result.err("play0: test")
    end

    result = built.fetch("play").call(Master::CLI::PipelineContext.new(user_message: "/play Bach", args: "Bach"))

    assert_equal "play0: test", result
    assert_equal "Bach", captured.first
  ensure
    media.define_singleton_method(:play_live_music, original) if original
  end

  def test_session_commands_are_one_verb
    assert_equal :dispatch_session, built.fetch("session").method_name
    %w[sessions continue resume fork].each { |gone| refute built.key?(gone), "/#{gone} is /session #{gone}" }
    assert_includes Registry.help_text("session"), "/session fork"
  end
  def test_voice_controls_have_sensible_defaults_and_plain_language_presets
    original_mode = ENV.fetch("MASTER_TTS_MODE", nil)
    original_profile = ENV.fetch("MASTER_TTS_PROFILE", nil)
    ENV.delete("MASTER_TTS_MODE")
    ENV.delete("MASTER_TTS_PROFILE")

    Master::Voice::Engines.stub(:openbsd?, false) do
      Master::Voice::Policy.reload!
      assert_equal "classic", Master::Voice::Speech.synthesis_mode
      assert_match(/profile=natural/, Registry.dispatch_voice(ctx: { args: "status" }))
      assert_match(/natural speech selected/, Registry.dispatch_voice(ctx: { args: "natural" }))
      assert_equal "classic", Master::Voice::Speech.synthesis_mode

      assert_match(/Dilla profile selected/, Registry.dispatch_voice(ctx: { args: "dilla" }))
      assert_equal "dilla", Master::Voice::Policy.profile_name
      assert_match(/expressive speech selected/, Registry.dispatch_voice(ctx: { args: "expressive" }))
      assert_equal "transcendent", Master::Voice::Speech.synthesis_mode

      Registry.dispatch_voice(ctx: { args: "natural" })
      assert_equal "classic", Master::Voice::Speech.synthesis_mode
      assert_equal "", Master::Voice::Policy.profile_name
    end
  ensure
    original_mode ? ENV["MASTER_TTS_MODE"] = original_mode : ENV.delete("MASTER_TTS_MODE")
    original_profile ? ENV["MASTER_TTS_PROFILE"] = original_profile : ENV.delete("MASTER_TTS_PROFILE")
    Master::Voice::Policy.reload!
  end

  def test_voice_output_toggles_are_explicit_and_off_interrupts_playback
    original_speak = ENV.fetch("MASTER_CLI_SPEAK", nil)
    interrupted = []

    ENV["MASTER_CLI_SPEAK"] = "0"
    Master::Voice::Playback.stub(:enabled?, true) do
      assert_match(/CLI speech enabled/, Registry.dispatch_voice(ctx: { args: "on" }))
    end
    assert_equal "1", ENV["MASTER_CLI_SPEAK"]

    Master::Voice::Playback.stub(:interrupt!, ->(reason) { interrupted << reason; true }) do
      assert_match(/CLI replies remain text/, Registry.dispatch_voice(ctx: { args: "off" }))
    end
    assert_equal "0", ENV["MASTER_CLI_SPEAK"]
    assert_equal ["voice off"], interrupted
  ensure
    original_speak ? ENV["MASTER_CLI_SPEAK"] = original_speak : ENV.delete("MASTER_CLI_SPEAK")
  end

  def test_voice_test_temporarily_enables_audio_without_changing_the_session
    original_speak = ENV.fetch("MASTER_CLI_SPEAK", nil)
    ENV.delete("MASTER_CLI_SPEAK")
    heard = []

    Master::Voice::Playback.stub(:speak_now, ->(text) {
      heard << [text, ENV["MASTER_CLI_SPEAK"]]
      true
    }) do
      assert_match(/test passed/, Registry.dispatch_voice(ctx: { args: "test" }))
    end

    assert_equal [["MASTER voice test.", "1"]], heard
    refute ENV.key?("MASTER_CLI_SPEAK")
  ensure
    original_speak ? ENV["MASTER_CLI_SPEAK"] = original_speak : ENV.delete("MASTER_CLI_SPEAK")
  end

  def test_voice_help_explains_the_default_and_optional_presets
    help = Registry.help_text("voice")
    ["/voice on|off", "/voice natural", "/voice expressive", "/voice dilla", "/voice timing", "/voice test"].each do |command|
      assert_includes help, command
    end
    assert_match(/web face keeps its own TTS path enabled/i, help)
  end

  def test_fix_activates_and_forwards_the_turn_cancellation_token_before_preflight
    token = Master::Core::CancellationToken.new
    ctx = Master::CLI::PipelineContext.new(user_message: "/fix", args: "").merge(cancellation: token)
    captured = nil
    parsed = lambda do |**arguments|
      captured = arguments
      "preflight stubbed"
    end

    Registry.stub(:dispatch_fix_parsed, parsed) do
      result = Registry.dispatch_fix(
        scanner: nil, fix_loop: nil, deliberation: nil, root: Master::ROOT, bus: nil, ctx:
      )
      assert_equal "preflight stubbed", result
    end

    assert_predicate token, :active?
    assert_same token, captured.fetch(:cancellation)
  end

end

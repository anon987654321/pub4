# frozen_string_literal: true

require "test_helper"
require "cli/core_bridge"
require "tmpdir"
require "minitest/mock"

# The bridge runs one goal through the core Fold from inside the CLI and streams
# turns to the event bus. These pin that it works fully offline (scripted model),
# returns a Fold summary, and publishes a turn event the dashboard can render.
class CoreBridgeTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:, **) = @effects.shift || Master::Core::Effect.done("done")
  end

  class FakeBus
    # Positional like the real Trace::EventBus. A kwargs-only publish rejects
    # Mission#emit's positional hash, and its rescue swallows the refusal
    # silently — every mission:* event would vanish from the test bus.
    attr_reader :events
    def initialize = @events = []
    def publish(name, payload = {}) = @events << [name, payload]
    def publish_required(name, payload = {}) = @events << [name, payload]
  end

  # The real Constitution blocks `done` before an evidence threshold, so a
  # completing run must first produce passing exec evidence — same as production.
  #
  # The argv has to name a command Proof::PRODUCERS recognises. Declaring
  # `evidence: :test_pass` on `true` records nothing: an exec that claims an
  # evidence kind its command could not have produced is the forgery that guard
  # exists to refuse, so these ran three no-ops, earned no evidence, and the
  # fold spun to max_turns refusing `done` forty times. `echo` keeps them
  # side-effect free while the argv stays something a producer pattern matches.
  def evidence_then_done(*extra, summary:)
    [
      *extra,
      Master::Core::Effect.exec(%w[echo rake test], evidence: :test_pass),
      Master::Core::Effect.exec(%w[echo rubocop], evidence: :scan_clean),
      Master::Core::Effect.exec(%w[echo rake review], evidence: :code_review),
      Master::Core::Effect.done(summary),
    ]
  end

  def test_run_returns_summary_and_streams_turns
    Dir.mktmpdir do |root|
      bus = FakeBus.new
      model = ScriptedModel.new(
        *evidence_then_done(Master::Core::Effect.write("note.txt", "hello\n"), summary: "wrote the note"),
      )
      result = Master::CLI::CoreBridge.run("write a note", root:, bus:, model:)

      assert_equal :complete, result[:reason]
      assert_equal "wrote the note", result[:summary]
      assert_equal "hello\n", File.read(File.join(root, "note.txt"))
      assert(bus.events.any? { |name, _| name == "core:turn" }, "expected a core:turn event")
    end
  end

  def test_trace_failed_mission_is_terminal_unknown_outcome_not_auto_deferred
    mission = Object.new
    mission.define_singleton_method(:finish!) { |state:, summary:| @finished = [state, summary] }
    mission.define_singleton_method(:defer!) { |**| flunk("ambiguous side effects must not auto-continue") }
    mission.define_singleton_method(:fail!) { |*| flunk("unknown outcome must not be collapsed into generic failure") }
    mission.define_singleton_method(:block!) { |**| flunk("trace failure is not a policy block") }

    done = Master::Core::Fold::Done.new(
      reason: :trace_failed, turns: 1, summary: "after-event persistence failed"
    )
    Master::CLI::CoreBridge.settle_mission(mission, done)

    assert_equal ["unknown_outcome", "after-event persistence failed"],
                 mission.instance_variable_get(:@finished)
  end

  def test_cancelled_fold_is_persisted_as_terminal_mission_state
    Dir.mktmpdir do |root|
      model = Object.new
      model.define_singleton_method(:propose) do |*|
        flunk("a pre-cancelled mission must not call the model")
      end
      cancellation = Master::Core::CancellationToken.new.cancel!(reason: "operator stopped")

      result = Master::CLI::CoreBridge.run(
        "cancel without starting work", root:, model:, cancellation:
      )

      assert_equal :cancelled, result[:reason]
      assert_equal "cancelled: operator stopped", result[:summary]
      record = Master::Fix::Mission.current(root:)
      assert_equal "cancelled", record["state"]
      assert_equal "execute", record["stage"], "cancellation must not pretend that verification or delivery happened"
      assert_equal false, record["auto_continue"] if record.key?("auto_continue")
    end
  end

  def test_ambiguous_fold_outcomes_are_terminal_and_never_auto_deferred
    %i[unknown_outcome recovery_failed].each do |reason|
      Dir.mktmpdir do |root|
        mission = Master::Fix::Mission.new(root:).start_or_resume!(
          goal: "reconcile external effect", scope: root, origin: "fold", auto_continue: true
        )
        mission.transition!(:execute)
        done = Master::Core::Fold::Done.new(
          reason:, turns: 1, summary: "#{reason}: receipt unavailable"
        )

        Master::CLI::CoreBridge.settle_mission(mission, done)

        record = Master::Fix::Mission.current(root:)
        assert_equal reason.to_s, record["state"]
        assert_equal "execute", record["stage"]
        refute_includes Master::Fix::Mission::RESUMABLE_STATES, record["state"]
      end
    end
  end

  def test_lifecycle_events_persist_without_a_host_bus
    Dir.mktmpdir do |root|
      model = ScriptedModel.new(*evidence_then_done(
        Master::Core::Effect.write("persisted.txt", "never log this payload"), summary: "ok"
      ))

      result = Master::CLI::CoreBridge.run("persist a note", root:, model:)

      assert_equal :complete, result[:reason]
      records = File.readlines(File.join(root, "runtime", "events", "activity.jsonl"))
                      .map { |line| JSON.parse(line) }
      events = records.select { |record| record["event"].start_with?("core:effect:") }
      assert events.any? { |record| record["event"] == "core:effect:before" }
      assert events.any? { |record| record["event"] == "core:effect:after" }
      before = events.find { |record| record["event"] == "core:effect:before" }
      after = events.find { |record| record["event"] == "core:effect:after" }
      assert_equal before["effect_id"], after["effect_id"]
      assert_equal before["run_id"], after["run_id"]
      assert_equal before["attempt_id"], after["attempt_id"]
      assert_equal "#{result[:mission]["id"]}:#{result[:mission]["attempt_count"]}", before["attempt_id"]
      assert_equal before["mission_id"], after["mission_id"]
      assert_equal before["checkpoint_id"], after["checkpoint_id"]
      assert before["checkpoint_id"], "the reversible write should link its checkpoint"
      assert_equal result[:mission]["id"], before["mission_id"]
      assert_match(/\A[0-9a-f]{64}\z/, before["scope_digest"])
      assert_equal before["scope_digest"], after["scope_digest"]
      persisted = File.read(File.join(root, "runtime", "events", "activity.jsonl"))
      refute_includes persisted, "never log this payload"
      refute_includes persisted, "persisted.txt"
    end
  end

  def test_core_turn_stream_does_not_persist_private_read_output
    Dir.mktmpdir do |root|
      private_text = "private customer content\nsecond private line\n"
      File.write(File.join(root, "private.txt"), private_text)
      bus = FakeBus.new
      model = ScriptedModel.new(*evidence_then_done(
        Master::Core::Effect.read("private.txt"), summary: "read complete"
      ))

      result = Master::CLI::CoreBridge.run("read a private file", root:, bus:, model:)

      assert_equal :complete, result[:reason]
      turn = bus.events.find { |name, payload| name == "core:turn" && payload[:verb] == :read }
      assert_equal "file read", turn.last[:subject]
      assert_equal "completed", turn.last[:detail]
      assert_equal private_text.bytesize, turn.last[:output_bytes]
      assert_equal private_text.lines.size, turn.last[:output_lines]
      refute turn.last.values.include?(private_text)
      refute bus.events.inspect.include?(private_text)
    end
  end

  def test_core_effect_lifecycle_events_are_paired_and_redacted
    Dir.mktmpdir do |root|
      bus = FakeBus.new
      effect = Master::Core::Effect.write("private.txt", "secret payload")
      model = ScriptedModel.new(*evidence_then_done(effect, summary: "ok"))

      result = Master::CLI::CoreBridge.run("write a private note", root:, bus:, model:)

      assert_equal :complete, result[:reason]
      events = bus.events.select { |name, payload| name.start_with?("core:effect:") && payload[:verb] == :write }
      assert_equal %w[core:effect:before core:effect:after], events.map(&:first)
      assert_equal events.first.last[:effect_id], events.last.last[:effect_id]
      refute events.any? { |_name, payload| payload.values.include?("secret payload") }
      turn = bus.events.find { |name, payload| name == "core:turn" && payload[:verb] == :write }
      assert_equal "file write", turn.last[:subject]
      assert_equal "completed", turn.last[:detail]
      refute turn.last.key?(:content)
    end
  end

  # defer! reads delay and retry_count after with_lock returns; defined inside
  # the block they died with it and the emit below named an unset local.
  # CoreBridge.settle_mission routes any fold end that is neither complete nor
  # needs-user here.
  def test_defer_reaches_the_emit_with_retry_and_delay
    Dir.mktmpdir do |root|
      bus = FakeBus.new
      mission = Master::Fix::Mission.new(root:, bus:).start_or_resume!(
        goal: "fix the pool",
        scope: root,
        model: "agy:auto",
        effort: "low",
        origin: "fold",
      )
      mission.defer!(reason: "attempt exhausted", seconds: 60)

      event = bus.events.find { |name, _| name == "mission:deferred" }
      assert event, "expected a mission:deferred event"
      assert_equal 60, event.last[:delay_seconds]
      assert_equal 1, event.last[:retry_count]
      assert_equal "waiting", Master::Fix::Mission.current(root:)["state"]
    end
  end

  # /undo pops the session journal's newest entry. A fold write that journals
  # nothing leaves an earlier session's snapshot on top, and /undo reverts that
  # file instead of the one the fold just wrote.
  def test_undo_after_a_fold_turn_restores_the_folds_file_and_nothing_else
    Dir.mktmpdir do |root|
      older = File.join(root, "older.txt")
      note = File.join(root, "note.txt")
      File.write(older, "earlier session\n")
      File.write(note, "before\n")
      session = Object.new.tap { |s| def s.snapshot(*) = nil }
      undo = Master::Trace::Undo.new(session:, root:)
      undo.snapshot(older)
      File.write(older, "kept\n")

      model = ScriptedModel.new(*evidence_then_done(Master::Core::Effect.write("note.txt", "after\n"), summary: "ok"))
      Master::CLI::CoreBridge.run("rewrite the note", root:, model:, container: { undo: })
      assert_equal "after\n", File.read(note)

      undo.undo!
      assert_equal "before\n", File.read(note), "/undo should restore the file the fold wrote"
      assert_equal "kept\n", File.read(older), "/undo should leave the earlier session's file alone"
    end
  end

  # Constitution and World each used to resolve the root on their own, so a
  # relative path could name one file to the check and another to the writer.
  def test_the_constitution_and_the_world_share_the_resolved_workspace_root
    Dir.mktmpdir do |given|
      Dir.mktmpdir do |resolved|
        seen = nil
        real = Master::Core::Constitution.method(:load)
        loader = ->(**kw) { seen = kw[:workspace_root]; real.call(**kw) }
        Master::CLI::CoreBridge.stub(:workspace_root_for, resolved) do
          Master::Core::Constitution.stub(:load, loader) do
            Master::CLI::CoreBridge.run("goal", root: given, model: ScriptedModel.new, max_turns: 1)
          end
        end
        assert_equal resolved, seen
      end
    end
  end

  # WriteGuard reads the file on disk as the "before" side, so it needs the
  # path the World writes to rather than one relative to the process cwd.
  def test_the_scan_verifier_hands_the_guard_the_absolute_path
    Dir.mktmpdir do |root|
      paths = []
      guard = Object.new
      guard.define_singleton_method(:verdict) do |path:, content:|
        paths << path
        Struct.new(:blocking).new([])
      end
      Master::Fix::WriteGuard.stub(:default, guard) do
        Master::CLI::CoreBridge.scan_verifier(root:).call(path: "lib/a.rb", content: "A = 1\n")
      end
      assert_equal [File.join(root, "lib/a.rb")], paths
    end
  end

  def test_run_string_renders_a_transcript
    Dir.mktmpdir do |root|
      model = ScriptedModel.new(*evidence_then_done(summary: "all clear"))
      out = Master::CLI::CoreBridge.run_string("check", root:, model:)
      assert_match(/core: complete/, out)
      assert_match(/all clear/, out)
    end
  end

  def test_empty_goal_is_refused
    assert_equal "core: no goal", Master::CLI::CoreBridge.run_string("   ", root: Dir.pwd)
  end

  # The fold asked RubyLLM directly, so MASTER_MODEL and the failover hop never
  # reached it: forced to a local model, a turn still went to OpenRouter.
  class RecordingAgent
    attr_reader :calls
    def initialize = @calls = []

    def ask_once(prompt, system:, law:, temperature:, format:)
      @calls << { prompt:, system:, law:, temperature:, format: }
      '{"verb": "note", "args": {"kind": "probe", "text": "asked"}}'
    end
  end

  def test_the_fold_asks_through_the_agent_dispatcher
    Dir.mktmpdir do |root|
      agent = RecordingAgent.new
      Master::CLI::CoreBridge.run("goal", root:, container: { agent: }, max_turns: 1)

      refute_empty agent.calls
      assert_equal Master::Core::Model::SYSTEM, agent.calls.first[:system]
      refute agent.calls.first[:law], "Core::Model's prompt is the whole contract"
      offered = agent.calls.first[:format].dig(:properties, :verb, :enum)
      refute_includes offered, "done", "a first turn has read nothing and proved nothing"
      assert_includes offered, "read"
      assert_equal 0, agent.calls.first[:temperature], "every model decodes the fold alike"
    end
  end

  # A small local model that cannot hold the fold answers in prose. Two such
  # replies in a row move the fold to the next larger local model, and past the
  # largest to the routed cloud lane when the network answers.
  class LadderAgent
    attr_reader :models
    attr_accessor :replies

    def initialize(replies) = (@replies, @models = replies, [])
    def model = "ollama:gemma3:4b"
    def candidate_models = ["ollama:gemma3:4b", "openrouter/some-cloud"]

    def ask_once(_prompt, model: nil, **)
      @models << model
      @replies.shift || %({"why": "look", "verb": "read", "args": {"path": "a"}})
    end
  end

  class SizedRouter
    SIZES = { "gemma3:4b" => 3, "llama3" => 4, "phi" => 2 }.freeze
    def local_models = %w[ollama:llama3 ollama:gemma3:4b ollama:phi]
    def ollama_size(name) = SIZES.fetch(name, 0)
  end

  def ladder_run(replies, online:)
    agent = LadderAgent.new(replies)
    ladder = Master::CLI::CoreBridge::ModelLadder.new(agent:, router: SizedRouter.new, online: -> { online })
    chat = Master::CLI::CoreBridge::AgentChat.new(agent, nil, nil, nil, ladder)
    6.times { chat.with_instructions("sys").ask("turn") }
    agent.models
  end

  def test_two_unparseable_replies_climb_to_the_next_larger_local_model
    models = ladder_run(["I cannot help with that.", "no idea"], online: false)
    assert_equal [nil, nil, "ollama:llama3"], models.first(3)
  end

  def test_one_bad_reply_between_good_ones_does_not_climb
    good = %({"why": "x", "verb": "read", "args": {"path": "a"}})
    assert_equal [nil] * 6, ladder_run(["prose", good, "prose", good], online: false)
  end

  def test_past_the_largest_local_model_the_cloud_lane_answers_when_online
    models = ladder_run(%w[a b c d], online: true)
    assert_equal "ollama:llama3", models[2]
    assert_equal "openrouter/some-cloud", models[4]
  end

  def test_offline_past_the_largest_local_model_the_fold_stays_where_it_is
    models = ladder_run(%w[a b c d], online: false)
    assert_equal "ollama:llama3", models.last
  end

  # A push is a Request. The interactive terminal answers it; a turn with no
  # asker on its fiber (the daemon, a pipe, the web face) refuses as before.
  # The push runs in a directory that is no repository, so an approved one
  # fails at git rather than reaching a remote.
  def push_transcript(asker)
    Dir.mktmpdir do |root|
      model = ScriptedModel.new(Master::Core::Effect.exec(%w[git push origin main]))
      Fiber[:master_terminal_ask] = asker
      Master::CLI::CoreBridge.run("push", root:, model:, max_turns: 1)[:transcript].join("\n")
    ensure
      Fiber[:master_terminal_ask] = nil
    end
  end

  def test_a_terminal_yes_lets_a_requested_effect_run
    asked = []
    line = push_transcript(lambda { |prompt:, **| asked << prompt; "y" })
    assert_match(/git push origin main/, asked.first)
    refute_match(/needs approval/, line)
  end

  def test_a_terminal_no_refuses_and_says_who_asked
    assert_match(/sandboxed_exec needs approval/, push_transcript(->(**) { "" }))
  end

  def test_no_asker_on_the_turn_still_refuses
    assert_match(/needs approval.*no surface to ask/, push_transcript(nil))
  end

  def test_repeated_capability_refusal_stops_and_blocks_the_mission
    Dir.mktmpdir do |root|
      model = ScriptedModel.new(
        Master::Core::Effect.exec(%w[git status --short]),
        Master::Core::Effect.read("README.md"),
        Master::Core::Effect.exec(%w[git status --short]),
        Master::Core::Effect.done("must not complete"),
      )

      result = Master::CLI::CoreBridge.run(
        "inspect the tree", root:, model:, mode: :observe, max_turns: 8
      )

      assert_equal :blocked, result[:reason]
      assert_equal 3, result[:turns]
      assert_match(/repeated exec refusal/, result[:summary])
      assert_equal "blocked", result[:mission]["state"]
    end
  end

  def test_on_turn_callback_fires_per_turn
    Dir.mktmpdir do |root|
      lines = []
      model = ScriptedModel.new(*evidence_then_done(summary: "done"))
      Master::CLI::CoreBridge.run("goal", root:, model:, on_turn: ->(line) { lines << line })
      refute_empty lines
      assert(lines.all? { |line| line.match?(/\A\d+:/) })
    end
  end
end

# The sandbox answers :deny, :ask or :allow. The bridge used to forward only
# :deny, so :ask reached the Constitution as nil and nil means proceed — the
# policy marked `git push`, a hard reset and a deploy as needing a person, and
# the one path that runs unattended did them without asking.
#
# It cannot simply forward every :ask either. :ask is also what the policy
# answers for any command it has no pattern for, which is most of them, so that
# would stop the fold running its own tests. The two are told apart by whether
# the policy recognised the command by name.
class CoreBridgeSandboxTest < Minitest::Test
  def sandbox = Master::CLI::CoreBridge.send(:shell_sandbox, root: Dir.pwd)

  def test_a_recognised_ask_asks_a_person_instead_of_proceeding
    assert_equal({ ask: "matched ask pattern" }, sandbox.call(%w[git push origin main]))
  end

  def test_the_other_named_asks_are_carried_too
    [%w[git reset --hard], %w[git clean -fd .], %w[bundle exec rails db:drop]].each do |argv|
      answer = sandbox.call(argv)
      assert_kind_of Hash, answer, "#{argv.join(' ')} should reach a person"
      assert answer[:ask], "#{argv.join(' ')} should carry an ask reason"
    end
  end

  def test_a_command_the_policy_does_not_recognise_still_proceeds
    assert_nil sandbox.call(%w[bundle exec rake test]),
               "the fold has to be able to run its own tests without asking"
  end

  def test_a_denial_still_returns_a_reason
    answer = sandbox.call(["rm", "-rf", "/"])
    assert_kind_of String, answer
    refute_empty answer
  end

  # End to end: the rule the bridge feeds turns a recognised ask into a Request,
  # which is the verdict the Fold pauses on rather than one it executes.
  def test_the_constitution_turns_a_recognised_ask_into_a_request
    law = Master::Core::Constitution.new(
      laws: [Master::Core::Constitution.send(:sandboxed_exec_rule, sandbox)],
    )
    verdict = law.admit(Master::Core::Effect.exec(%w[git push origin main]), nil)

    assert_kind_of Master::Core::Verdict::Request, verdict
    assert_match(/git push origin main/, verdict.prompt)
  end

  def test_the_constitution_still_allows_an_unrecognised_command
    law = Master::Core::Constitution.new(
      laws: [Master::Core::Constitution.send(:sandboxed_exec_rule, sandbox)],
    )
    verdict = law.admit(Master::Core::Effect.exec(%w[bundle exec rake test]), nil)

    refute_kind_of Master::Core::Verdict::Request, verdict
    refute_kind_of Master::Core::Verdict::Block, verdict
  end

  def test_observe_mode_is_read_only
    Dir.mktmpdir do |root|
      File.write(File.join(root, "README.md"), "hello\n")
      model = CoreBridgeTest::ScriptedModel.new(
        Master::Core::Effect.read("README.md"),
        Master::Core::Effect.done("read-only assessment"),
      )
      result = Master::CLI::CoreBridge.run(
        "inspect the repository", root:, model:, mode: :observe, max_turns: 2
      )
      assert_equal :complete, result[:reason]
      assert_equal "observe", result[:mission].dig("operator", "mode")
    end
  end
  def test_run_string_leaves_keyless_local_and_cli_fallbacks_to_the_router
    Dir.mktmpdir do |root|
      called = false
      runner = lambda do |goal, root:, bus: nil, model: nil, model_id: nil|
        called = true
        { reason: :complete, turns: 1, summary: "keyless lane answered", transcript: ["routed #{goal}"], risk: :low }
      end

      Master.stub(:any_api_key_present?, false) do
        Master::CLI::CoreBridge.stub(:run, runner) do
          output = Master::CLI::CoreBridge.run_string("status", root:)
          assert called
          assert_match(/core: complete turns=1/, output)
          assert_match(/keyless lane answered/, output)
        end
      end
    end
  end

  def test_allowed_tools_narrow_the_profile_and_refuse_scoped_entries
    caps = Master::Core::Capabilities.for(:repair)
    _, err = capture_io { Master::CLI::CoreBridge.grant_tools(caps, "Read Edit Bash(git diff:*) Frobnicate") }
    assert_equal %i[stdio read write], caps.capabilities
    assert_includes err, "Bash(git diff:*)"
    assert_includes err, "Frobnicate"
  end

  def test_allowed_tools_never_widen_the_profile
    caps = Master::Core::Capabilities.for(:observe)
    Master::CLI::CoreBridge.grant_tools(caps, "Bash Write")
    assert_equal %i[stdio read], caps.capabilities
  end

  def test_empty_allowed_tools_leaves_the_fold_read_only
    caps = Master::CLI::CoreBridge.grant_tools(Master::Core::Capabilities.for(:repair), "")
    assert_equal %i[stdio read], caps.capabilities
  end

  def test_only_plan_permission_mode_changes_the_operator_mode
    assert_equal :plan, Master::CLI::CoreBridge.mode_for_permission("plan")
    %w[default acceptEdits bypassPermissions].each do |name|
      assert_nil Master::CLI::CoreBridge.mode_for_permission(name)
    end
    assert_nil Master::CLI::CoreBridge.mode_for_permission(nil)
  end
end

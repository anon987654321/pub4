# frozen_string_literal: true

require "test_helper"
require "cli/core_bridge"
require "tmpdir"

# The bridge runs one goal through the core Fold from inside the CLI and streams
# turns to the event bus. These pin that it works fully offline (scripted model),
# returns a Fold summary, and publishes a turn event the dashboard can render.
class CoreBridgeTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:, **) = @effects.shift || Master::Core::Effect.done("done")
  end

  class FakeBus
    attr_reader :events
    def initialize = @events = []
    def publish(name, **payload) = @events << [name, payload]
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
  def sandbox = Master::CLI::CoreBridge.send(:shell_sandbox)

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
      rules: [Master::Core::Constitution.send(:sandboxed_exec_rule, sandbox)],
    )
    verdict = law.admit(Master::Core::Effect.exec(%w[git push origin main]), nil)

    assert_kind_of Master::Core::Verdict::Request, verdict
    assert_match(/git push origin main/, verdict.prompt)
  end

  def test_the_constitution_still_allows_an_unrecognised_command
    law = Master::Core::Constitution.new(
      rules: [Master::Core::Constitution.send(:sandboxed_exec_rule, sandbox)],
    )
    verdict = law.admit(Master::Core::Effect.exec(%w[bundle exec rake test]), nil)

    refute_kind_of Master::Core::Verdict::Request, verdict
    refute_kind_of Master::Core::Verdict::Block, verdict
  end
end

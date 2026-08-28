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
    def propose(_context, verbs:) = @effects.shift || Master::Core::Effect.done("done")
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

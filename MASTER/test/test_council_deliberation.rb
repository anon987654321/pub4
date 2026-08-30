# frozen_string_literal: true

require_relative "test_helper"

class TestCouncilDeliberation < Minitest::Test
  Gate = Master::Ground::QuotaGate
  CREDITS = "Insufficient credits. Add more using https://openrouter.ai"

  Persona = Struct.new(:name, :role, :bias, :prompt, :veto_role, :emphasizes, keyword_init: true) do
    def veto? = !!veto_role
  end

  # The gate is process-wide by design — one account, one fact — so a test
  # that trips it hands the next test a closed council unless it puts it back.
  def setup = Gate.reset!
  def teardown = Gate.reset!

  # Counts calls, so "did not spend the call" is a measurement and not a
  # reading of the log.
  class BrokeAgent
    attr_reader :calls

    def initialize(fail_times: Float::INFINITY)
      @calls = 0
      @fail_times = fail_times
    end

    def ask(_prompt, **)
      @calls += 1
      raise(StandardError, CREDITS) if @calls <= @fail_times

      "looks good"
    end
  end

  class StubAgent
    def initialize(mapping = {})
      @mapping = mapping
    end

    def ask(prompt, **)
      @mapping.each do |needle, response|
        return response if prompt.include?(needle)
      end
      "looks good"
    end
  end

  # Stubbed, not inherited: review refuses without a provider key, and keys
  # reach ENV through EnvLoader at boot — which neither tests nor bare
  # requires run. This test failed on any shell without exported keys and
  # passed on any with them, which is an environment reading, not a test.
  def test_veto_blocks_review
    personas = [
      Persona.new(name: "Security", role: "Attacker", bias: "paranoid", prompt: "be strict", veto_role: true),
    ]
    agent = StubAgent.new("You are Security" => "VETO: unsafe eval path")

    result = Master.stub(:any_api_key_present?, true) do
      Master::Review::Council::Deliberation.new(personas:, agent:, judge_enabled: false)
                                           .review("eval(params[:x])")
    end

    assert result.err?
    assert_equal :validation, result.category
    assert_match(/veto/i, result.message)
  end

  # The CLI-lane posture: a dev Mac cannot hear 26 personas inside the budget
  # (the file writes the arithmetic down), so local runs take one round of a
  # capped panel, veto roles surviving the cut first. vm23 hears everyone.
  def test_local_posture_caps_the_panel_and_rounds
    old = ENV["MASTER_COUNCIL_LOCAL"]
    ENV["MASTER_COUNCIL_LOCAL"] = "1"
    assert Master::Review::Council::Deliberation.local_posture?
    cap = Master::Review::Council::Deliberation.local_panel_size
    assert_operator cap, :>=, 3, "a panel below quorum cannot deliberate"

    critic = Master::Review::Council::Critique.new(mode: :general, agent: nil, files: [])
    panel = Array.new(26) do |i|
      Persona.new(name: i < 2 ? "Veto#{i}" : "P#{i}", role: "r", bias: "b", prompt: "p", veto_role: i < 2)
    end
    localized = critic.send(:localize_panel, panel)
    assert_equal cap, localized.size
    assert localized.take(2).all?(&:veto?), "veto roles must survive the cut first"

    ENV["MASTER_COUNCIL_LOCAL"] = "0"
    assert_equal panel, critic.send(:localize_panel, panel)
  ensure
    old.nil? ? ENV.delete("MASTER_COUNCIL_LOCAL") : ENV["MASTER_COUNCIL_LOCAL"] = old
  end

  def test_quorum_error_carries_the_failure_tally
    failing = BrokeAgent.new
    personas = Array.new(4) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }

    result = Master.stub(:any_api_key_present?, true) do
      Master::Review::Council::Deliberation.new(personas:, agent: failing, judge_enabled: false)
                                           .review("puts :ok")
    end

    assert result.err?
    assert_match(/quorum not reached \(0\/4\)/, result.message)
    assert_match(/insufficient_credits/, result.message, "the reason tally is the actionable half")
  end

  # The defect this fixes: four personas each bought the same refusal, and the
  # run then reported on everything else as though nothing were missing.
  # Sequential mode makes the count deterministic — the parallel case cannot
  # recall a batch already in flight, only the batches after it.
  def test_a_spend_limit_stops_the_council_after_one_refusal
    failing = BrokeAgent.new
    personas = Array.new(12) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }

    result = Master.stub(:any_api_key_present?, true) do
      Master::Review::Council::Deliberation.new(personas:, agent: failing, judge_enabled: false, mode: :sequential)
                                           .review("puts :ok")
    end

    assert_equal 1, failing.calls, "the second call was guaranteed to fail; it must not be spent"
    assert result.err?
    assert_equal Gate::CATEGORY, result.category, "a chain stage branches on this, not on prose"
    assert_match(/SKIPPED council/, result.message, "could not run must not read as a pass")
    assert_match(/spend limit/, result.message)
    assert_includes Gate.skipped_tiers, "council"
  end

  # Once tripped, a second council in the same run does not re-buy the refusal.
  def test_the_next_council_in_the_run_is_skipped_not_retried
    failing = BrokeAgent.new
    personas = Array.new(4) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }
    delib = Master::Review::Council::Deliberation.new(personas:, agent: failing, judge_enabled: false,
                                                     mode: :sequential)

    Master.stub(:any_api_key_present?, true) { delib.review("puts :ok") }
    spent = failing.calls
    second = Master.stub(:any_api_key_present?, true) { delib.review("puts :other") }

    assert_equal spent, failing.calls, "the gate is still closed; nothing more is spent"
    assert_equal Gate::CATEGORY, second.category
    assert_match(/SKIPPED council/, second.message)
  end

  # Resume, with no code change and no manual reset: the limit lifts, the
  # backoff elapses, and the next round runs. A breaker that latched for the
  # process would have deleted the tier for the rest of a long gate.
  def test_the_council_resumes_when_the_limit_lifts
    agent = BrokeAgent.new(fail_times: 1)
    personas = Array.new(4) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }
    delib = Master::Review::Council::Deliberation.new(personas:, agent:, judge_enabled: false, mode: :sequential)

    first = Master.stub(:any_api_key_present?, true) { delib.review("puts :ok") }
    assert first.err?
    assert Gate.blocked?

    second = Master::Ground::FailureTaxonomy.stub(:backoff_seconds, 0) do
      Gate.trip!(source: "test", message: CREDITS) # re-arm with the backoff elapsed
      Master.stub(:any_api_key_present?, true) { delib.review("puts :ok") }
    end

    assert second.ok?, "the council must come back on its own: #{second.message if second.err?}"
    assert_equal 4, second.value!.size
  end

  def test_empty_personas_fails_validation
    result = Master::Review::Council::Deliberation.new(personas: [], agent: StubAgent.new, judge_enabled: false)
                                        .review("puts :ok")

    assert result.err?
    assert_equal :validation, result.category
    assert_match(/no personas/, result.message)
  end
end

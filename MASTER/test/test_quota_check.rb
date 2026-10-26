# frozen_string_literal: true

require_relative "test_helper"
# Zeitwerk is told to ignore this file (data/autoload.yml), so the semantic
# tier only exists once something requires it — the same require every other
# test of these rules makes.
require_relative "../law/detectors/semantic_laws"

class TestQuotaCheck < Minitest::Test
  Check = Master::Io::QuotaCheck
  CREDITS = "Insufficient credits. Add more using https://openrouter.ai"

  def setup
    Check.reset!
    @lane_dir = Dir.mktmpdir
    Master::Io::LaneQuota.path = File.join(@lane_dir, "lane_quota.yml")
  end

  def teardown
    Check.reset!
    Master::Io::LaneQuota.path = nil
    FileUtils.remove_entry(@lane_dir)
  end

  # One provider out of credit closes its own lane. The subscription CLI the
  # council also speaks through stays spendable, so the panel still sits.
  def test_a_spend_limit_closes_only_the_lane_that_hit_it
    Check.trip!(source: "council persona P0", message: CREDITS, model: "openrouter:nvidia/nemotron:free")

    assert Check.blocked?("openrouter:nvidia/nemotron:free")
    refute Check.blocked?("claude-cli:claude-sonnet-5-5")
    assert Check.blocked?, "asked without a model, the tier still reads as blocked"
  end

  def test_a_trip_without_a_model_closes_only_the_provider_its_error_names
    Check.trip!(source: "council persona P0", message: CREDITS)

    assert Check.blocked?("openrouter:nvidia/nemotron:free")
    refute Check.blocked?("claude-cli:claude-sonnet-5-5")
  end

  def test_a_trip_without_a_model_closes_every_lane
    Check.trip!(source: "semantic Law X", message: "Individual quota reached")

    assert Check.blocked?("claude-cli:claude-sonnet-5-5")
  end

  # The whole point of the class: a spend limit and a throttle want opposite
  # answers, so they cannot share a category.
  def test_a_spend_limit_is_not_a_rate_limit
    taxonomy = Master::Ground::FailureTaxonomy.new
    assert_equal :exhausted, taxonomy.classify(CREDITS)
    assert_equal :exhausted, taxonomy.classify("HTTP 402 Payment Required")
    assert_equal :transient, taxonomy.classify("rate limit exceeded"),
                 "a throttle still wants backoff-and-retry, not a pause"

    info = taxonomy.handle(StandardError.new(CREDITS))
    assert_equal "pause_and_reprobe", info[:strategy]
    assert_equal 0, info[:max_retries].to_i, "an in-place retry cannot make an account solvent"
  end

  def test_lane_silence_is_a_semantic_skip_not_a_scan_failure
    agent = Class.new do
      define_method(:ask) do |_prompt, **|
        raise StandardError, "no lane answered 12 calls in a row; model work is skipped for 5 minutes. /model list says what each lane needs."
      end
    end.new

    rule = Master::Review::Scan::Laws::AdversarialLaw.new.set_agent(agent)

    error = assert_raises(RuntimeError) { rule.check("def a = 1\n", path: "x.rb") }

    assert_match(/semantic assessment INCONCLUSIVE/, error.message, "an unmeasured tier is not a clean file")
    assert_equal ["semantic Laws"], Check.skipped_tiers
  end

  def test_individual_quota_reached_is_exhaustion
    taxonomy = Master::Ground::FailureTaxonomy.new

    assert_equal :exhausted, taxonomy.classify("Individual quota reached. Please upgrade your subscription")
    assert Check.trip_if_limited(source: "agy", message: "Individual quota reached")
    assert Check.blocked?
    assert_equal :exhausted, Check.state
  end

  # Trip once, say so once. Four personas hitting the same empty balance is
  # one fact about the account, not four about the personas.
  def test_trips_once_and_only_the_first_caller_is_told_to_announce
    assert Check.trip!(source: "council persona P0", message: CREDITS), "first trip announces"
    refute Check.trip!(source: "council persona P1", message: CREDITS), "the rest stay quiet"
    refute Check.trip!(source: "council persona P2", message: CREDITS)

    assert Check.blocked?
    assert Check.tripped?
    assert_equal :exhausted, Check.state
  end

  # The report is the honest half: a run that skipped a whole tier must name
  # the tier, not fold it into a pass.
  def test_report_names_the_skipped_tier_and_the_cause
    assert_nil Check.report, "a healthy run has nothing to report"

    Check.trip!(source: "council persona P0", message: CREDITS, model: "openrouter/free")
    Check.skipped("semantic rules")
    Check.skipped("semantic rules")
    Check.skipped("council")

    assert_equal ["semantic rules", "council"], Check.skipped_tiers, "one fact per tier, not per file"
    report = Check.report
    assert_match(/\ASKIPPED semantic rules, council/, report)
    assert_match(/spend limit/, report)
    assert_match(/openrouter\/free/, report)
    assert_match(/re-probing in \d+s/, report, "the reader needs to know it comes back")
    assert_equal :exhausted, Check.status[:state]
    assert_equal 1, Check.status[:confirmations], "recording a skipped tier is not another confirmation"
  end

  # Not a latch. The operator's reading is that these limits lift within
  # minutes, so a breaker that never re-probes turns a short outage into a
  # whole run of silently skipped work.
  def test_reprobes_on_the_shared_backoff_rather_than_latching
    Check.trip!(source: "council", message: CREDITS)
    assert Check.blocked?
    assert_equal Master::Ground::FailureTaxonomy.backoff_seconds(0), Check.seconds_until_probe,
                 "the wait is the taxonomy's backoff, not a second formula"

    Check.reset!
    Master::Ground::FailureTaxonomy.stub(:backoff_seconds, 0) do
      Check.trip!(source: "council", message: CREDITS)
      refute Check.blocked?, "once the backoff elapses the next call goes through"
    end
    assert Check.tripped?, "the run still remembers that a tier was hit"
  end

  # Confirmed again means wait longer, so a limit that is genuinely down for
  # an hour is not probed every second.
  def test_each_confirmation_widens_the_wait
    Check.trip!(source: "council", message: CREDITS)
    first = Check.seconds_until_probe
    Check.trip!(source: "council", message: CREDITS)
    assert_operator Check.seconds_until_probe, :>, first
  end

  # The third state. A revoked key is not a balance that refills.
  # A file path is not a provider answer: test_forbidden_patterns_guard.rb paused every paid call.
  def test_a_refusal_word_inside_a_file_name_is_not_a_refusal
    refute Master::Io::QuotaCheck.refusal?("no model agent configured for test/test_forbidden_patterns_guard.rb")
    assert Master::Io::QuotaCheck.refusal?("HTTP 403 Forbidden")
  end

  def test_a_refused_key_stops_instead_of_reprobing
    Check.trip!(source: "agent single-shot", message: "401 Unauthorized: invalid api key")

    assert_equal :refused, Check.state
    assert Check.blocked?
    assert_nil Check.seconds_until_probe, "nothing is being waited for"
    assert_match(/refused the key/, Check.report)
    assert_match(/needs a human/, Check.report)
  end

  # A paid call that came back is the only evidence the limit lifted.
  def test_a_successful_call_clears_the_pause
    Check.trip!(source: "council", message: CREDITS)
    assert Check.clear!
    refute Check.blocked?
    assert_equal :available, Check.state
    refute Check.clear!, "clearing an open check changes nothing"
  end

  # A council that quietly answers on a different model is not reviewing the
  # same way twice; the swap belongs in the record.
  def test_substitutions_are_recorded
    assert_nil Check.substitution_note
    Check.substituted(from: "openrouter/free", to: "claude-cli:sonnet")
    Check.substituted(from: "openrouter/free", to: "claude-cli:sonnet")

    assert_equal 1, Check.substitutions.size
    assert_match(/openrouter\/free -> claude-cli:sonnet/, Check.substitution_note)
  end

  # The other half of the defect: MASTER/law's 122 rules are all lexical, so
  # every semantic rule is a model call. With the check closed they return no
  # findings — and "no findings" is exactly what a clean file returns, which is
  # how a whole tier of detection disappears into a pass.
  def test_the_semantic_tier_refuses_to_read_as_clean
    asked = []
    agent = Class.new do
      define_method(:initialize) { |log| @log = log }
      define_method(:ask) { |prompt, **| @log << prompt; "CLEAN" }
    end.new(asked)

    rule = Master::Review::Scan::Laws::AdversarialLaw.new.set_agent(agent)
    assert_empty rule.check("def a = 1\n", path: "x.rb"), "a healthy call still returns findings-or-none"
    assert_equal 1, asked.size, "with credit, the rule asks"

    Check.trip!(source: "council", message: CREDITS)
    assert_empty rule.check("def b = 2\n", path: "y.rb")

    assert_equal 1, asked.size, "the second call was guaranteed to fail; it must not be spent"
    assert_includes Check.skipped_tiers, "semantic Laws",
                    "returning [] without naming the tier is what reads as a clean bill of health"
    assert_match(/SKIPPED semantic Laws/, Check.report)
  end

  # A rule that reaches the model and is told "no credit" trips the tier once,
  # not once per file — the same population that once logged 4,663 identical
  # entries for one absent capability.
  def test_a_rule_hitting_the_limit_trips_the_tier_once
    broke = Class.new do
      define_method(:ask) { |_prompt, **| raise(StandardError, CREDITS) }
    end.new
    rule = Master::Review::Scan::Laws::AdversarialLaw.new.set_agent(broke)

    error = assert_raises(RuntimeError) { rule.check("def a = 1\n", path: "x.rb") }

    assert_match(/semantic assessment INCONCLUSIVE/, error.message)
    assert Check.blocked?, "the first refusal closes the check for the whole tier"
    assert_equal :exhausted, Check.state
  end

  # STUDIO loads Io::ReplicateClient without the runtime that gives
  # FailureTaxonomy its laws.yml, and the check still has to answer there.
  def test_classification_survives_a_taxonomy_that_cannot_load
    Master::Ground::FailureTaxonomy.stub(:exhausted?, ->(_m) { raise "no laws.yml" }) do
      assert Check.exhaustion?(CREDITS)
      refute Check.exhaustion?("connection reset by peer")
    end
  end
end

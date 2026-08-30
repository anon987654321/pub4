# frozen_string_literal: true

require_relative "test_helper"
# Zeitwerk is told to ignore this file (data/autoload.yml), so the semantic
# tier only exists once something requires it — the same require every other
# test of these rules makes.
require "review/scan/rules/semantic_rules"

class TestQuotaGate < Minitest::Test
  Gate = Master::Ground::QuotaGate
  CREDITS = "Insufficient credits. Add more using https://openrouter.ai"

  def setup = Gate.reset!
  def teardown = Gate.reset!

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

  # Trip once, say so once. Four personas hitting the same empty balance is
  # one fact about the account, not four about the personas.
  def test_trips_once_and_only_the_first_caller_is_told_to_announce
    assert Gate.trip!(source: "council persona P0", message: CREDITS), "first trip announces"
    refute Gate.trip!(source: "council persona P1", message: CREDITS), "the rest stay quiet"
    refute Gate.trip!(source: "council persona P2", message: CREDITS)

    assert Gate.blocked?
    assert Gate.tripped?
    assert_equal :exhausted, Gate.state
  end

  # The report is the honest half: a run that skipped a whole tier must name
  # the tier, not fold it into a pass.
  def test_report_names_the_skipped_tier_and_the_cause
    assert_nil Gate.report, "a healthy run has nothing to report"

    Gate.trip!(source: "council persona P0", message: CREDITS, model: "openrouter/free")
    Gate.skipped("semantic rules")
    Gate.skipped("semantic rules")
    Gate.skipped("council")

    assert_equal ["semantic rules", "council"], Gate.skipped_tiers, "one fact per tier, not per file"
    report = Gate.report
    assert_match(/\ASKIPPED semantic rules, council/, report)
    assert_match(/spend limit/, report)
    assert_match(/openrouter\/free/, report)
    assert_match(/re-probing in \d+s/, report, "the reader needs to know it comes back")
    assert_equal :exhausted, Gate.status[:state]
    assert_equal 1, Gate.status[:confirmations], "recording a skipped tier is not another confirmation"
  end

  # Not a latch. The operator's reading is that these limits lift within
  # minutes, so a breaker that never re-probes turns a short outage into a
  # whole run of silently skipped work.
  def test_reprobes_on_the_shared_backoff_rather_than_latching
    Gate.trip!(source: "council", message: CREDITS)
    assert Gate.blocked?
    assert_equal Master::Ground::FailureTaxonomy.backoff_seconds(0), Gate.seconds_until_probe,
                 "the wait is the taxonomy's backoff, not a second formula"

    Gate.reset!
    Master::Ground::FailureTaxonomy.stub(:backoff_seconds, 0) do
      Gate.trip!(source: "council", message: CREDITS)
      refute Gate.blocked?, "once the backoff elapses the next call goes through"
    end
    assert Gate.tripped?, "the run still remembers that a tier was hit"
  end

  # Confirmed again means wait longer, so a limit that is genuinely down for
  # an hour is not probed every second.
  def test_each_confirmation_widens_the_wait
    Gate.trip!(source: "council", message: CREDITS)
    first = Gate.seconds_until_probe
    Gate.trip!(source: "council", message: CREDITS)
    assert_operator Gate.seconds_until_probe, :>, first
  end

  # The third state. A revoked key is not a balance that refills.
  def test_a_refused_key_stops_instead_of_reprobing
    Gate.trip!(source: "agent single-shot", message: "401 Unauthorized: invalid api key")

    assert_equal :refused, Gate.state
    assert Gate.blocked?
    assert_nil Gate.seconds_until_probe, "nothing is being waited for"
    assert_match(/refused the key/, Gate.report)
    assert_match(/needs a human/, Gate.report)
  end

  # A paid call that came back is the only evidence the limit lifted.
  def test_a_successful_call_clears_the_pause
    Gate.trip!(source: "council", message: CREDITS)
    assert Gate.clear!
    refute Gate.blocked?
    assert_equal :available, Gate.state
    refute Gate.clear!, "clearing an open gate changes nothing"
  end

  # A council that quietly answers on a different model is not reviewing the
  # same way twice; the swap belongs in the record.
  def test_substitutions_are_recorded
    assert_nil Gate.substitution_note
    Gate.substituted(from: "openrouter/free", to: "claude-cli:sonnet")
    Gate.substituted(from: "openrouter/free", to: "claude-cli:sonnet")

    assert_equal 1, Gate.substitutions.size
    assert_match(/openrouter\/free -> claude-cli:sonnet/, Gate.substitution_note)
  end

  # The other half of the defect: MASTER/law's 122 rules are all lexical, so
  # every semantic rule is a model call. With the gate closed they return no
  # findings — and "no findings" is exactly what a clean file returns, which is
  # how a whole tier of detection disappears into a pass.
  def test_the_semantic_tier_refuses_to_read_as_clean
    asked = []
    agent = Class.new do
      define_method(:initialize) { |log| @log = log }
      define_method(:ask) { |prompt, **| @log << prompt; "CLEAN" }
    end.new(asked)

    rule = Master::Review::Scan::Rules::AdversarialRule.new.set_agent(agent)
    assert_empty rule.check("def a = 1\n", path: "x.rb"), "a healthy call still returns findings-or-none"
    assert_equal 1, asked.size, "with credit, the rule asks"

    Gate.trip!(source: "council", message: CREDITS)
    assert_empty rule.check("def b = 2\n", path: "y.rb")

    assert_equal 1, asked.size, "the second call was guaranteed to fail; it must not be spent"
    assert_includes Gate.skipped_tiers, "semantic rules",
                    "returning [] without naming the tier is what reads as a clean bill of health"
    assert_match(/SKIPPED semantic rules/, Gate.report)
  end

  # A rule that reaches the model and is told "no credit" trips the tier once,
  # not once per file — the same population that once logged 4,663 identical
  # entries for one absent capability.
  def test_a_rule_hitting_the_limit_trips_the_tier_once
    broke = Class.new do
      define_method(:ask) { |_prompt, **| raise(StandardError, CREDITS) }
    end.new
    rule = Master::Review::Scan::Rules::AdversarialRule.new.set_agent(broke)

    assert_empty rule.check("def a = 1\n", path: "x.rb")
    assert Gate.blocked?, "the first refusal closes the gate for the whole tier"
    assert_equal :exhausted, Gate.state
  end

  # STUDIO loads Io::ReplicateClient without the runtime that gives
  # FailureTaxonomy its rules.yml, and the gate still has to answer there.
  def test_classification_survives_a_taxonomy_that_cannot_load
    Master::Ground::FailureTaxonomy.stub(:exhausted?, ->(_m) { raise "no rules.yml" }) do
      assert Gate.exhaustion?(CREDITS)
      refute Gate.exhaustion?("connection reset by peer")
    end
  end
end

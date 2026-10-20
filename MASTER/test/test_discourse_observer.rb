# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestDiscourseObserver < Minitest::Test
  Observer = Master::Cognition::DiscourseObserver

  def setup
    @dir = Dir.mktmpdir("discourse")
    @audit = File.join(@dir, "audit", "discourse.jsonl")
    @observer = Observer.new(audit_path: @audit)
  end

  def teardown = FileUtils.remove_entry(@dir)

  def test_a_catalogued_phrase_is_pointed_at_with_its_exact_span
    found = @observer.observe("Sam: That never happened, you're imagining things.\n")

    assert_equal %w[denial_of_event reality_questioning], found.map(&:rule).sort
    denial = found.find { |o| o.rule == "denial_of_event" }
    assert_equal "Sam", denial.speaker
    assert_equal "That never happened", denial.span
    assert_equal 1, denial.line
  end

  def test_every_observation_names_other_explanations_and_a_limit_and_disclaims_intent
    found = @observer.observe("everyone thinks you are wrong")

    assert_equal 1, found.size
    assert_operator found.first.alternatives.size, :>=, 1
    refute_empty found.first.limit
    assert_includes found.first.statement, "not a statement about intent or character"
  end

  def test_wording_alone_never_reaches_certainty
    found = @observer.observe("last chance, last chance, you must decide now, after all I've done")

    assert_operator found.size, :>=, 3
    found.each { |o| assert_operator o.confidence, :<=, 0.6 }
  end

  def test_a_quotation_or_hedge_lowers_confidence_and_is_reported
    plain = @observer.observe("you're imagining things").first
    quoted = @observer.observe("she said you're imagining things, for example").first

    assert_operator quoted.confidence, :<, plain.confidence
    assert_includes quoted.counter_evidence, "she said"
  end

  def test_no_catalogued_wording_is_an_empty_list_not_a_clean_bill
    assert_empty @observer.observe("Shall we meet at six? The weather is fine.")
  end

  def test_every_call_is_appended_to_the_audit_trail_with_the_span_and_rule
    @observer.observe("that never happened")
    @observer.observe("nothing to see")
    rows = File.readlines(@audit).map { |line| JSON.parse(line) }

    assert_equal 2, rows.size
    assert_equal "denial_of_event", rows.first.fetch("observations").first.fetch("rule")
    assert_equal 1, rows.first.fetch("catalogue")
    assert_empty rows.last.fetch("observations")
  end

  def test_the_catalogue_carries_an_alternative_and_a_limit_for_every_pattern
    catalogue = Master.load_yaml(Observer::CATALOGUE)

    catalogue.fetch("markers").each do |rule, markers|
      refute_empty markers, rule
      refute_empty catalogue.fetch("alternatives").fetch(rule), rule
      refute_empty catalogue.fetch("limit").fetch(rule), rule
    end
  end
end

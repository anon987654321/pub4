# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "master"

# The evidence weights live in exactly one Ruby place — Proof::SCORING — and the
# lib spine still reads data/rules.yml's evidence_scoring. Until that spine is
# severed the two must agree, or the agent is told one threshold and judged by
# another. This test is the seam that keeps them honest.
class EvidencePolicyTest < Minitest::Test
  DATA = YAML.safe_load_file(
    File.expand_path("../../data/rules.yml", __dir__), aliases: true
  ).fetch("evidence_scoring")

  def test_weights_match_rules_yaml
    yaml_weights = DATA.fetch("weights").transform_keys(&:to_sym)
    assert_equal Master::Core::Proof::SCORING, yaml_weights
  end

  def test_pass_threshold_matches_rules_yaml
    assert_equal DATA.fetch("pass_threshold"), Master::Core::Proof::PASS_THRESHOLD
  end

  # Same seam as the weights: Ruby is the source, YAML mirrors it, and a
  # disagreement means the agent is judged by one policy and told another.
  def test_producers_match_rules_yaml
    yaml = DATA.fetch("producers").transform_keys(&:to_sym).transform_values { |p| Regexp.new(p) }
    ruby = Master::Core::Proof::PRODUCERS.transform_values { |r| Regexp.new(r.source.sub(/\A\\b\(\?:/, "").sub(/\)\z/, "")) }

    assert_equal ruby.keys.sort, yaml.keys.sort
    ruby.each_key { |kind| assert_equal ruby[kind].source, yaml[kind].source, "producer for #{kind} drifted" }
  end

  # Every kind that scores must have a producer, or its weight is unreachable.
  def test_every_scored_kind_has_a_producer
    assert_equal Master::Core::Proof::SCORING.keys.sort, Master::Core::Proof::PRODUCERS.keys.sort
  end

  def test_model_prompt_is_built_from_the_policy_not_restated
    prompt = Master::Core::Model::SYSTEM
    assert_includes prompt, "threshold #{Master::Core::Proof::PASS_THRESHOLD}"
    Master::Core::Proof::SCORING.each do |kind, weight|
      assert_includes prompt, "#{kind}=#{weight}"
    end
  end

  E = Master::Core::Effect
  OK = Master::Core::Observation.ok("ok")

  # A command that can actually produce each kind. These fixtures used to run
  # ["true"] for all of them, which is the forgery PRODUCERS now closes — the
  # suite was demonstrating the hole while pinning the policy around it.
  PRODUCER_ARGV = {
    test_pass: %w[bundle exec rake test],
    scan_clean: %w[bin/check],
    code_review: %w[bin/review],
    log_analysis: %w[rcctl check brgen],
    profiling_data: %w[stackprof tmp/profile.dump],
  }.freeze

  def proof_with(*kinds)
    proof = Master::Core::Proof.new(risk: :low)
    kinds.each { |kind| proof.record_evidence(E.exec(PRODUCER_ARGV.fetch(kind), evidence: kind), OK) }
    proof
  end

  # The forgery itself, pinned so it cannot come back. `true` deliberately stays
  # literal here — this is the one place in the suite that should use it.
  def test_a_command_that_proves_nothing_scores_nothing
    proof = Master::Core::Proof.new(risk: :low)
    %i[test_pass scan_clean code_review].each do |kind|
      proof.record_evidence(E.exec(%w[true], evidence: kind), OK)
    end

    refute proof.proved?, "exec(['true']) laundered into a passing proof"
    assert_equal 0, proof.send(:evidence_score)
  end

  # Every kind needs at least one command that earns it, or the label is
  # unreachable and the weight beside it is decoration.
  def test_every_scored_kind_has_a_command_that_earns_it
    Master::Core::Proof::SCORING.each_key do |kind|
      proof = Master::Core::Proof.new(risk: :low)
      proof.record_evidence(E.exec(PRODUCER_ARGV.fetch(kind), evidence: kind), OK)
      refute_equal 0, proof.send(:evidence_score), "nothing can earn #{kind}"
    end
  end

  # Three distinct kinds is what the threshold is designed to want.
  def test_three_distinct_kinds_reach_the_threshold
    assert proof_with(:test_pass, :scan_clean, :code_review).proved?
  end

  # Repetition is not independence. Nothing deduplicated, so the same tag three
  # times was 105 points out of one kind of proof.
  def test_repeating_one_kind_does_not_stack
    proof = proof_with(:test_pass, :test_pass, :test_pass)
    refute proof.proved?, "three of the same evidence kind reached the threshold"
  end

  # Evidence proves something about the tree it was earned against. A write after
  # it makes it a claim about a tree that no longer exists, so `done` must not be
  # reachable on the strength of a run that predates the change.
  def test_a_write_invalidates_evidence_earned_before_it
    proof = proof_with(:test_pass, :scan_clean, :code_review)
    assert proof.proved?, "precondition: the fold had proved itself"

    proof.record_evidence(E.write("MASTER/lib/thing.rb", "CHANGED = 1\n"), OK)

    refute proof.proved?, "evidence survived a write to the code it was proving"
  end

  # And it can be re-earned: the fold tests again after the change and is proved
  # once more. Staleness must not be a dead end.
  def test_evidence_re_earned_after_a_write_counts_again
    proof = proof_with(:test_pass, :scan_clean, :code_review)
    proof.record_evidence(E.write("MASTER/lib/thing.rb", "CHANGED = 1\n"), OK)
    refute proof.proved?

    %i[test_pass scan_clean code_review].each do |kind|
      proof.record_evidence(E.exec(PRODUCER_ARGV.fetch(kind), evidence: kind), OK)
    end
    assert proof.proved?, "a fold that re-proves its work after a change is stuck"
  end
end

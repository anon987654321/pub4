# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "json"
require "open3"
require "tmpdir"
require_relative "../lib/cognition/outcome_model"
require_relative "../lib/cognition/benchmark"

class TestCognitionOutcomeModel < Minitest::Test
  def model = Master::Cognition::OutcomeModel.new

  def evidence(source, body = source)
    { source:, content: body, sha256: Digest::SHA256.hexdigest(body) }
  end

  def test_unknown_actions_start_uncertain_and_do_not_claim_learned_confidence
    prediction = model.predict({ "records" => {} }, context: "Rails test", action: "run tests")

    assert_equal :unknown, prediction[:prediction]
    assert_equal :insufficient_data, prediction[:status]
    assert_equal 0.5, prediction[:success_probability]
    assert_equal 0.0, prediction[:confidence]
  end

  def test_predictions_learn_only_from_explicit_task_outcomes
    state = { "records" => {} }
    6.times do |index|
      model.observe!(state, context: "rails app", action: "run contract tests",
                     outcome: "success", evidence: evidence("test:#{index}", "output-#{index}"))
    end

    prediction = model.predict(state, context: "rails app", action: "run contract tests")
    assert_equal :learned, prediction[:status]
    assert_equal 6, prediction[:successes]
    assert_operator prediction[:success_probability], :>, 0.8
  end

  def test_a_receipt_is_counted_once_and_cannot_be_relabelled
    state = { "records" => {} }
    receipt = evidence("test:receipt", "same output")
    2.times do
      model.observe!(state, context: "task", action: "verify",
                     outcome: "success", evidence: receipt)
    end
    assert_equal 1, model.predict(state, context: "task", action: "verify")[:successes]

    assert_raises(ArgumentError) do
      model.observe!(state, context: "task", action: "verify",
                     outcome: "failure", evidence: receipt)
    end
    assert_equal 1, model.predict(state, context: "task", action: "verify")[:successes]
  end

  def test_inconclusive_observations_do_not_change_success_probability
    state = { "records" => {} }
    3.times do |index|
      model.observe!(state, context: "deploy", action: "probe",
                     outcome: "inconclusive", evidence: evidence("probe:#{index}"))
    end

    prediction = model.predict(state, context: "deploy", action: "probe")
    assert_equal 0, prediction[:samples]
    assert_equal 3, prediction[:inconclusive]
    assert_equal 0.5, prediction[:success_probability]
  end

  def test_receipts_reject_content_digest_mismatches
    assert_raises(ArgumentError) do
      model.observe!({ "records" => {} }, context: "task", action: "verify",
                     outcome: "success", evidence: { source: "test:source", content: "different",
                                                      sha256: Digest::SHA256.hexdigest("original") })
    end
  end

  def test_inline_evidence_requires_a_well_formed_matching_digest
    assert_raises(ArgumentError) do
      model.observe!({ "records" => {} }, context: "task", action: "verify",
                     outcome: "success", evidence: { source: "test:empty", content: "body", sha256: "" })
    end
  end

  def test_inline_evidence_has_a_bounded_size
    oversized = "x" * (Master::Cognition::OutcomeModel::MAX_EVIDENCE_BYTES + 1)
    assert_raises(ArgumentError) do
      model.observe!({ "records" => {} }, context: "task", action: "verify",
                     outcome: "success", evidence: evidence("test:oversized", oversized))
    end
  end

  def test_records_require_a_source_and_a_valid_sha256
    assert_raises(ArgumentError) do
      model.observe!({ "records" => {} }, context: "task", action: "verify",
                     outcome: "success", evidence: { source: "test", sha256: "not-a-digest" })
    end
  end

  def test_benchmark_verifies_root_confined_file_receipts
    Dir.mktmpdir("cognition-evidence") do |root|
      body = "real task outcome output"
      path = File.join(root, "outcome.log")
      File.write(path, body)
      receipt = { source: "outcome.log", sha256: Digest::SHA256.file(path).hexdigest }
      rows = [{
        context: "file-backed benchmark",
        action: "verify output",
        outcome: "success",
        evidence: receipt,
      }]

      report = Master::Cognition::Benchmark.evaluate(rows, root:)
      assert_equal 1, report.fetch("scored_outcomes")

      rows.first[:evidence] = receipt.merge(sha256: "0" * 64)
      assert_raises(ArgumentError) { Master::Cognition::Benchmark.evaluate(rows, root:) }
    end
  end

  def test_benchmark_rejects_unverifiable_reference_only_evidence
    rows = [{
      context: "task", action: "verify", outcome: "success",
      evidence: { source: "outcome.log", sha256: "a" * 64 }
    }]
    assert_raises(ArgumentError) { Master::Cognition::Benchmark.evaluate(rows) }
  end

  def test_no_learning_ablation_stays_at_the_prior
    rows = 8.times.map do |index|
      { context: "repeatable task", action: "run verifier",
        outcome: index.even? ? "success" : "failure",
        evidence: evidence("fixture:#{index}", "outcome-#{index}") }
    end

    report = Master::Cognition::Benchmark.evaluate(rows, learn: false)
    assert_equal "ablation_no_learning", report.fetch("mode")
    assert_equal 0.25, report.fetch("learned_brier_score")
    assert_equal 0.0, report.fetch("prediction_coverage")
    assert_equal [0], report.fetch("rows").map { |row| row.fetch("prior_samples") }.uniq
  end

  def test_predictions_are_scored_before_their_outcomes_are_learned
    rows = 10.times.map do |index|
      { context: "repeatable task", action: "run verifier",
        outcome: "success", evidence: evidence("fixture:#{index}", "success-#{index}") }
    end

    report = Master::Cognition::Benchmark.evaluate(rows)
    assert_equal 10, report.fetch("scored_outcomes")
    assert_operator report.fetch("brier_improvement"), :>, 0
    assert_equal 0, report.fetch("rows").first.fetch("prior_samples")
    assert_equal 9, report.fetch("rows").last.fetch("prior_samples")
  end

  def test_the_benchmark_tool_reports_the_ablation_from_a_jsonl_file
    Dir.mktmpdir("cognition-tool") do |dir|
      rows = 6.times.map do |index|
        body = "outcome-#{index}"
        { context: "task", action: "verify", outcome: "success",
          evidence: { source: "fixture:#{index}", content: body, sha256: Digest::SHA256.hexdigest(body) } }
      end
      path = File.join(dir, "outcomes.jsonl")
      File.write(path, rows.map { |row| JSON.generate(row) }.join("\n"))
      tool = File.expand_path("../tools/research/cognition_benchmark.rb", __dir__)

      out, status = Open3.capture2(RbConfig.ruby, tool, "--no-learning", path)

      assert status.success?
      assert_equal "ablation_no_learning", JSON.parse(out).fetch("mode")
    end
  end

  def test_learned_records_are_bounded_and_the_oldest_are_dropped
    state = { "records" => {} }
    limit = Master::Cognition::OutcomeModel::MAX_RECORDS
    (limit + 3).times do |index|
      model.observe!(state, context: "ctx", action: "action-#{index}",
                     outcome: "success", evidence: evidence("test:#{index}", "body-#{index}"))
    end

    assert_equal limit, state.fetch("records").size
    assert_equal :insufficient_data, model.predict(state, context: "ctx", action: "action-0")[:status]
    assert_equal 1, model.predict(state, context: "ctx", action: "action-#{limit + 2}")[:successes]
  end
end

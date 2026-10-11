# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "tmpdir"

class TestCognitionFeedback < Minitest::Test
  def setup
    @root = Dir.mktmpdir("master-cognition-feedback")
    @mind = Master::Cognition::Mind.new(root: @root, bus: nil)
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def evidence(source, body = source)
    { source:, content: body, sha256: Digest::SHA256.hexdigest(body) }
  end

  def test_verified_task_result_updates_prediction_and_self_calibration
    6.times do |index|
      @mind.record_task_result(
        context: "ruby source edit",
        action: "run focused tests",
        outcome: "success",
        task_type: "ruby_repair",
        confidence: 0.8,
        predicted_probability: 0.8,
        evidence: evidence("test:#{index}", "result-#{index}"),
      )
    end

    prediction = @mind.predict_outcome(context: "ruby source edit", action: "run focused tests")
    report = @mind.capability_report.fetch("ruby_repair")

    assert_equal :learned, prediction[:status]
    assert_equal 6, report.fetch(:samples)
    assert_equal 6, report.fetch(:successes)
    assert_in_delta 0.8, report.fetch(:mean_confidence), 0.001
    assert_operator report.fetch(:brier_score), :<, 0.1
  end

  def test_unverified_results_do_not_enter_cognitive_memory
    assert_raises(ArgumentError) do
      @mind.record_task_result(context: "task", action: "act", outcome: "success",
                               task_type: "task", evidence: { source: "run", sha256: "bad" })
    end

    assert_equal :unknown, @mind.predict_outcome(context: "task", action: "act")[:prediction]
  end

  def test_inconclusive_results_are_not_counted_as_task_successes_or_failures
    @mind.record_task_result(context: "deploy", action: "probe", outcome: "inconclusive",
                             task_type: "deploy", evidence: evidence("probe"))
    assert_empty @mind.capability_report
    assert_equal 0, @mind.predict_outcome(context: "deploy", action: "probe")[:samples]
    assert_equal 1, @mind.predict_outcome(context: "deploy", action: "probe")[:inconclusive]
  end

  def test_fix_terminal_teaches_only_from_a_matching_durable_receipt
    require "json"
    path = File.join(@root, ".master", "receipts", "convergence-test.json")
    FileUtils.mkdir_p(File.dirname(path))
    body = JSON.generate({
      "command" => "/fix",
      "state" => "done",
      "details" => { "run_id" => "run-1", "target" => "MASTER" },
    })
    File.write(path, body)
    digest = Digest::SHA256.hexdigest(body)
    payload = {
      state: "done",
      run_id: "run-1",
      outcome_receipt: { source: ".master/receipts/convergence-test.json", sha256: digest },
    }

    @mind.send(:capture_fix_outcome, payload)
    assert_equal 1, @mind.predict_outcome(context: "target=MASTER", action: "/fix")[:successes]

    payload[:outcome_receipt][:sha256] = "0" * 64
    payload[:run_id] = "run-2"
    @mind.send(:capture_fix_outcome, payload)
    assert_equal 1, @mind.predict_outcome(context: "target=MASTER", action: "/fix")[:successes]
  end

  def test_malformed_outcome_state_is_not_accepted_as_a_valid_checkpoint
    path = File.join(@root, Master::Cognition::Mind::STATE_PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, {
      "ticks" => 3,
      "identity" => { "name" => "MASTER" },
      "predictions" => { "transitions" => {} },
      "outcomes" => "corrupted",
    }.to_yaml)

    loaded = Master::Cognition::State.load(path)
    refute loaded.checkpoint_valid
    assert_kind_of Hash, loaded.outcomes
    assert_equal 0.0, loaded.metrics.fetch("continuity")
  end

  def test_checkpoint_continuity_is_not_a_monotonic_mood_proxy
    assert_equal 0.0, @mind.snapshot.dig("metrics", "continuity")

    @mind.tick!
    saved = Master::Cognition::State.load(File.join(@root, Master::Cognition::Mind::STATE_PATH))
    assert saved.checkpoint_valid
    assert_equal 1.0, saved.metrics.fetch("checkpoint_continuity")
  end
end

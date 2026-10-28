# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "json"
require "tmpdir"

# Verified task outcomes train Mind's outcome model, and /fix's terminal event
# trains it only through a durable receipt whose bytes and run agree.
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

  def test_verified_task_results_update_the_prediction
    6.times do |index|
      @mind.record_task_result(context: "ruby source edit", action: "run focused tests", outcome: "success",
                               predicted_probability: 0.8, evidence: evidence("test:#{index}", "result-#{index}"))
    end

    prediction = @mind.predict_outcome(context: "ruby source edit", action: "run focused tests")
    assert_equal :learned, prediction[:status]
    assert_equal 6, prediction[:successes]
    assert_operator prediction[:brier_score], :<, 0.1
  end

  def test_unverified_results_do_not_enter_cognitive_memory
    assert_raises(ArgumentError) do
      @mind.record_task_result(context: "task", action: "act", outcome: "success",
                               evidence: { source: "run", sha256: "bad" })
    end

    assert_equal :unknown, @mind.predict_outcome(context: "task", action: "act")[:prediction]
  end

  def test_inconclusive_results_are_not_counted_as_successes_or_failures
    @mind.record_task_result(context: "deploy", action: "probe", outcome: "inconclusive", evidence: evidence("probe"))
    prediction = @mind.predict_outcome(context: "deploy", action: "probe")

    assert_equal 0, prediction[:samples]
    assert_equal 1, prediction[:inconclusive]
  end

  def test_recorded_outcomes_survive_a_restart
    @mind.record_task_result(context: "deploy", action: "probe", outcome: "success", evidence: evidence("probe"))
    again = Master::Cognition::Mind.new(root: @root, bus: nil)

    assert_equal 1, again.predict_outcome(context: "deploy", action: "probe")[:successes]
  end

  def test_fix_terminal_teaches_only_from_a_matching_durable_receipt
    payload = fix_payload(state: "done", run_id: "run-1", target: "MASTER", prior: 0.3)

    @mind.send(:capture_fix_outcome, payload)
    learned = @mind.predict_outcome(context: "target=MASTER", action: "/fix")
    assert_equal 1, learned[:successes]
    assert_in_delta 0.49, learned[:brier_score], 0.001

    @mind.send(:capture_fix_outcome, payload)
    assert_equal 1, @mind.predict_outcome(context: "target=MASTER", action: "/fix")[:successes], "a replayed receipt counts once"

    forged = payload.merge(run_id: "run-2", outcome_receipt: payload[:outcome_receipt].merge(sha256: "0" * 64))
    @mind.send(:capture_fix_outcome, forged)
    assert_equal 1, @mind.predict_outcome(context: "target=MASTER", action: "/fix")[:successes]
  end

  def test_a_receipt_for_another_run_or_state_teaches_nothing
    payload = fix_payload(state: "done", run_id: "run-1", target: "MASTER")

    @mind.send(:capture_fix_outcome, payload.merge(run_id: "other"))
    @mind.send(:capture_fix_outcome, payload.merge(state: "failed"))
    @mind.send(:capture_fix_outcome, payload.merge(target: "RAILS"))

    assert_equal 0, @mind.predict_outcome(context: "target=MASTER", action: "/fix")[:samples]
  end

  def test_a_failed_terminal_counts_as_a_failure
    @mind.send(:capture_fix_outcome, fix_payload(state: "timeout", run_id: "run-3", target: "RAILS"))

    assert_equal 1, @mind.predict_outcome(context: "target=RAILS", action: "/fix")[:failures]
  end

  def test_the_terminal_event_on_the_bus_reaches_the_model
    bus = Master::Trace::EventBus.new(event_log: Object.new.tap { |log| log.define_singleton_method(:append) { |*| nil } })
    mind = Master::Cognition::Mind.new(root: @root, bus:)
    bus.publish("fix_loop:terminal", **fix_payload(state: "done", run_id: "run-4", target: "STUDIO"))

    assert_equal 1, mind.predict_outcome(context: "target=STUDIO", action: "/fix")[:successes]
  end

  def test_outcome_checkpoint_rejects_unbounded_receipt_history
    path = File.join(@root, Master::Cognition::Mind::STATE_PATH)
    FileUtils.mkdir_p(File.dirname(path))
    receipts = Array.new(65) do |index|
      { "source" => "receipt:#{index}", "sha256" => "a" * 64, "outcome" => "success" }
    end
    record = {
      "context" => "task", "action" => "/fix",
      "successes" => 1, "failures" => 0, "inconclusive" => 0,
      "brier_sum" => 0.0, "brier_count" => 0,
      "observations" => [], "seen_receipts" => receipts
    }
    File.write(path, {
      "ticks" => 3,
      "identity" => { "name" => "MASTER" },
      "predictions" => { "transitions" => {} },
      "outcomes" => { "records" => { "a" * 24 => record } },
    }.to_yaml)

    loaded = Master::Cognition::State.load(path)
    assert_equal "invalid", loaded.load_status
    assert_empty loaded.outcomes.fetch("records")
  end

  def test_malformed_outcome_state_is_not_accepted
    path = File.join(@root, Master::Cognition::Mind::STATE_PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, { "ticks" => 3, "outcomes" => { "records" => { "bad" => "not a record" } } }.to_yaml)

    loaded = Master::Cognition::State.load(path)
    assert_equal "invalid", loaded.load_status
    assert_empty loaded.outcomes.fetch("records")
  end

  private

  def fix_payload(state:, run_id:, target:, prior: nil)
    path = File.join(@root, ".master", "receipts", "convergence-#{run_id}.json")
    FileUtils.mkdir_p(File.dirname(path))
    details = { "run_id" => run_id, "target" => target }
    details["outcome_prior"] = { "context" => "target=#{target}", "action" => "/fix", "success_probability" => prior } if prior
    body = JSON.generate("command" => "/fix", "state" => state, "details" => details)
    File.write(path, body)
    { state:, run_id:, target:,
      outcome_receipt: { source: ".master/receipts/convergence-#{run_id}.json", sha256: Digest::SHA256.hexdigest(body) } }
  end
end

# frozen_string_literal: true

require_relative "test_helper"
require "timeout"
require_relative "../lib/fix/kernel/repair_adapter"

# The fix candidates were made concurrent on 2026-11-05 by a patch nobody ran. Its threads started with no
# thread-locals, where the repair keeps the refusal note a retry must show and the model it is pinned to.
class TestCandidateThreads < Minitest::Test
  Ledger = Master::Fix::RunLedger
  Pin = Master::Review::LLMDispatcher::ModelPin

  def repair
    Master::Fix::RepairLoop.allocate.tap { |loop| loop.instance_variable_set(:@law, Struct.new(:id).new("LAW")) }
  end

  def test_each_candidate_sees_the_retry_note_and_the_model_pin
    rows = Ledger.retrying("the diff touched line 900") do
      Pin.with("claude-cli:claude-opus-5-5") do
        repair.send(:candidate_threads, 3, violation: {}, event: "test") { |_index| [Ledger.retry_note, Pin.current] }
      end
    end

    assert_equal 3, rows.size
    rows.each do |note, pin|
      assert_includes note, "the diff touched line 900"
      assert_equal "claude-cli:claude-opus-5-5", pin
    end
  end

  # The file budget ends a repair with Timeout; a candidate still asking its model must not outlive it.
  def test_a_candidate_still_running_when_the_caller_gives_up_is_killed
    started = Queue.new
    workers = []

    assert_raises(Timeout::Error) do
      Timeout.timeout(0.5) do
        repair.send(:candidate_threads, 2, violation: {}, event: "test") do |_index|
          workers << Thread.current
          started << true
          sleep 30
        end
      end
    end

    2.times { started.pop(timeout: 2) }
    workers.each { |thread| thread.join(2) }
    refute workers.any?(&:alive?), "a candidate thread outlived the caller"
  end
end

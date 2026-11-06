# frozen_string_literal: true

require "test_helper"

# ApplicationJob used to carry `retry_on StandardError`, so every exception a
# job could raise — including a plain bug — was retried three times with
# backoff. brgen runs a real Solid Queue worker, so that was three delayed
# copies of the same failure in production rather than one.
class ApplicationJobRetryPolicyTest < ActiveJob::TestCase
  class ProgrammingErrorJob < ApplicationJob
    def perform = raise(ArgumentError, "a bug, not a blip")
  end

  class DeadlockedJob < ApplicationJob
    def perform = raise(ActiveRecord::Deadlocked, "lock contention")
  end

  class VanishedRecordJob < ApplicationJob
    def perform
      raise ActiveRecord::RecordNotFound
    rescue ActiveRecord::RecordNotFound
      raise ActiveJob::DeserializationError
    end
  end

  test "a programming error is not retried" do
    assert_no_enqueued_jobs do
      assert_raises(ArgumentError) { ProgrammingErrorJob.perform_now }
    end
  end

  test "a deadlock is retried" do
    assert_enqueued_with(job: DeadlockedJob) { DeadlockedJob.perform_now }
  end

  test "a job whose record is gone is discarded rather than retried" do
    assert_no_enqueued_jobs do
      assert_nothing_raised { VanishedRecordJob.perform_now }
    end
  end
end

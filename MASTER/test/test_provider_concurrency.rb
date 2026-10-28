# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/io/provider_concurrency"
require "thread"

class TestProviderConcurrency < Minitest::Test
  Gate = Master::Io::ProviderConcurrency

  def test_shared_bucket_never_exceeds_its_configured_concurrency
    inside = 0
    maximum = 0
    lock = Mutex.new
    threads = 2.times.map do
      Thread.new do
        Gate.with_slot(bucket: "test-shared-provider", limit: 1, wait_seconds: 1) do
          lock.synchronize do
            inside += 1
            maximum = [maximum, inside].max
          end
          sleep 0.03
          lock.synchronize { inside -= 1 }
        end
      end
    end
    threads.each(&:value)

    assert_equal 1, maximum
    assert_equal 0, inside
  end

  def test_saturated_bucket_returns_control_for_fallback
    entered = Queue.new
    release = Queue.new
    first = Thread.new do
      Gate.with_slot(bucket: "test-saturation", limit: 1, wait_seconds: 1) do
        entered << true
        release.pop
      end
    end
    entered.pop

    error = assert_raises(Gate::Saturated) do
      Gate.with_slot(bucket: "test-saturation", limit: 1, wait_seconds: 0) { flunk "must not enter" }
    end
    assert_match(/queue is full/, error.message)
  ensure
    release << true if release
    first&.join
  end

  def test_a_shared_bucket_cannot_be_configured_with_conflicting_limits
    Gate.with_slot(bucket: "test-conflict", limit: 2) { :ok }

    error = assert_raises(ArgumentError) do
      Gate.with_slot(bucket: "test-conflict", limit: 1) { flunk "must reject conflicting configuration" }
    end
    assert_match(/conflicting concurrency limits/, error.message)
  end

  def test_invalid_bucket_and_limit_fail_closed
    assert_raises(ArgumentError) do
      Gate.with_slot(bucket: "", limit: 1) { flunk "empty bucket must be rejected" }
    end
    assert_raises(ArgumentError) do
      Gate.with_slot(bucket: "test-invalid", limit: 0) { flunk "zero limit must be rejected" }
    end
  end
end

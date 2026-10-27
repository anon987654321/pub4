# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/trace/mutation_observer"

class TestMutationObserver < Minitest::Test
  class RecordingBus
    attr_reader :events
    attr_accessor :failure

    def initialize
      @events = []
    end

    def publish_required(event, payload = {})
      raise IOError, "simulated audit failure" if event == failure

      @events << [event, payload]
      self
    end
  end

  def build(bus)
    Master::Trace::MutationObserver.new(
      root: Dir.pwd, namespace: "test:mutation_lifecycle",
      subject_type: "test", subject_id: "sample", bus:
    )
  end

  def test_mutation_has_durable_before_after_pair_with_shared_id
    bus = RecordingBus.new
    observer = build(bus)

    result = observer.mutate(operation: "write", item_count: 2) { :done }

    assert_equal :done, result
    assert_equal %w[test:mutation_lifecycle:before test:mutation_lifecycle:after], bus.events.map(&:first)
    before_payload = bus.events.first.last
    after_payload = bus.events.last.last
    assert_equal before_payload.fetch(:audit_id), after_payload.fetch(:audit_id)
    assert_equal "write", before_payload.fetch(:operation)
    assert_equal "ok", after_payload.fetch(:status)
    assert_equal 2, after_payload.fetch(:item_count)
    assert_operator after_payload.fetch(:elapsed_ms), :>=, 0
  end

  def test_before_persistence_failure_prevents_mutation
    bus = RecordingBus.new
    bus.failure = "test:mutation_lifecycle:before"
    observer = build(bus)
    called = false

    assert_raises(IOError) do
      observer.mutate(operation: "write") { called = true }
    end

    refute called
    assert observer.failed?
    assert_empty bus.events
  end

  def test_after_persistence_failure_is_not_retried
    bus = RecordingBus.new
    bus.failure = "test:mutation_lifecycle:after"
    observer = build(bus)
    calls = 0

    assert_raises(IOError) do
      observer.mutate(operation: "push") do
        calls += 1
        :published
      end
    end

    assert_equal 1, calls
    assert observer.failed?
    assert_equal ["test:mutation_lifecycle:before"], bus.events.map(&:first)
  end

  def test_tuple_with_failed_process_status_is_recorded_as_failed
    bus = RecordingBus.new
    observer = build(bus)
    status = Object.new
    status.define_singleton_method(:success?) { false }

    observer.mutate(operation: "fetch") { ["remote rejected", status] }

    assert_equal "failed", bus.events.last.last.fetch(:status)
  end
end

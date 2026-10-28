# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/trace/object_probe"

module ObjectProbeFixtures
  module Wrapper
    def perform(value = :wrapped)
      super
    end
  end

  class Parent
    def perform(value = :parent)
      value
    end
  end

  class Child < Parent
    prepend Wrapper

    def perform(value = :child)
      super
    end
  end

  class Worker
    def call(value)
      helper(value)
    end

    def helper(value)
      value
    end

    def boom
      raise ArgumentError, "sensitive exception message"
    end
  end
end

class TestObjectProbe < Minitest::Test
  Probe = Master::Trace::ObjectProbe

  def test_records_message_flow_for_selected_object_identity_only
    selected = ObjectProbeFixtures::Worker.new
    other = ObjectProbeFixtures::Worker.new
    probe = Probe.new(receivers: [selected], methods: %i[call helper])

    result = nil
    probe.capture do
      result = selected.call("sensitive argument")
      other.call("not observed")
    end

    assert_equal "sensitive argument", result
    calls = probe.events.select { |event| event.event == :call }
    assert_equal %i[call helper], calls.map(&:method_id)
    assert calls.all? { |event| event.receiver_id == selected.object_id }
    assert_nil probe.instrumentation_error
    refute probe.events.any? { |event| event.receiver_id == other.object_id }
    refute_includes probe.events.flat_map(&:members), :arguments
    refute_includes probe.events.flat_map(&:members), :return_value
    assert_predicate probe.events, :frozen?
  end

  def test_capture_preserves_block_result_and_exception
    worker = ObjectProbeFixtures::Worker.new
    probe = Probe.new(receivers: [worker])

    assert_equal :done, probe.capture { :done }
    error = assert_raises(ArgumentError) { probe.capture { worker.boom } }

    assert_equal "sensitive exception message", error.message
    raised = probe.events.find { |event| event.event == :raise }
    assert_equal "ArgumentError", raised.exception_class
    refute probe.events.inspect.include?(error.message)
  end

  def test_method_filter_and_event_limit_are_explicit
    worker = ObjectProbeFixtures::Worker.new
    probe = Probe.new(receivers: [worker], methods: [:call], max_events: 3)

    probe.capture { 5.times { worker.call(:ok) } }

    assert_operator probe.events.size, :<=, 3
    assert_predicate probe, :truncated?
    assert probe.events.all? { |event| event.method_id == :call }
  end

  def test_method_chain_reports_prepend_override_and_super_implementations
    worker = ObjectProbeFixtures::Child.new

    chain = Probe.method_chain(worker, :perform)

    assert_equal %w[ObjectProbeFixtures::Wrapper ObjectProbeFixtures::Child ObjectProbeFixtures::Parent],
                 chain.map { |entry| entry.fetch(:owner) }
    assert chain.all? { |entry| entry.fetch(:source_location).is_a?(Array) }
    assert chain.all?(&:frozen?)
    assert_predicate chain, :frozen?
  end

  def test_failed_inner_capture_does_not_disable_outer_capture
    worker = ObjectProbeFixtures::Worker.new
    probe = Probe.new(receivers: [worker])

    probe.capture do
      assert_raises(RuntimeError) { probe.capture { :nested } }
      worker.call(:still_traced)
    end

    assert probe.events.any? { |event| event.method_id == :call && event.event == :call }
    assert_nil probe.instrumentation_error
  end

  def test_state_snapshots_report_shape_changes_without_disclosing_values
    worker = ObjectProbeFixtures::Worker.new
    worker.instance_variable_set(:@queue, ["private prompt"])
    before = Probe.state_snapshot(worker)
    worker.instance_variable_get(:@queue) << "private token"
    after = Probe.state_snapshot(worker)

    change = Probe.state_diff(before, after).fetch(:@queue)

    assert_equal 1, change.fetch(:before).fetch(:length)
    assert_equal 2, change.fetch(:after).fetch(:length)
    assert_equal change.fetch(:before).fetch(:object_id), change.fetch(:after).fetch(:object_id)
    refute_includes before.inspect, "private prompt"
    refute_includes after.inspect, "private token"
    assert_predicate before, :frozen?
    assert_predicate after, :frozen?
  end

  def test_event_limit_must_be_positive_and_bounded
    worker = ObjectProbeFixtures::Worker.new

    assert_raises(ArgumentError) { Probe.new(receivers: [worker], max_events: 0) }
    assert_raises(ArgumentError) { Probe.new(receivers: [worker], max_events: Probe::MAX_EVENT_LIMIT + 1) }
    assert_raises(ArgumentError) { Probe.new(receivers: []) }
  end

  def test_a_recursive_capture_is_refused_and_the_outer_capture_survives
    worker = ObjectProbeFixtures::Worker.new
    probe = Master::Trace::ObjectProbe.new(receivers: [worker], methods: %i[call])
    refusal = nil

    probe.capture do
      worker.call(1)
      refusal = assert_raises(RuntimeError) { probe.capture { worker.call(:inner) } }
      worker.call(2)
    end

    assert_match(/already capturing/, refusal.message)
    assert_equal 4, probe.events.size, "both outer calls were recorded, the refused inner one was not"
    assert_equal :ok, probe.capture { worker.call(:ok) }, "the probe is reusable afterwards"
  end

  def test_calls_on_other_threads_are_not_recorded
    worker = ObjectProbeFixtures::Worker.new
    probe = Master::Trace::ObjectProbe.new(receivers: [worker], methods: %i[call])

    probe.capture do
      Thread.new { worker.call(:other_thread) }.join
      worker.call(:owner_thread)
    end

    assert_equal 2, probe.events.size, "only the owner thread's call and return are kept"
    assert_equal %i[call return], probe.events.map(&:event)
  end
end

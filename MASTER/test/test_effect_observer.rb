# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/trace/effect_observer"

class TestEffectObserver < Minitest::Test
  class RecordingBus
    attr_reader :events

    def initialize = @events = []

    def publish_required(name, payload = {})
      @events << [name, payload]
    end
  end

  def test_before_and_after_events_share_an_id_without_persisting_effect_arguments
    bus = RecordingBus.new
    observer = Master::Trace::EffectObserver.new(bus:)
    effect = Master::Core::Effect.write("private-name.txt", "private file contents")

    observer.call(stage: :before, turn: 2, effect:, effect_id: "effect-1")
    observer.call(
      stage: :after, turn: 2, effect:, effect_id: "effect-1",
      observation: Master::Core::Observation.ok("written"), elapsed_ms: 4
    )

    before, after = bus.events
    assert_equal "core:effect:before", before.first
    assert_equal "core:effect:after", after.first
    assert_equal before.last[:effect_id], after.last[:effect_id]
    assert_equal :write, before.last[:verb]
    assert_equal :write, before.last[:capability]
    assert_equal :perform, before.last[:operation]
    assert_equal :unknown, before.last[:reversibility]
    assert_equal "ok", after.last[:status]
    assert_equal 4, after.last[:elapsed_ms]
    refute_includes bus.events.inspect, "private file contents"
    refute_includes bus.events.inspect, "private-name.txt"
  end

  def test_reversibility_classification_is_carried_to_both_lifecycle_events
    bus = RecordingBus.new
    observer = Master::Trace::EffectObserver.new(bus:)
    effect = Master::Core::Effect.write("release.txt", "release")

    observer.call(
      stage: :before, turn: 3, effect:, effect_id: "release-1",
      reversibility: :irreversible, idempotency_key: "release-2026-10-26"
    )
    observer.call(
      stage: :after, turn: 3, effect:, effect_id: "release-1",
      reversibility: :irreversible, idempotency_key: "release-2026-10-26",
      observation: Master::Core::Observation.ok("submitted")
    )

    before, after = bus.events.map(&:last)
    assert_equal :irreversible, before[:reversibility]
    assert_equal :irreversible, after[:reversibility]
    assert_equal "release-2026-10-26", before[:idempotency_key]
    assert_equal before[:effect_id], after[:effect_id]
  end

  def test_rollback_event_links_to_the_original_effect_and_checkpoint
    bus = RecordingBus.new
    observer = Master::Trace::EffectObserver.new(bus:)
    effect = Master::Core::Effect.write("note.txt", "x")

    observer.call(
      stage: :before, turn: 1, effect:, effect_id: "rollback-1",
      operation: :rollback, parent_effect_id: "failed-1", checkpoint_id: "cp-1"
    )

    name, payload = bus.events.fetch(0)
    assert_equal "core:effect:before", name
    assert_equal :rollback, payload[:operation]
    assert_equal "failed-1", payload[:parent_effect_id]
    assert_equal "cp-1", payload[:checkpoint_id]
  end

  def test_requires_a_bus_with_strict_persistence
    error = assert_raises(ArgumentError) { Master::Trace::EffectObserver.new(bus: Object.new) }
    assert_match(/publish_required/, error.message)
  end

  def test_rejects_unknown_lifecycle_stage
    observer = Master::Trace::EffectObserver.new(bus: RecordingBus.new)
    effect = Master::Core::Effect.read("README.md")

    error = assert_raises(ArgumentError) do
      observer.call(stage: :middle, turn: 0, effect:, effect_id: "effect-2")
    end

    assert_match(/unknown effect lifecycle stage/, error.message)
  end
end

# frozen_string_literal: true

require_relative "test_helper"

class TestDiag < Minitest::Test
  class FakeBus
    def initialize
      @handlers = Hash.new { |hash, key| hash[key] = [] }
    end

    def subscribe(pattern, &handler)
      @handlers[pattern] << handler
    end

    def publish(event, payload = {})
      @handlers[event].each { |handler| handler.call(payload.merge(event:)) }
    end
  end

  class FakeBreaker
    def session_total
      0.0123
    end

    def open_models
      []
    end
  end

  def test_diag_cache_section_reports_cache_hit_events
    bus = FakeBus.new
    diag = Master::Trace::Diag.new(
      homeostat: nil,
      breaker: FakeBreaker.new,
      logging: nil,
      scan_registry: nil,
      event_bus: bus,
    )

    bus.publish("cache:hit", model: "claude", cached: 120, cache_write: 30)
    output = diag.render("cache")

    assert_includes output, "hits=1"
    assert_includes output, "cached_tokens=120"
    assert_includes output, "cache_writes=30"
    assert_includes output, "models=claude"
  end
end

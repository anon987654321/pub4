# frozen_string_literal: true

require_relative "test_helper"

class TestGatewayClientActions < Minitest::Test
  class FakeBus
    def initialize
      @handlers = Hash.new { |h, k| h[k] = [] }
    end

    def subscribe(pattern, &handler)
      @handlers[pattern] << handler
      -> { @handlers[pattern].delete(handler) }
    end

    def publish(event, payload = {})
      enriched = payload.merge(event:)
      @handlers.each do |pattern, handlers|
        next unless pattern == event || pattern == "client_action"

        handlers.each { |h| h.call(enriched) }
      end
      self
    end
  end

  def test_receive_attaches_client_actions_to_result
    bus = FakeBus.new
    pipeline = lambda do |input|
      bus.publish("client_action", action: "dilla_bg", label: "J Dilla pocket")
      Master::Result.ok({ rendered: "Music: Dilla pocket", intent: :command })
    end
    gateway = Master::Io::Gateway.new(pipeline:, session: Object.new, event_bus: bus)

    result = gateway.receive(channel: :cli, message: "/music")
    assert result.ok?
    value = result.value!
    assert_equal "Music: Dilla pocket", value[:rendered]
    assert_equal 1, value[:client_actions].size
    assert_equal "dilla_bg", value[:client_actions].first[:action]
  end

  def test_receive_omits_client_actions_when_none
    bus = FakeBus.new
    pipeline = ->(_input) { Master::Result.ok({ rendered: "ok" }) }
    gateway = Master::Io::Gateway.new(pipeline:, session: Object.new, event_bus: bus)

    result = gateway.receive(channel: :cli, message: "/help")
    assert result.ok?
    refute result.value!.key?(:client_actions)
  end
end

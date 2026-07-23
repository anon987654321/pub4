# frozen_string_literal: true

require "test_helper"

# Note: EventsController#stream is a real-time SSE loop (ActionController::Live)
# that only returns after MAX_STREAM_S (600s) or a client disconnect -- there's
# no existing Ruby-side pattern in this suite for exercising it via a bounded
# request/response cycle (SSE coverage elsewhere is JS-side: sse_contract.test.mjs).
# Testing the full stream action here risked hanging the test run for up to 10
# minutes with no safe short-circuit, so this covers the one piece that's both
# real logic and safely testable in isolation: the visitor-tier event filter.
class EventsControllerTest < ActionDispatch::IntegrationTest
  def controller
    @controller ||= EventsController.new
  end

  test "visitor_safe_event? allows tts and pipeline:stage events" do
    assert controller.send(:visitor_safe_event?, type: "tts:started")
    assert controller.send(:visitor_safe_event?, type: "pipeline:stage_complete")
    assert controller.send(:visitor_safe_event?, type: "pressure:updated")
    assert controller.send(:visitor_safe_event?, type: "council:deliberation")
    assert controller.send(:visitor_safe_event?, type: "link")
  end

  test "visitor_safe_event? blocks everything else" do
    refute controller.send(:visitor_safe_event?, type: "llm:request")
    refute controller.send(:visitor_safe_event?, type: "tool:used")
    refute controller.send(:visitor_safe_event?, type: "scan:complete")
    refute controller.send(:visitor_safe_event?, type: "autoloop:cycle")
  end
end

# frozen_string_literal: true

require "test_helper"

# EventsController#stream is an SSE loop that only returns after MAX_STREAM_S or
# a client disconnect, so these cover the logic beside it: the visitor filter
# and the bounded, non-blocking hand-off from the bus to the stream.
class EventsControllerTest < ActionDispatch::IntegrationTest
  MINE = "conv-1"

  def controller
    @controller ||= EventsController.new
  end

  def safe?(type, conversation: nil)
    data = conversation ? { conversation: } : {}
    controller.send(:visitor_safe_event?, { type:, data: }, MINE)
  end

  test "visitor_safe_event? passes the orb's public signals" do
    assert safe?("council:start")
    assert safe?("link")
  end

  test "visitor_safe_event? passes tts and stage events only for the visitor's own conversation" do
    assert safe?("tts:started", conversation: MINE)
    assert safe?("pipeline:stage_complete", conversation: MINE)
    refute safe?("tts:started", conversation: "someone-else")
    refute safe?("pipeline:stage_complete")
  end

  test "visitor_safe_event? blocks everything else" do
    refute safe?("llm:request")
    refute safe?("tool:before")
    refute safe?("scan:complete")
    refute safe?("autoloop:cycle")
  end

  test "the visitor payload drops the tts job id and the conversation" do
    event = { type: "tts:started", data: { job_id: "j", conversation: MINE, text: "hei" } }

    assert_equal({ text: "hei" }, controller.send(:visitor_safe_payload, event)[:data])
  end

  test "offer filters before the queue and drops when full instead of blocking" do
    queue = SizedQueue.new(2)
    refute controller.send(:offer, queue, { event: "llm:request" }, visitor_tier: true, mine: "c1")
    assert_equal 0, queue.size

    2.times { assert controller.send(:offer, queue, { event: "link" }, visitor_tier: true, mine: "c1") }
    refute controller.send(:offer, queue, { event: "link" }, visitor_tier: true, mine: "c1")
    assert_equal 2, queue.size
  end

  test "the stream subscription sees colon-named events" do
    bus = Master::Trace::EventBus.new(event_log: Class.new { def append(*) = nil }.new)
    seen = []
    bus.subscribe(EventsController::STREAM_PATTERN) { |ev| seen << ev[:event] }
    bus.publish("pipeline:stage_start")
    bus.publish("tts:started")

    assert_equal %w[pipeline:stage_start tts:started], seen
  end
end

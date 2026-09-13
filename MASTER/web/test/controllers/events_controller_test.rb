# frozen_string_literal: true

require "test_helper"

# EventsController#stream is an ActionController::Live loop that returns only
# after MAX_STREAM_S or a disconnect, so this covers the part that is real logic
# and safe to run in isolation: what a visitor is allowed to see.
class EventsControllerTest < ActionDispatch::IntegrationTest
  MINE = "conv-1"

  def controller
    @controller ||= EventsController.new
  end

  def safe?(type, conversation: nil)
    data = conversation ? { conversation: conversation } : {}
    controller.send(:visitor_safe_event?, { type: type, data: data }, MINE)
  end

  test "visitor_safe_event? passes the orb's public signals" do
    assert safe?("pressure:updated")
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
end

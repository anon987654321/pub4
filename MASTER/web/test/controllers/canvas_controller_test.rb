# frozen_string_literal: true

require "test_helper"

class CanvasControllerTest < ActionDispatch::IntegrationTest
  test "post_event accepts allowed topic" do
    post "/canvas/event", params: { topic: "canvas:mood", payload: { mood: "calm" } }

    assert_response :accepted
  end

  test "post_event rejects unknown topic" do
    post "/canvas/event", params: { topic: "canvas:evil", payload: {} }

    assert_response :unprocessable_entity
  end

  test "state accepts mood payload" do
    post "/canvas/state", params: { mood: "focus", mode: "idle", idle: 3, palette: 1 }

    assert_response :accepted
  end
end
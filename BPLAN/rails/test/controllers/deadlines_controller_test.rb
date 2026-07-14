# frozen_string_literal: true

require "test_helper"

class DeadlinesControllerTest < ActionDispatch::IntegrationTest
  test "deadlines index" do
    get deadlines_url
    assert_response :success
    assert_includes response.body, "Fristkalender"
    assert_includes response.body, "Last ned ICS"
  end

  test "deadlines ics" do
    get "/deadlines.ics"
    assert_response :success
    assert_includes response.body, "BEGIN:VCALENDAR"
  end
end
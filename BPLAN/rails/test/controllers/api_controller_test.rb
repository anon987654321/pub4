# frozen_string_literal: true

require "test_helper"

class ApiControllerTest < ActionDispatch::IntegrationTest
  test "api plans json" do
    get api_plans_url
    assert_response :success
    data = JSON.parse(response.body)
    assert data.is_a?(Array)
    assert_equal "master", data.first["slug"]
  end

  test "api legats json with track filter" do
    get api_legats_url(track: "bolig")
    assert_response :success
    data = JSON.parse(response.body)
    assert data.all? { |entry| entry["track"] == "bolig" }
  end
end
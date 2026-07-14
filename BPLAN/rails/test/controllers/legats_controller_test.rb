# frozen_string_literal: true

require "test_helper"

class LegatsControllerTest < ActionDispatch::IntegrationTest
  test "legats index filters by track" do
    get legats_url(track: "bolig")
    assert_response :success
    assert_includes response.body, 'track-pill--bolig'
    assert_not_includes response.body, 'track-pill--innovasjon'
  end

  test "legats index shows badges" do
    get legats_url
    assert_response :success
    assert_includes response.body, "status-badge"
    assert_includes response.body, "Sendbar"
  end

  test "missing legat returns not found" do
    get legat_url(id: "does_not_exist")
    assert_response :not_found
  end
end
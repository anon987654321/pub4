# frozen_string_literal: true

require "test_helper"

class OperatorControllerTest < ActionDispatch::IntegrationTest
  test "operator dashboard requires authentication" do
    get operator_dashboard_path
    assert_response :redirect
  end
end
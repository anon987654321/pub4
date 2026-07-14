# frozen_string_literal: true

require "test_helper"

class PortfolioControllerTest < ActionDispatch::IntegrationTest
  test "portfolio page" do
    get portfolio_url
    assert_response :success
    assert_includes response.body, "Portefølje"
    assert_includes response.body, "Konvergens"
  end
end
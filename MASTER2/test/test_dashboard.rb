# frozen_string_literal: true

require_relative "test_helper"

class TestDashboard < Minitest::Test
  def test_responds_to_public_api
    assert_respond_to MASTER::Dashboard, :render
    assert_respond_to MASTER::Dashboard, :show
  end

  def test_dashboard_module_exists
    assert defined?(MASTER::Dashboard), "MASTER::Dashboard should be defined"
  end
end

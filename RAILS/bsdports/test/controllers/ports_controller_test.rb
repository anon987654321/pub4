# frozen_string_literal: true

require "test_helper"

class PortsControllerTest < ActionDispatch::IntegrationTest
  def test_root_renders_ports_index
    get root_url
    assert_response :success
  end
end

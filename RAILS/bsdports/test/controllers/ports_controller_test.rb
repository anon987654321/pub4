# frozen_string_literal: true

require "test_helper"

class PortsControllerTest < ActionDispatch::IntegrationTest
  def test_root_renders_ports_index
    get root_url
    assert_response :success
  end

  def test_legal_pages_are_public
    %w[/privacy /terms /cookies].each do |path|
      get path
      assert_response :success, path
      assert_includes response.body, "legal-prose"
    end
  end
end

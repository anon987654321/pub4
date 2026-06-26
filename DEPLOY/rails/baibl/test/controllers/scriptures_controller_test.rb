# frozen_string_literal: true

require "test_helper"

class ScripturesControllerTest < ActionDispatch::IntegrationTest
  def test_root_renders_scripture_index
    get root_url
    assert_response :success
  end
end
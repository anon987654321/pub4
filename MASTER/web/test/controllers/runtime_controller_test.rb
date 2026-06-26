# frozen_string_literal: true

require "test_helper"

class RuntimeControllerTest < ActionDispatch::IntegrationTest
  test "config returns json without container" do
    Rails.application.config.x.master_container = nil

    get "/runtime/config"

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("topologies")
    assert body.key?("tts_config")
  end

  test "topologies returns json without container" do
    Rails.application.config.x.master_container = nil

    get "/runtime/topologies"

    assert_response :success
    assert_kind_of Hash, JSON.parse(response.body)
  end
end
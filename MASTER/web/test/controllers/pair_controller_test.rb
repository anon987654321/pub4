# frozen_string_literal: true

require "test_helper"

class PairControllerTest < ActionDispatch::IntegrationTest
  def teardown
    FileUtils.rm_rf(File.join(Master::ROOT, ".master", "pairing"))
  end

  test "show reports unpaired for a visitor" do
    get "/pair"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["paired"]
  end

  test "create redeems a code and sets the cookie" do
    issued = Master::Ground::Pairing.issue(label: "test")
    post "/pair", params: { code: issued[:code] }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["ok"]
    assert_equal "messaging", body["profile"]
    assert cookies[:master_paired].present?
  end

  test "create rejects a bad code" do
    post "/pair", params: { code: "NOPE1234" }

    assert_response :unprocessable_entity
  end

  test "pair redeem works without a booted container" do
    Rails.application.config.x.master_container = nil
    issued = Master::Ground::Pairing.issue(label: "warm")
    post "/pair", params: { code: issued[:code] }

    assert_response :success
  end
end

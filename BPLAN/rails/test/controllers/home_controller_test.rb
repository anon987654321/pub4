# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "frontpage" do
    get root_url
    assert_response :success
    assert_includes response.body, "MASTER"
    assert_includes response.body, "Brostøtte"
    assert_includes response.body, "Bolig i Bergen"
  end

  test "plans and legats" do
    get plans_url
    assert_response :success
    assert_includes response.body, "track-pill"

    get plan_url(slug: "master")
    assert_response :success
    assert_includes response.body, "Budsjett"

    get legats_url
    assert_response :success

    get legat_url(id: "01_innovasjon_norge_master")
    assert_response :success
    assert_includes response.body, "Send-sjekkliste"
  end

  test "payment flow ignores tampered amount" do
    post pay_url(slug: "master"), params: { kind: "legat", amount: 1 }
    assert_redirected_to %r{/pay/master}
    follow_redirect!
    assert_response :success
    assert_includes response.body, "75,000"
    assert_not_includes response.body, ">NOK 1<"
  end

  test "norwegian hedge hides IN pay button" do
    get root_url
    assert_response :success
    assert_includes response.body, "Norwegian Hedge"
    assert_no_match(%r{/pay/norwegian_hedge}, response.body)
  end
end
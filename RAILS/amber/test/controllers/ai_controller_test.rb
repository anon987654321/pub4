# frozen_string_literal: true

require "test_helper"

# AiController runs offline in tests (no OpenRouter key, no MASTER bridge), so
# these pin the paths every reader hits: the heuristic notice speaks nb, the
# suggestion page renders without the photograph bridge, and the GET that can
# shell out to MASTER stops at its own limit.
class AiControllerTest < ActionDispatch::IntegrationTest
  def sign_in_as(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  test "the heuristic joy analysis notice is a key" do
    user = sign_in_as("ai-joy@example.com")
    item = user.items.create!(title: "Ullgenser", category: "Tops", times_worn: 12)

    post ai_analyze_item_path(item)

    assert_redirected_to item_path(item)
    assert_includes [ I18n.t("flash.joy_analysis_heuristic"), I18n.t("flash.joy_analysis_ai") ], flash[:notice]
  end

  test "suggest outfits renders without the MASTER photograph bridge" do
    sign_in_as("ai-suggest@example.com")

    get ai_suggest_outfits_path

    assert_response :success
    refute WardrobeAi.master_photograph_available?
  end

  test "suggest outfits stops at its own limit" do
    sign_in_as("ai-limit@example.com")

    10.times { get ai_suggest_outfits_path }
    assert_response :success

    get ai_suggest_outfits_path
    assert_redirected_to items_path
    assert_equal I18n.t("shared.flash.rate_limited"), flash[:alert]
  end

  test "a guest is sent to sign in" do
    get ai_suggest_outfits_path

    assert_response :redirect
  end
end

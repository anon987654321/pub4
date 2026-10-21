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

  test "suggest outfits renders without the STUDIO photograph bridge" do
    sign_in_as("ai-suggest@example.com")

    get ai_suggest_outfits_path

    assert_response :success
    refute WardrobeAi.studio_photograph_available?
  end

  test "GET analysis pages do not persist state or enqueue recommendations" do
    sign_in_as("ai-get-read-only@example.com")

    assert_no_difference -> { PackingList.count + StylePreference.count + Recommendation.count } do
      assert_no_enqueued_jobs(only: RecommendOutfitsJob) do
        get ai_suggest_outfits_path
        assert_response :success
        get ai_packing_list_path, params: { duration: "3", climate: "cold" }
        assert_response :success
        get ai_style_profile_path, params: { answers: { body_type: "slim" } }
        assert_response :success
      end
    end
  end

  test "packing list is persisted only after explicit POST" do
    sign_in_as("ai-packing-post@example.com")

    assert_no_difference -> { PackingList.count } do
      get ai_packing_list_path, params: { duration: "3", climate: "cold" }
      assert_response :success
    end

    assert_difference -> { PackingList.count }, 1 do
      post ai_create_packing_list_path, params: { duration: "3", climate: "cold" }
    end
    assert_response :success
  end

  test "suggest outfits stops at its own limit" do
    sign_in_as("ai-limit@example.com")

    10.times { get ai_suggest_outfits_path }
    assert_response :success

    get ai_suggest_outfits_path
    assert_redirected_to items_path
    assert_equal I18n.t("shared.flash.rate_limited"), flash[:alert]
  end

  test "saving a generated outfit is rate limited" do
    sign_in_as("ai-generate-limit@example.com")

    10.times { post ai_generate_outfit_path }
    assert_response :redirect

    post ai_generate_outfit_path
    assert_redirected_to items_path
    assert_equal I18n.t("shared.flash.rate_limited"), flash[:alert]
  end

  test "a guest is sent to sign in" do
    get ai_suggest_outfits_path

    assert_response :redirect
  end
end

# frozen_string_literal: true

require "test_helper"

class PrivacySettingsControllerTest < ActionDispatch::IntegrationTest
  def sign_in_as(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  test "a guest cannot open privacy settings" do
    get privacy_setting_path

    assert_response :redirect
  end

  test "owner can disable external AI and injected clients cannot bypass consent" do
    user = sign_in_as("privacy-ai@example.com")

    get privacy_setting_path
    assert_response :success
    assert_select "input[name='privacy_setting[allow_ai_analysis]']"

    patch privacy_setting_path, params: { privacy_setting: { allow_ai_analysis: "0" } }

    assert_redirected_to privacy_setting_path
    refute user.privacy_setting.reload.allow_ai_analysis?

    service = WardrobeAi.new(user, client: Object.new)
    refute service.available?
    item = user.items.create!(title: "Wool jumper", category: "Tops", times_worn: 4)
    assert_equal "heuristic", service.analyze_joy(item).fetch("source")
  end
end

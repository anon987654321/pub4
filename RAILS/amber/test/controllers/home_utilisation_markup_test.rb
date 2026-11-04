# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The utilisation dd wrote class="" whenever the rate was not low.
class HomeUtilisationMarkupTest < ActionDispatch::IntegrationTest
  test "a healthy utilisation has no empty class attribute" do
    email = "hu-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    worn = user.items.create!(title: "Actually worn", category: "Tops")
    worn.wear!(worn_on: Date.current)

    Weather.stub(:today, nil) { get root_url }
    assert_response :success
    assert_select ".dash-stats dd", text: "100%" do |nodes|
      assert_nil nodes.first["class"]
    end
  end

  test "a low utilisation is still marked" do
    email = "hl-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    user.items.create!(title: "Never worn", category: "Tops")

    Weather.stub(:today, nil) { get root_url }
    assert_select ".dash-stats dd.stat-warn", text: "0%"
  end
end

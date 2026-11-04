# frozen_string_literal: true

require "test_helper"

# UsersController#show loaded @outfits under the wardrobe visibility policy
# and users/show never drew them, so a profile showed pieces but no looks.
class UsersProfileTest < ActionDispatch::IntegrationTest
  setup do
    email = "owner-#{SecureRandom.hex(4)}@example.test"
    @owner = User.strict_loading(false).create!(email_address: email, password: "password")
    @outfit = Outfit.strict_loading(false).create!(user: @owner, name: "Fredagsantrekk")
  end

  test "the owner sees their outfits on their profile" do
    post session_path, params: { email_address: @owner.email_address, password: "password" }

    get user_path(@owner)
    assert_response :success
    assert_select "h2", text: I18n.t("users.outfits")
    assert_select ".item-grid article##{ActionView::RecordIdentifier.dom_id(@outfit)}"
  end

  test "a guest who may not see the wardrobe sees no outfits" do
    get user_path(@owner)
    assert_response :success
    assert_select "article##{ActionView::RecordIdentifier.dom_id(@outfit)}", 0
  end
end

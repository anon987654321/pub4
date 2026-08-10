# frozen_string_literal: true

require "test_helper"

# items#show and outfits#show/like/reorder were listed in their controllers'
# set_* before_action but omitted from authorize!, and set_item/set_outfit are
# unscoped .find calls. Any signed-in user could therefore read another user's
# wardrobe and reorder their outfits.
class WardrobeAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "wa_owner@example.com", password: "secret1234")
    @other = User.create!(email_address: "wa_other@example.com", password: "secret1234")
    @item = Item.create!(title: "Private coat", category: "Outerwear", user: @owner)
    @outfit = Outfit.create!(name: "Private fit", user: @owner)
    sign_in_as(@other)
  end

  test "a stranger cannot read another user's item when the wardrobe is not public" do
    get item_path(@item)

    assert_response :redirect
    assert_equal "Unauthorized", flash[:alert]
  end

  test "a stranger cannot read another user's outfit when the wardrobe is not public" do
    get outfit_path(@outfit)

    assert_response :redirect
    assert_equal "Unauthorized", flash[:alert]
  end

  test "a stranger cannot reorder another user's outfit" do
    patch reorder_outfit_path(@outfit), params: { positions: [ 1, 2 ] }

    assert_response :redirect
    assert_equal "Unauthorized", flash[:alert]
  end

  test "the owner can still read their own item and outfit" do
    sign_in_as(@owner)

    get item_path(@item)
    assert_response :success

    get outfit_path(@outfit)
    assert_response :success
  end

  private

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end
end

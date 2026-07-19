# frozen_string_literal: true

require "test_helper"

# Request-level coverage for amber wardrobe mutations (items, outfits, wear).
class WardrobeMutationsTest < ActionDispatch::IntegrationTest
  def make_user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@amber.test",
      password: "password",
      password_confirmation: "password"
    )
  end

  def sign_in_amber(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  test "create wardrobe item requires auth" do
    assert_no_difference -> { Item.count } do
      post items_path, params: { item: { title: "Coat", category: "Outerwear" } }
    end
    assert_response :redirect
  end

  test "signed-in user can create item and mark wear" do
    user = make_user("owner")
    sign_in_amber(user)

    assert_difference -> { Item.count }, 1 do
      post items_path, params: {
        item: { title: "Navy blazer", category: "Outerwear", brand: "Test" }
      }
    end
    item = Item.order(:id).last
    assert_equal user.id, item.user_id
    assert_redirected_to item_path(item)

    worn_before = item.times_worn.to_i
    post wear_item_path(item)
    assert_redirected_to item_path(item)
    assert_equal worn_before + 1, item.reload.times_worn
  end

  test "signed-in user can create outfit from wardrobe items" do
    user = make_user("stylist")
    sign_in_amber(user)
    top = user.items.create!(title: "Tee", category: "Tops")
    bottom = user.items.create!(title: "Jeans", category: "Bottoms")

    assert_difference -> { Outfit.count }, 1 do
      post outfits_path, params: {
        outfit: {
          name: "Casual Friday",
          season: "all",
          occasion: "work",
          outfit_items_attributes: {
            "0" => { item_id: top.id, position: 0 },
            "1" => { item_id: bottom.id, position: 1 }
          }
        }
      }
    end
    outfit = Outfit.order(:id).last
    assert_equal user.id, outfit.user_id
    assert_equal 2, outfit.outfit_items.count
    assert_redirected_to outfit_path(outfit)

    post wear_outfit_path(outfit)
    assert_redirected_to outfit_path(outfit)
  end

  test "non-owner cannot wear another user item" do
    owner = make_user("item_owner")
    other = make_user("item_other")
    item = owner.items.create!(title: "Scarf", category: "Accessories")
    sign_in_amber(other)

    post wear_item_path(item)
    assert_response :redirect
    assert_equal 0, item.reload.times_worn.to_i
  end
end

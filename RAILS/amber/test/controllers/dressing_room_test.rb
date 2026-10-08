# frozen_string_literal: true

require "test_helper"

class DressingRoomTest < ActionDispatch::IntegrationTest
  def sign_in_as(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  test "zones are ordered by taste, not by insertion" do
    user = sign_in_as("dressing-order@example.com")
    user.items.create!(title: "Forgotten tee", category: "Tops", times_worn: 0, spark_joy: false)
    favourite = user.items.create!(title: "Everyday tee", category: "Tops", times_worn: 10, spark_joy: true, last_worn_on: Date.current)

    get dressing_room_outfits_path

    assert_response :success
    zones = JSON.parse(css_select("[data-wardrobe-carousel-zones-value]").first["data-wardrobe-carousel-zones-value"])
    assert_equal favourite.id, zones["top"].first["id"]
  end

  test "save_look keeps the combination the carousels were showing" do
    user = sign_in_as("dressing-save@example.com")
    top = user.items.create!(title: "Linen shirt", category: "Tops")
    bottom = user.items.create!(title: "Wide trousers", category: "Bottoms")
    shoes = user.items.create!(title: "Loafers", category: "Shoes")

    assert_difference "Outfit.count", 1 do
      post save_look_outfits_path, params: { item_ids: [ top.id, bottom.id, shoes.id ] }
    end

    outfit = Outfit.order(:id).last
    assert_redirected_to outfit
    assert_equal [ top.id, bottom.id, shoes.id ], outfit.outfit_items.order(:position).pluck(:item_id)
  end

  test "save_look drops blank zone slots rather than failing" do
    user = sign_in_as("dressing-blank@example.com")
    top = user.items.create!(title: "Knit", category: "Tops")

    assert_difference "Outfit.count", 1 do
      post save_look_outfits_path, params: { item_ids: [ "", top.id.to_s, "", "" ] }
    end

    assert_equal [ top.id ], Outfit.order(:id).last.outfit_items.pluck(:item_id)
  end

  test "save_look will not steal another wardrobe's garment" do
    other = User.strict_loading(false).create!(email_address: "dressing-other@example.com", password: "password")
    stolen = other.items.create!(title: "Their coat", category: "Outerwear")
    sign_in_as("dressing-thief@example.com")

    assert_no_difference "Outfit.count" do
      post save_look_outfits_path, params: { item_ids: [ stolen.id ] }
    end

    assert_redirected_to dressing_room_outfits_path
  end

  test "save_look with nothing picked returns to the dressing room" do
    sign_in_as("dressing-empty@example.com")

    assert_no_difference "Outfit.count" do
      post save_look_outfits_path, params: { item_ids: [ "", "" ] }
    end

    assert_redirected_to dressing_room_outfits_path
  end
end

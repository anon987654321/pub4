# frozen_string_literal: true

require "test_helper"

class MenuControllerTest < ActiveSupport::TestCase
  setup do
    @kitchen = seed_kitchen!
    @wraps = seed_category!(@kitchen, name: "Wraps & Ruller", slug: "wraps", emoji: "🌯")
    @item = seed_item!(@wraps, name: "Damaskus Kylling Shawarma", price_ore: 12900)
  end

  test "root renders the catalog with the seeded items" do
    get root_url
    assert_response :success

    assert_match "Damaskus Kylling Shawarma", response.body
    assert_match "129 kr", response.body                       # money(12900)
    assert_match(/4[.,]9/, response.body)                      # kitchen rating ⭐
    assert_match "11–23", response.body                        # opening hours
    assert_match "Wraps & Ruller", response.body               # category section
  end

  test "the item page shows the origin story and the options" do
    seed_option!(@item, name: "Toum", kind: "sauce", default_on: true)
    seed_option!(@item, name: "Salat", kind: "topping")

    get menu_item_url(@item)
    assert_response :success

    assert_match "Souq al-Hamidiyah", response.body  # origins.damaskus story
    assert_match "Toum", response.body
    assert_match "Salatbar", response.body           # free toppings presented as salatbar
    assert_match "Legg i kurv", response.body        # sticky add button
  end

  test "the reorder card greets returning customers with Yalla igjen" do
    user = customer_sign_in
    seed_order!(user: user, kitchen: @kitchen, state: "delivered")

    get root_url
    assert_response :success
    assert_match "Yalla igjen", response.body
  end

  test "guests do not see the reorder card" do
    get root_url
    assert_response :success
    assert_no_match(/Yalla igjen/, response.body)
  end

  test "sold-out items stay off the menu" do
    seed_item!(@wraps, name: "Hemmelig test-wrap", name_en: "Secret test wrap",
               available: false)

    get root_url
    assert_response :success
    assert_no_match(/Hemmelig test-wrap/, response.body)
  end
end

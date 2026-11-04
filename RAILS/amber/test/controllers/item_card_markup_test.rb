# frozen_string_literal: true

require "test_helper"

# items/_item opened with two HTML comments naming the brands the card was
# styled after; they shipped to every client inside every card.
class ItemCardMarkupTest < ActionDispatch::IntegrationTest
  test "wardrobe cards carry no design notes" do
    email = "ic-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user.items.create!(title: "Linen shirt", category: "Tops")

    get items_path
    assert_response :success
    assert_includes response.body, "Linen shirt"
    assert_not_includes response.body, "Luxury minimalist card"
  end

  # A garment with no photo left the card's photo area empty, where the demo
  # and outfit cards draw the category's initial.
  test "a wardrobe card without a photo shows the category initial" do
    email = "ic-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    user.items.create!(title: "Linen shirt", category: "Tops")

    get items_path
    assert_select ".item-photo-wrap .item-photo--placeholder[aria-hidden=true]", text: "T"
  end
end

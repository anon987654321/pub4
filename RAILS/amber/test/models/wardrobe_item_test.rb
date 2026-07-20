# frozen_string_literal: true

require "test_helper"

class WardrobeItemTest < ActiveSupport::TestCase
  setup do
    @user = User.strict_loading(false).create!(email_address: "wardrobe@amber.test", password: "password123")
    @item = Item.create!(user: @user, title: "Coat", category: "Outerwear")
  end

  test "requires unique item per user wardrobe" do
    WardrobeItem.create!(user: @user, item: @item)
    duplicate = WardrobeItem.new(user: @user, item: @item)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "validates condition inclusion" do
    entry = WardrobeItem.new(user: @user, item: @item, condition: "mythical")

    assert_not entry.valid?
    assert_includes entry.errors[:condition], "is not included in the list"
  end
end

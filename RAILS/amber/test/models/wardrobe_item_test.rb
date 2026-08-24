# frozen_string_literal: true

require "test_helper"

# Asserted through the I18n key, not the English sentence. These apps default
# to nb; the literals only ever matched because rails-i18n was missing, so the
# tests were pinned to the absence of a translation.
class WardrobeItemTest < ActiveSupport::TestCase
  setup do
    @user = User.strict_loading(false).create!(email_address: "wardrobe@amber.test", password: "password123")
    @item = Item.create!(user: @user, title: "Coat", category: "Outerwear")
  end

  test "requires unique item per user wardrobe" do
    WardrobeItem.create!(user: @user, item: @item)
    duplicate = WardrobeItem.new(user: @user, item: @item)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], I18n.t("errors.messages.taken")
  end

  test "validates condition inclusion" do
    entry = WardrobeItem.new(user: @user, item: @item, condition: "mythical")

    assert_not entry.valid?
    assert_includes entry.errors[:condition], I18n.t("errors.messages.inclusion")
  end
end

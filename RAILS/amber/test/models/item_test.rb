# frozen_string_literal: true

require "test_helper"

class ItemTest < ActiveSupport::TestCase
  test "for_lifecycle maps chips onto the inventory scopes" do
    assert_equal Item.declutter_box.to_sql, Item.for_lifecycle("box").to_sql
    assert_equal Item.sentimental.to_sql, Item.for_lifecycle("memory").to_sql
    assert_equal Item.seasonal_archived.to_sql, Item.for_lifecycle("seasonal").to_sql
    assert_equal Item.active_wardrobe.to_sql, Item.for_lifecycle("active").to_sql
    assert_equal Item.all.to_sql, Item.for_lifecycle("all").to_sql
  end

  test "cost_per_wear is nil until price and wears are usable" do
    item = Item.new(price: 100, times_worn: 0)
    assert_nil item.cost_per_wear

    item.times_worn = nil
    assert_nil item.cost_per_wear
  end

  test "cost_per_wear rounds to two decimals" do
    item = Item.new(price: 100, times_worn: 3)

    assert_equal 33.33, item.cost_per_wear
  end

  test "occasions normalizes comma-separated tags" do
    item = Item.new(occasion_tags: "work, casual,travel")

    assert_equal [ "work", "casual", "travel" ], item.occasions
  end

  test "wear! increments times_worn, logs wear, and updates cost_per_wear" do
    user = User.strict_loading(false).create!(email_address: "wear-item@amber.test", password: "password123")
    item = Item.create!(user: user, title: "Tee", category: "Tops", price: 30, times_worn: 0)

    assert_nil item.cost_per_wear

    assert_difference -> { item.wear_logs.count }, 1 do
      item.wear!(worn_on: Date.new(2026, 7, 20), context: "test")
    end

    item.reload
    assert_equal 1, item.times_worn
    assert_equal Date.new(2026, 7, 20), item.last_worn_on
    assert_equal 30.0, item.cost_per_wear
    assert_equal "test", item.wear_logs.last.context
    assert_equal "active", item.lifecycle_state
  end
end

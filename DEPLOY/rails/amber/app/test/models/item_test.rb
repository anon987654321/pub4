require "test_helper"

class ItemTest < ActiveSupport::TestCase
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

    assert_equal ["work", "casual", "travel"], item.occasions
  end
end

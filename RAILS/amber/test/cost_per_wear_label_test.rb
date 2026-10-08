# frozen_string_literal: true

require "test_helper"

# The demo wardrobe printed "8.63 per wear" and "not worn yet" on a Norwegian
# page, from a model method that knew neither the locale nor the currency. The
# figure now goes through items.per_wear and number_to_currency, the same pair
# items/show already uses, and a garment without a price says nothing rather
# than calling itself unworn.
class CostPerWearLabelTest < ActionView::TestCase
  include ApplicationHelper

  test "a priced, worn garment reads its cost per wear through the locale" do
    item = Item.new(price_cents: 86_300, times_worn: 100)

    assert_equal I18n.t("items.per_wear", amount: number_to_currency(8.63)), cost_per_wear_label(item)
  end

  test "an unpriced or unworn garment carries no figure" do
    assert_nil cost_per_wear_label(Item.new(price_cents: nil, times_worn: 8))
    assert_nil cost_per_wear_label(Item.new(price_cents: 86_300, times_worn: 0))
  end

  test "the demo card spells its wear count and figure through the locale" do
    item = Item.new(id: 1, title: "Sage linen shorts", category: "Bottoms", brand: "COS",
                    price_cents: 6_904, times_worn: 8)

    render partial: "demo_wardrobe/item", locals: { item: item }

    assert_includes rendered, I18n.t("items.worn_times_short", count: 8)
    assert_includes rendered, cost_per_wear_label(item)
  end
end

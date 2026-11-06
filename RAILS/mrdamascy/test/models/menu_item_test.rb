# frozen_string_literal: true

require "test_helper"

class MenuItemTest < ActiveSupport::TestCase
  setup do
    @kitchen = seed_kitchen!
    @category = seed_category!(@kitchen)
  end

  test "heat accepts the 0–3 scale" do
    [ 0, 1, 2, 3 ].each do |heat|
      item = seed_item!(@category, heat: heat)
      assert item.valid?, "heat #{heat} should be valid"
    end
  end

  test "heat refuses anything outside 0–3" do
    [ 4, -1 ].each do |heat|
      item = MenuItem.new(
        menu_category: @category,
        name: "Prøve-wrap",
        name_en: "Test wrap",
        description: "Prøvebeskrivelse.",
        price_ore: 12900,
        origin: "damaskus",
        heat: heat,
        weight_g: 450,
        position: 1
      )
      assert_not item.valid?, "heat #{heat} should be refused (0–3 only)"
    end
  end

  test "price is required" do
    item = MenuItem.new(
      menu_category: @category,
      name: "Prøve-wrap",
      name_en: "Test wrap",
      description: "Prøvebeskrivelse.",
      price_ore: nil,
      origin: "damaskus",
      heat: 1,
      weight_g: 450,
      position: 1
    )
    assert_not item.valid?, "a menu item without a price should be invalid"
  end

  test "available scope only returns available items" do
    visible = seed_item!(@category, name: "Damaskus Kylling Shawarma", available: true)
    seed_item!(@category, name: "Utsolgt wrap", name_en: "Sold-out wrap", available: false)

    scope_ids = MenuItem.available.ids
    assert_includes scope_ids, visible.id
    assert_not_includes scope_ids, MenuItem.find_by(name: "Utsolgt wrap").id
  end

  test "origin stays a lowercase city slug that matches the origins i18n keys" do
    item = seed_item!(@category, origin: "berlin")
    assert item.valid?
    assert_equal "berlin", item.origin
    # The view layer resolves the story with t("origins.#{item.origin}") —
    # lowercase slugs keep that lookup working for all 12 cities.
    assert I18n.exists?("origins.#{item.origin}"), "origins.#{item.origin} must exist in locales"
  end

  test "allergens take only the 14 EU keys, or none alone, and every key has both names" do
    item = seed_item!(@category)

    assert item.update(allergens: "gluten, milk")
    assert_equal %w[gluten milk], item.listed_allergens
    assert item.update(allergens: "none")
    assert_empty item.listed_allergens
    assert_not item.update(allergens: "milk,shellfish"), "an unknown key is refused"
    assert_not item.update(allergens: "none,milk"), "none stands alone"

    assert_equal 14, MenuItem::ALLERGENS.size
    MenuItem::ALLERGENS.each do |key|
      %i[nb en].each { |locale| assert I18n.exists?("menu.allergen_names.#{key}", locale), "#{locale} #{key}" }
    end
  end
end

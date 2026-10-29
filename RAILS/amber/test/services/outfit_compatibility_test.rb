# frozen_string_literal: true

require "test_helper"

class OutfitCompatibilityTest < ActiveSupport::TestCase
  def user(email)
    User.strict_loading(false).create!(email_address: email, password: "password")
  end

  test "proposed combinations can be scored without persisting an outfit" do
    owner = user("compatibility-composition@example.com")
    dress = Item.new(title: "Wool dress", category: "Dresses", material: "wool")
    shoes = Item.new(title: "Leather shoes", category: "Shoes", material: "leather")

    scorer = OutfitCompatibility.new(owner)

    assert_includes 0.0..1.0, scorer.score_items([dress, shoes], weather: "cold")
    assert_equal 0.0, scorer.score_items([])
  end

  test "a dress satisfies the top and bottom roles in category balance" do
    owner = user("compatibility-dress@example.com")
    scorer = OutfitCompatibility.new(owner)
    dress = Item.new(title: "Dress", category: "Dresses")
    shoes = Item.new(title: "Shoes", category: "Shoes")
    shoe_only = scorer.score_items([shoes])
    dress_look = scorer.score_items([dress, shoes])

    assert_operator dress_look, :>, shoe_only
  end

  test "weather compatibility evaluates each garment fit once" do
    owner = user("compatibility-weather-cost@example.com")
    scorer = OutfitCompatibility.new(owner)
    items = [ Item.new(category: "Tops"), Item.new(category: "Shoes") ]
    calls = 0

    GarmentTaxonomy.stub(:weather_fit, ->(_item) { calls += 1; "warm" }) do
      scorer.score_items(items, weather: "cold")
    end

    assert_equal items.size, calls
  end

  test "cold weather accepts cold, mild and dry material classes" do
    scorer = OutfitCompatibility.new(user("compatibility-cold@example.com"))
    items = [
      Item.new(title: "Wool coat", category: "Outerwear", material: "wool"),
      Item.new(title: "Cotton tee", category: "Tops", material: "cotton"),
      Item.new(title: "Leather boots", category: "Shoes", material: "leather"),
    ]

    assert_equal 1.0, scorer.send(:weather_fit, items, "cold")
  end

  test "rain favors shell materials over dry-only materials" do
    scorer = OutfitCompatibility.new(user("compatibility-rain@example.com"))
    shell = Item.new(title: "Shell jacket", category: "Outerwear", material: "nylon shell")
    suede = Item.new(title: "Suede shoes", category: "Shoes", material: "suede")

    assert_equal 0.5, scorer.send(:weather_fit, [shell, suede], "rain")
  end

  test "unknown weather remains neutral instead of guessing" do
    scorer = OutfitCompatibility.new(user("compatibility-unknown-weather@example.com"))

    assert_equal 0.75, scorer.send(:weather_fit, [Item.new(material: "wool")], "monsoon")
  end

  test "an avoid preference lowers the score for a matching combination" do
    owner = user("compatibility-avoid@example.com")
    owner.style_preferences.create!(kind: :avoid, name: "polyester", weight: 1.0)
    scorer = OutfitCompatibility.new(owner)
    avoided = Item.new(title: "Polyester tee", category: "Tops", material: "polyester")
    neutral = Item.new(title: "Linen tee", category: "Tops", material: "linen")

    assert_operator scorer.score_items([avoided]), :<, scorer.score_items([neutral])
  end
end

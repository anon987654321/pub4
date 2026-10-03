# frozen_string_literal: true

require "test_helper"

class StyleAssistantTest < ActiveSupport::TestCase
  def user(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    user.items.destroy_all
    user
  end

  # A wardrobe with enough in every zone that the assistant has real choices.
  def stock(owner)
    3.times { |i| owner.items.create!(title: "Top #{i}", category: "Tops", material: "cotton") }
    3.times { |i| owner.items.create!(title: "Bottom #{i}", category: "Bottoms", material: "denim") }
    3.times { |i| owner.items.create!(title: "Shoe #{i}", category: "Shoes", material: "leather") }
    owner.items.create!(title: "Rain coat", category: "Outerwear", material: "cotton")
    owner.items.create!(title: "Scarf", category: "Accessories", material: "wool")
    owner
  end

  test "the same day suggests the same outfit twice" do
    owner = stock(user("assistant-stable@example.com"))

    first = StyleAssistant.new(owner, date: Date.new(2026, 8, 10)).suggest
    second = StyleAssistant.new(owner, date: Date.new(2026, 8, 10)).suggest

    assert_equal first.item_ids, second.item_ids
    assert first.any?
  end

  test "a different day suggests a different outfit" do
    owner = stock(user("assistant-daily@example.com"))

    week = (0..6).map { |offset| StyleAssistant.new(owner, date: Date.new(2026, 8, 10) + offset).suggest.item_ids }

    assert_operator week.uniq.size, :>, 1, "the suggestion never changed across a week"
  end

  test "cold weather adds a layer and warm weather does not" do
    owner = stock(user("assistant-weather@example.com"))
    date = Date.new(2026, 8, 10)

    cold = StyleAssistant.new(owner, weather: { temp: 4.0, description: "Clear" }, date: date).suggest
    warm = StyleAssistant.new(owner, weather: { temp: 26.0, description: "Clear" }, date: date).suggest

    assert_includes cold.picks.map(&:zone), :outer
    assert_not_includes warm.picks.map(&:zone), :outer
    assert_includes cold.notes, :layering
    assert_includes warm.notes, :no_outerwear
  end

  test "rain vetoes suede shoes even when taste prefers them" do
    owner = user("assistant-rain@example.com")
    owner.items.create!(title: "Top", category: "Tops")
    owner.items.create!(title: "Bottom", category: "Bottoms")
    owner.items.create!(title: "Suede loafers", category: "Shoes", material: "suede", spark_joy: true, times_worn: 30)
    leather = owner.items.create!(title: "Leather boots", category: "Shoes", material: "leather", times_worn: 0)

    suggestion = StyleAssistant.new(owner, weather: { temp: 12.0, description: "Rainy" }).suggest

    shoes = suggestion.picks.find { |pick| pick.zone == :shoes }
    assert_equal leather, shoes.item
  end

  test "a garment worn yesterday is rested when the zone has alternatives" do
    owner = user("assistant-rest@example.com")
    owner.items.create!(title: "Bottom", category: "Bottoms")
    owner.items.create!(title: "Shoes", category: "Shoes")
    yesterday = owner.items.create!(title: "Worn yesterday", category: "Tops", spark_joy: true, times_worn: 20, last_worn_on: Date.current - 1)
    owner.items.create!(title: "Rested top", category: "Tops", times_worn: 0)

    picks = StyleAssistant.new(owner).suggest.picks

    assert_not_includes picks.map(&:item), yesterday
  end

  test "the only garment in a zone comes back even if it was just worn" do
    owner = user("assistant-thin@example.com")
    only = owner.items.create!(title: "Only shoes", category: "Shoes", last_worn_on: Date.current)
    owner.items.create!(title: "Top", category: "Tops")
    owner.items.create!(title: "Bottom", category: "Bottoms")

    picks = StyleAssistant.new(owner).suggest.picks

    assert_includes picks.map(&:item), only
  end

  test "a dress replaces the top and bottom when it outranks them" do
    owner = user("assistant-dress@example.com")
    owner.items.create!(title: "Dull top", category: "Tops", spark_joy: false, times_worn: 0, life_phase: "past-self")
    owner.items.create!(title: "Dull bottom", category: "Bottoms", spark_joy: false, times_worn: 0, life_phase: "past-self")
    dress = owner.items.create!(title: "Favourite dress", category: "Dresses", spark_joy: true, times_worn: 20, last_worn_on: 10.days.ago.to_date, life_phase: "current")
    owner.items.create!(title: "Shoes", category: "Shoes")

    zones = StyleAssistant.new(owner).suggest

    assert_includes zones.items, dress
    assert_equal %i[dress shoes], zones.picks.map(&:zone)
  end

  test "out-of-season garments are not suggested" do
    owner = user("assistant-season@example.com")
    off = Item::SEASONS.excluding("All-Season").find { |season| season != Item.new.current_season }
    owner.items.create!(title: "Wrong season", category: "Tops", season: off)
    right = owner.items.create!(title: "Right season", category: "Tops", season: "All-Season")

    picks = StyleAssistant.new(owner).suggest.picks

    assert_equal [ right ], picks.select { |pick| pick.zone == :top }.map(&:item)
  end

  test "an empty wardrobe suggests nothing rather than raising" do
    owner = user("assistant-empty@example.com")

    suggestion = StyleAssistant.new(owner).suggest

    assert_not suggestion.any?
    assert_empty suggestion.item_ids
  end

  test "picks read head to toe" do
    owner = stock(user("assistant-order@example.com"))

    zones = StyleAssistant.new(owner, weather: { temp: 2.0, description: "Snowy" }).suggest.picks.map(&:zone)

    assert_equal zones.sort_by { |zone| StyleAssistant::ZONES.keys.index(zone) }, zones
  end

  # active_wardrobe keeps declutter-box garments, so the assistant used to dress
  # you in something you had already decided to release.
  test "a garment in the declutter box is never suggested" do
    owner = user("assistant-boxed@example.com")
    boxed = owner.items.create!(title: "Boxed tee", category: "Tops", spark_joy: true, times_worn: 40, lifecycle_state: "declutter_box")
    kept = owner.items.create!(title: "Kept tee", category: "Tops", times_worn: 1)
    owner.items.create!(title: "Bottom", category: "Bottoms")
    owner.items.create!(title: "Shoes", category: "Shoes")

    items = StyleAssistant.new(owner).suggest.items

    assert_not_includes items, boxed
    assert_includes items, kept
  end
end

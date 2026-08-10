# frozen_string_literal: true

require "test_helper"

class WardrobeAnalyticsTest < ActiveSupport::TestCase
  def user(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    user.items.destroy_all
    user
  end

  test "lifecycle buckets and the total come from one grouped count" do
    owner = user("analytics-buckets@example.com")
    2.times { |i| owner.items.create!(title: "Active #{i}", category: "Tops") }
    owner.items.create!(title: "Torn", category: "Tops", lifecycle_state: "repair")
    owner.items.create!(title: "Boxed", category: "Tops", lifecycle_state: "declutter_box")
    owner.items.create!(title: "Memory", category: "Tops", lifecycle_state: "sentimental_archive")
    owner.items.create!(title: "Winter", category: "Outerwear", lifecycle_state: "seasonal_archive")
    owner.items.create!(title: "Gone", category: "Tops", lifecycle_state: "sold")

    summary = WardrobeAnalytics.new(owner).summary

    assert_equal 7, summary[:total_items]
    assert_equal 6, summary[:active_items], "released garments are not active"
    assert_equal 1, summary[:repair]
    assert_equal 1, summary[:declutter_box]
    assert_equal 1, summary[:sentimental_archive]
    assert_equal 1, summary[:seasonal_archived]
  end

  test "underused matches the Ruby predicate it replaced" do
    owner = user("analytics-underused@example.com")
    [ nil, 0, 1, 2, 3, 10 ].each_with_index { |worn, i| owner.items.create!(title: "Item #{i}", category: "Tops", times_worn: worn) }

    summary = WardrobeAnalytics.new(owner).summary

    assert_equal owner.items.to_a.count(&:underused?), summary[:underused]
    assert_equal 4, summary[:underused]
    assert_equal 2, summary[:never_worn]
  end

  test "cost per wear averages each garment's own ratio and ignores the unpriced" do
    owner = user("analytics-cpw@example.com")
    owner.items.create!(title: "Dear", category: "Dresses", price_cents: 90_000, times_worn: 2)   # 450
    owner.items.create!(title: "Cheap", category: "Tops", price_cents: 10_000, times_worn: 50)    # 2
    owner.items.create!(title: "Unpriced", category: "Tops", times_worn: 4)
    owner.items.create!(title: "Unworn", category: "Tops", price_cents: 50_000, times_worn: 0)

    assert_in_delta 226.0, WardrobeAnalytics.new(owner).summary[:cost_per_wear], 0.01
  end

  test "cost per wear is nil rather than zero when nothing qualifies" do
    owner = user("analytics-cpw-none@example.com")
    owner.items.create!(title: "Unworn", category: "Tops", price_cents: 50_000, times_worn: 0)

    assert_nil WardrobeAnalytics.new(owner).summary[:cost_per_wear]
  end

  test "an empty wardrobe reports zeroes, not nils" do
    summary = WardrobeAnalytics.new(user("analytics-empty@example.com")).summary

    assert_equal 0, summary[:total_items]
    assert_equal 0, summary[:active_items]
    assert_equal 0, summary[:underused]
    assert_empty summary[:tips]
  end

  test "tips fire off the same counts the summary reports" do
    owner = user("analytics-tips@example.com")
    owner.items.create!(title: "Never worn", category: "Tops")
    owner.items.create!(title: "Torn", category: "Tops", lifecycle_state: "repair")
    owner.items.create!(title: "Boxed", category: "Tops", lifecycle_state: "declutter_box")

    summary = WardrobeAnalytics.new(owner).summary

    assert_equal "rules", summary[:tips_source]
    # Through the keys: the coach is translated and the suite runs under nb.
    assert_includes summary[:tips], I18n.t("coach.never_worn")
    assert_includes summary[:tips], I18n.t("coach.repair")
    assert_includes summary[:tips], I18n.t("coach.declutter_box", count: 1)
  end

  test "one wardrobe's counts do not leak into another's" do
    mine = user("analytics-mine@example.com")
    theirs = user("analytics-theirs@example.com")
    3.times { |i| theirs.items.create!(title: "Theirs #{i}", category: "Tops") }
    mine.items.create!(title: "Mine", category: "Tops")

    assert_equal 1, WardrobeAnalytics.new(mine).summary[:total_items]
  end
end

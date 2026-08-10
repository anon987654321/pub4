# frozen_string_literal: true

require "test_helper"

class WardrobeChartsTest < ActiveSupport::TestCase
  def user(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    user.items.destroy_all
    user
  end

  test "category mix counts the active wardrobe and ranks it" do
    owner = user("charts-mix@example.com")
    3.times { |i| owner.items.create!(title: "Tee #{i}", category: "Tops") }
    owner.items.create!(title: "Jeans", category: "Bottoms")
    owner.items.create!(title: "Sold coat", category: "Outerwear", lifecycle_state: "sold")

    bars = WardrobeCharts.new(owner).category_mix

    assert_equal %w[Tops Bottoms], bars.map(&:label)
    assert_equal [ 3, 1 ], bars.map(&:value)
    # Shares are normalised inside the figure, so the tallest bar is always full.
    assert_in_delta 1.0, bars.first.share, 0.0001
    assert_in_delta 0.3333, bars.last.share, 0.0001
  end

  test "wear distribution buckets every active garment exactly once" do
    owner = user("charts-usage@example.com")
    [ 0, 0, 1, 2, 4, 9, 15, 40 ].each_with_index do |worn, i|
      owner.items.create!(title: "Item #{i}", category: "Tops", times_worn: worn)
    end

    bars = WardrobeCharts.new(owner).wear_distribution

    assert_equal WardrobeCharts::WEAR_BUCKETS.map(&:first), bars.map(&:key)
    assert_equal [ 2, 2, 1, 1, 1, 1 ], bars.map(&:value)
    assert_equal 8, bars.sum(&:value)
  end

  test "cost per wear ranks the worst value first and skips unpriced garments" do
    owner = user("charts-cost@example.com")
    owner.items.create!(title: "Bargain", category: "Tops", price_cents: 10_000, times_worn: 50)
    dear = owner.items.create!(title: "Gala dress", category: "Dresses", price_cents: 90_000, times_worn: 2)
    owner.items.create!(title: "Unpriced", category: "Tops", times_worn: 4)
    owner.items.create!(title: "Never worn", category: "Tops", price_cents: 50_000, times_worn: 0)

    bars = WardrobeCharts.new(owner).cost_per_wear

    assert_equal [ "Gala dress", "Bargain" ], bars.map(&:label)
    assert_in_delta 450.0, bars.first.value, 0.01
    assert_equal dear, bars.first.item
  end

  test "idle ranks underused garments by how long they have sat" do
    owner = user("charts-idle@example.com")
    recent = owner.items.create!(title: "Worn last week", category: "Tops", times_worn: 1, last_worn_on: 7.days.ago.to_date)
    stale = owner.items.create!(title: "Worn last year", category: "Tops", times_worn: 2, last_worn_on: 400.days.ago.to_date)
    owner.items.create!(title: "Workhorse", category: "Tops", times_worn: 30, last_worn_on: 300.days.ago.to_date)

    bars = WardrobeCharts.new(owner).idle

    assert_equal [ stale, recent ], bars.map(&:item)
    assert_equal 400, bars.first.value
    assert_equal 7, bars.last.value
  end

  test "a never-worn garment is still dated from purchase" do
    owner = user("charts-idle-fallback@example.com")
    item = owner.items.create!(title: "Impulse buy", category: "Tops", times_worn: 0, purchase_date: 200.days.ago.to_date)

    assert_equal 200, WardrobeCharts.new(owner).idle_days(item)
  end

  test "an empty wardrobe produces empty series rather than dividing by zero" do
    owner = user("charts-empty@example.com")

    figures = WardrobeCharts.new(owner).figures

    assert_empty figures[:category_mix]
    assert_empty figures[:cost_per_wear]
    assert_empty figures[:idle]
    # The distribution keeps its buckets — an all-zero histogram is a reading.
    assert_equal 6, figures[:wear_distribution].size
    assert_equal [ 0.0 ], figures[:wear_distribution].map(&:share).uniq
  end

  test "shares never exceed one" do
    owner = user("charts-share@example.com")
    5.times { |i| owner.items.create!(title: "Item #{i}", category: "Tops", times_worn: i, price_cents: 1000 * (i + 1)) }

    WardrobeCharts.new(owner).figures.each_value do |bars|
      bars.each { |bar| assert_includes 0.0..1.0, bar.share, "#{bar.key} share out of range" }
    end
  end
end

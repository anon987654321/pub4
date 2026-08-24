# frozen_string_literal: true

require "test_helper"

# The record that makes cost-per-wear mean anything, and it had no test.
#
# Item#wear! writes one of these inside a transaction that also increments
# times_worn and stamps last_worn_on. Two counters for the same fact, in the same
# transaction, and nothing checked they stay in step -- which is the arrangement
# where they quietly do not.
class WearLogTest < ActiveSupport::TestCase
  setup do
    @user = User.strict_loading(false).create!(email_address: "wear@amber.test", password: "password123")
    @item = Item.create!(user: @user, title: "Wool coat", category: "Outerwear")
  end

  test "a wear log records who wore what and when" do
    log = WearLog.create!(user: @user, item: @item, worn_on: Date.current)

    assert_equal @user, log.user
    assert_equal @item, log.item
  end

  test "a date is required, because a wear with no date counts toward nothing" do
    log = WearLog.new(user: @user, item: @item)

    assert_not log.valid?
    assert_includes log.errors.attribute_names, :worn_on
  end

  test "an outfit is optional, because a garment can be worn on its own" do
    assert WearLog.new(user: @user, item: @item, worn_on: Date.current).valid?
  end

  test "both the wearer and the garment are required" do
    assert_not WearLog.new(item: @item, worn_on: Date.current).valid?
    assert_not WearLog.new(user: @user, worn_on: Date.current).valid?
  end

  test "context is bounded so a note cannot become an essay" do
    assert WearLog.new(user: @user, item: @item, worn_on: Date.current, context: "a" * 300).valid?
    assert_not WearLog.new(user: @user, item: @item, worn_on: Date.current, context: "a" * 301).valid?
  end

  # Two logs on one day is a real thing — changed after work — and a uniqueness
  # rule here would silently drop the second wear from the count.
  test "a garment may be worn twice in one day" do
    WearLog.create!(user: @user, item: @item, worn_on: Date.current)

    assert WearLog.new(user: @user, item: @item, worn_on: Date.current).valid?
  end

  test "recent orders by the day worn and breaks ties by when it was logged" do
    old = WearLog.create!(user: @user, item: @item, worn_on: 3.days.ago.to_date)
    yesterday = WearLog.create!(user: @user, item: @item, worn_on: 1.day.ago.to_date)
    later_entry = WearLog.create!(user: @user, item: @item, worn_on: 1.day.ago.to_date)

    assert_equal [ later_entry, yesterday, old ], WearLog.recent.to_a
  end

  # --- the two counters -----------------------------------------------------

  test "wearing an item writes a log and moves the counter together" do
    @item.update!(times_worn: 2)

    assert_difference [ "WearLog.count", "@item.reload.times_worn" ], 1 do
      @item.wear!
    end
  end

  test "wearing an item from nothing starts the counter at one" do
    assert_nil @item.times_worn
    @item.wear!

    assert_equal 1, @item.reload.times_worn
    assert_equal 1, WearLog.where(item: @item).count
  end

  test "the log count and the counter stay in step over several wears" do
    5.times { @item.wear! }

    assert_equal 5, @item.reload.times_worn
    assert_equal 5, WearLog.where(item: @item).count,
                   "times_worn and the wear logs are two records of one fact and have diverged"
  end

  test "wearing stamps the day and returns the item to the active state" do
    @item.update!(lifecycle_state: "seasonal_archive")
    @item.wear!(worn_on: Date.new(2026, 8, 16))

    assert_equal Date.new(2026, 8, 16), @item.reload.last_worn_on
    assert_equal "active", @item.lifecycle_state, "wearing something does not take it out of the archive"
  end

  test "a wear can name the outfit it was part of" do
    outfit = Outfit.create!(user: @user, name: "Rain day")
    @item.wear!(outfit:)

    # Loaded explicitly: WearLog is strict_loading, so reading through the
    # association off a bare instance raises rather than answering.
    assert_equal outfit, WearLog.where(item: @item).includes(:outfit).first.outfit
  end

  test "a wear can carry the note the wearer left" do
    @item.wear!(context: "too warm for the office")

    assert_equal "too warm for the office", WearLog.where(item: @item).first.context
  end

  # The whole point of counting wears.
  test "cost per wear falls as the garment is worn" do
    @item.update!(price_cents: 60_000)

    assert_nil @item.cost_per_wear, "an unworn garment has no cost per wear, not a division by zero"

    @item.wear!
    assert_in_delta 600.0, @item.reload.cost_per_wear, 0.01

    5.times { @item.wear! }
    assert_in_delta 100.0, @item.reload.cost_per_wear, 0.01
  end

  test "a garment with no price has no cost per wear rather than a zero" do
    @item.wear!

    assert_nil @item.reload.cost_per_wear
  end

  test "destroying an item takes its wear history with it" do
    @item.wear!

    assert_difference "WearLog.count", -1 do
      @item.destroy!
    end
  end
end
